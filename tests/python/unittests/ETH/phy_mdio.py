"""Behavioural MDIO side of a PHY, for the tests of the MDIO master."""

import cocotb
from cocotb.triggers import RisingEdge

from tests.python.unittests.dut import Dut

PREAMBLE_ONES = 32
OPCODE_READ = 2
OPCODE_WRITE = 1
FIELD_BITS = 12
DATA_BITS = 16


class MdioPhy:
    """A PHY that answers Clause 22 frames at a given address.

    Attributes
    ----------
    regs : dict[int, int]
        Register file of the PHY.
    frames : list[tuple[int, int, int]]
        Each frame seen as (opcode, phy address, register address).
    """

    def __init__(self, dut: Dut, address: int, regs: dict[int, int]) -> None:
        """Start the model on the MDC and MDIO pins of the design.

        Parameters
        ----------
        dut : Dut
            The design under test.
        address : int
            PHY address the model answers to.
        regs : dict[int, int]
            Initial register file.
        """
        self.regs = regs
        self.frames: list[tuple[int, int, int]] = []
        self._dut = dut
        self._address = address
        self._phy_out = 1
        dut.i_mdio.value = 1
        cocotb.start_soon(self._line())
        cocotb.start_soon(self._protocol())

    async def _line(self) -> None:
        """Resolve MDIO: the master when it drives, else the PHY."""
        while True:
            await RisingEdge(self._dut.i_clk)
            if int(self._dut.o_mdio_oe.value):
                self._dut.i_mdio.value = int(self._dut.o_mdio_out.value)
            else:
                self._dut.i_mdio.value = self._phy_out

    async def _sample(self) -> int:
        """Return the master bit at the next rising edge of MDC.

        Returns
        -------
        int
            The line level the master drives, 1 if it is released.
        """
        await RisingEdge(self._dut.o_mdc)
        if int(self._dut.o_mdio_oe.value):
            return int(self._dut.o_mdio_out.value)
        return 1

    async def _header(self) -> tuple[int, int, int]:
        """Wait for a start of frame and read opcode and addresses.

        Returns
        -------
        tuple[int, int, int]
            Opcode, PHY address and register address.
        """
        ones = 0
        while True:
            bit = await self._sample()
            if bit:
                ones += 1
            elif ones >= PREAMBLE_ONES and await self._sample():
                break
            else:
                ones = 0
        fields = 0
        for _ in range(FIELD_BITS):
            fields = (fields << 1) | await self._sample()
        return fields >> 10, (fields >> 5) & 0x1F, fields & 0x1F

    async def _read_reply(self, reg: int) -> None:
        """Drive the turnaround and the data of a read."""
        value = self.regs.get(reg, 0)
        # The PHY drives after a rising edge; the master samples later.
        await RisingEdge(self._dut.o_mdc)
        self._phy_out = 0
        for index in range(DATA_BITS):
            await RisingEdge(self._dut.o_mdc)
            self._phy_out = (value >> (DATA_BITS - 1 - index)) & 1
        await RisingEdge(self._dut.o_mdc)
        self._phy_out = 1

    async def _write_frame(self, phy: int, reg: int) -> None:
        """Take the turnaround and the data of a write.

        Parameters
        ----------
        phy : int
            PHY address of the frame.
        reg : int
            Register address of the frame.
        """
        await self._sample()
        await self._sample()
        value = 0
        for _ in range(DATA_BITS):
            value = (value << 1) | await self._sample()
        if phy == self._address:
            self.regs[reg] = value

    async def _protocol(self) -> None:
        """Serve frames forever."""
        while True:
            opcode, phy, reg = await self._header()
            self.frames.append((opcode, phy, reg))
            if opcode == OPCODE_READ and phy == self._address:
                await self._read_reply(reg)
            elif opcode == OPCODE_WRITE:
                await self._write_frame(phy, reg)
