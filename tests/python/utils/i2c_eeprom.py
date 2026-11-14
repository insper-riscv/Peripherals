"""Behavioural model of an I2C EEPROM (24Cxx family) for the tests.

The model watches the resolved lines of the testbench once per system
clock and drives the slave side of the open-drain bus, so the clock of
the bus must be slower than the system clock by a few cycles.
"""

from dataclasses import dataclass, field

import cocotb
from cocotb.triggers import RisingEdge, Timer

from tests.python.utils.dut import I2cDut

DEVICE_ADDRESS = 0x50
BYTE_BITS = 8
ACK_END_BIT = BYTE_BITS + 1
MSB = 0x80


@dataclass(frozen=True)
class Geometry:
    """Organisation of the array.

    Attributes
    ----------
    size : int
        Size of the array in bytes.
    page : int
        Page size in bytes, a power of two.
    addr_bytes : int
        Address bytes of the protocol, 1 or 2.
    write_cycles : int
        System clock cycles the internal write cycle lasts.
    """

    size: int = 256
    page: int = 8
    addr_bytes: int = 1
    write_cycles: int = 400


@dataclass
class Counters:
    """Events the model has seen.

    Attributes
    ----------
    starts : int
        Start and repeated start conditions.
    stops : int
        Stop conditions.
    nacked_addresses : int
        Address bytes answered with NACK.
    """

    starts: int = 0
    stops: int = 0
    nacked_addresses: int = 0


@dataclass
class _Flags:
    """Mode of the slave."""

    receiving: bool = False
    sending: bool = False
    ignoring: bool = True
    writing: bool = False


@dataclass
class _Byte:
    """Progress inside the byte on the line."""

    bit_count: int = 0
    shift: int = 0
    byte_index: int = 0
    master_acked: bool = False


@dataclass
class _State:
    """Protocol state of the slave."""

    pointer: int = 0
    staged: list[tuple[int, int]] = field(
        default_factory=list[tuple[int, int]]
    )
    busy_left: int = 0
    stretch_left: int = 0
    sda_low: int = 0
    f: _Flags = field(default_factory=_Flags)
    b: _Byte = field(default_factory=_Byte)


class I2cEeprom:
    """An EEPROM with one or two address bytes and page write.

    Attributes
    ----------
    memory : bytearray
        Contents of the array, erased bytes are 0xFF.
    stretch_cycles : int
        Cycles the slave holds SCL low after each byte, zero for none.
    fight_bit : int | None
        When set, the slave also drives SDA low at the fall of SCL that
        precedes this bit of the address byte, as a second master would.
    counts : Counters
        Start, stop and refused address counts.
    """

    def __init__(
        self,
        dut: I2cDut,
        size: int = 256,
        page: int = 8,
        addr_bytes: int = 1,
        write_cycles: int = 400,
    ) -> None:
        """Create the model.

        Parameters
        ----------
        dut : I2cDut
            The testbench.
        size : int
            Size of the array in bytes.
        page : int
            Page size in bytes, a power of two.
        addr_bytes : int
            Address bytes of the protocol, 1 or 2.
        write_cycles : int
            System clock cycles the internal write cycle lasts.
        """
        self.dut = dut
        self.geometry = Geometry(size, page, addr_bytes, write_cycles)
        self.memory = bytearray([0xFF] * size)
        self.stretch_cycles = 0
        self.fight_bit: int | None = None
        self.counts = Counters()
        self._s = _State()

    def start(self) -> None:
        """Start the model as a background coroutine."""
        cocotb.start_soon(self._run())

    def _next_pointer(self) -> int:
        """Return the address after the current one inside the page."""
        page = self.geometry.page
        base = self._s.pointer & ~(page - 1)
        return base | ((self._s.pointer + 1) & (page - 1))

    def _on_start(self) -> None:
        """Handle a start or repeated start condition."""
        s = self._s
        self.counts.starts += 1
        s.f.ignoring = False
        s.f.writing = False
        s.b.byte_index = 0
        s.b.bit_count = 0
        s.b.shift = 0
        s.f.sending = False
        s.f.receiving = True
        s.sda_low = 0

    def _on_stop(self) -> None:
        """Handle a stop condition and start the write cycle."""
        s = self._s
        self.counts.stops += 1
        if s.f.writing and s.staged:
            for address, value in s.staged:
                self.memory[address] = value
            s.busy_left = self.geometry.write_cycles
        s.staged = []
        s.f.writing = False
        s.f.ignoring = True
        s.f.receiving = False
        s.f.sending = False
        s.sda_low = 0

    def _take_byte(self) -> bool:
        """Process a complete byte received and return the ACK."""
        s = self._s
        value = s.b.shift
        if s.b.byte_index == 0:
            if (value >> 1) != DEVICE_ADDRESS or s.busy_left > 0:
                self.counts.nacked_addresses += 1
                s.f.ignoring = True
                s.f.receiving = False
                return False
            s.f.sending = bool(value & 1)
            s.f.writing = not s.f.sending
            return True
        if s.b.byte_index <= self.geometry.addr_bytes:
            if s.b.byte_index == 1:
                s.pointer = 0
            s.pointer = ((s.pointer << 8) | value) % self.geometry.size
            return True
        s.staged.append((s.pointer, value))
        s.pointer = self._next_pointer()
        return True

    def _drive_data_bit(self) -> None:
        """Drive the next bit of the byte sent, or free the ACK bit."""
        s = self._s
        if s.b.bit_count < BYTE_BITS:
            bit = (s.b.shift >> (BYTE_BITS - 1 - s.b.bit_count)) & 1
            s.sda_low = int(bit == 0)
        else:
            s.sda_low = 0
            s.stretch_left = self.stretch_cycles

    def _on_fall(self) -> None:
        """Handle the falling edge of SCL."""
        s = self._s
        if s.f.ignoring:
            s.sda_low = 0
            return
        if s.f.receiving and s.b.bit_count < BYTE_BITS:
            s.sda_low = 0
        if s.b.bit_count == BYTE_BITS and s.f.receiving:
            s.sda_low = int(self._take_byte())
            s.stretch_left = self.stretch_cycles
        elif s.b.bit_count == ACK_END_BIT:
            self._on_ack_end()
        elif s.f.sending:
            self._drive_data_bit()
        if (
            self.fight_bit == s.b.bit_count
            and s.f.receiving
            and s.b.byte_index == 0
        ):
            s.sda_low = 1

    def _on_ack_end(self) -> None:
        """Handle the fall of SCL that ends the acknowledge bit."""
        s = self._s
        s.sda_low = 0
        was_receiving = s.f.receiving
        s.b.bit_count = 0
        if was_receiving:
            s.b.byte_index += 1
            s.b.shift = 0
            if s.f.sending:
                s.f.receiving = False
                self._load_next()
        elif s.b.master_acked:
            self._load_next()
        else:
            s.f.ignoring = True
            s.f.sending = False

    def _load_next(self) -> None:
        """Put the next byte to send on the line, MSB first."""
        s = self._s
        s.b.shift = self.memory[s.pointer]
        s.pointer = (s.pointer + 1) % self.geometry.size
        s.f.sending = True
        s.sda_low = int((s.b.shift & MSB) == 0)

    def _on_rise(self, sda: int) -> None:
        """Handle the rising edge of SCL."""
        s = self._s
        if s.f.ignoring:
            return
        if s.b.bit_count < BYTE_BITS and s.f.receiving:
            s.b.shift = ((s.b.shift << 1) | sda) & 0xFF
        elif s.b.bit_count == BYTE_BITS and not s.f.receiving:
            s.b.master_acked = sda == 0
        s.b.bit_count += 1

    def _on_scl_high(self, sda: tuple[int, int]) -> None:
        """Detect a start or a stop while SCL stays high.

        Parameters
        ----------
        sda : tuple[int, int]
            Previous and current level of SDA.
        """
        if sda[0] and not sda[1]:
            self._on_start()
        elif not sda[0] and sda[1]:
            self._on_stop()

    def _dispatch(self, scl: tuple[int, int], sda: tuple[int, int]) -> None:
        """Run the handler of the event between two samples of the bus.

        Parameters
        ----------
        scl : tuple[int, int]
            Previous and current level of SCL.
        sda : tuple[int, int]
            Previous and current level of SDA.
        """
        if scl[0] and scl[1]:
            self._on_scl_high(sda)
        elif scl[1] and not scl[0]:
            self._on_rise(sda[1])
        elif scl[0] and not scl[1]:
            self._on_fall()

    async def _run(self) -> None:
        """Follow the bus until the end of the simulation."""
        scl_prev = 1
        sda_prev = 1
        s = self._s
        while True:
            await RisingEdge(self.dut.i_clk)
            await Timer(1, unit="ns")
            scl = int(self.dut.o_scl.value)
            sda = int(self.dut.o_sda.value)
            s.busy_left = max(s.busy_left - 1, 0)
            self._dispatch((scl_prev, scl), (sda_prev, sda))
            s.stretch_left = max(s.stretch_left - 1, 0)
            self.dut.i_slave_scl_low.value = int(s.stretch_left > 0)
            self.dut.i_slave_sda_low.value = s.sda_low
            scl_prev = scl
            sda_prev = sda
