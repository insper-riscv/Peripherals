"""LCD 16x2: registradores, fila, espera, atrasos e interrupção.

O clock é de 10 MHz e o pulso de EN dura 500 ns, o que cobre o atraso
de dados do chip mais os dois ciclos do sincronizador. O modelo do
HD44780 confere os
tempos do barramento e recusa escritas com o chip ocupado.
"""

import cocotb

from tests.python.unittests.LCD import common as c
from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import LcdDut

FIFO_DEPTH = 4
DELAY_RESET = 500
DELAY_LONG_RESET = 20_000
BURST = 12
TOO_SHORT_DELAY = 5
HELLO = "HELLO"
DELAY_LONG_SHORT = 3
WORLD = "WORLD"
CHARS_LINE = 16
SETTLE_CYCLES = 50
DRAIN_LIMIT = 200_000
CHIP_RECOVER_CYCLES = 1000


@cocotb.test()
async def reset_state(dut: LcdDut) -> None:
    """Confira registradores e pinos logo depois do reset."""
    await c.start(dut)
    status = await bus.read(dut, c.STATUS)
    check(status == c.FIFO_EMPTY, f"STATUS {status:#x}")
    control = await bus.read(dut, c.CONTROL)
    check(control == c.POLL_ENABLE | c.LCD_ON, f"CONTROL {control:#x}")
    check(await bus.read(dut, c.DELAY) == DELAY_RESET, "DELAY de reset")
    check(
        await bus.read(dut, c.DELAY_LONG) == DELAY_LONG_RESET,
        "DELAY_LONG de reset",
    )
    check(int(dut.o_lcd_en.value) == 0, "EN em repouso")
    check(int(dut.o_lcd_rw.value) == 0, "RW em repouso")
    check(int(dut.o_lcd_data_oe.value) == 0, "dados soltos em repouso")
    check(int(dut.o_lcd_on.value) == 1, "LCD_ON ligado")
    check(int(dut.o_lcd_blon.value) == 0, "LCD_BLON desligado")
    check(int(dut.o_irq.value) == 0, "sem interrupção habilitada")
    for address in (c.COMMAND, c.DATA, 6, 7):
        check(await bus.read(dut, address) == 0, f"endereço {address} lê zero")


@cocotb.test()
async def powers_up_and_prints_with_busy_polling(dut: LcdDut) -> None:
    """Inicialize por software e escreva duas linhas."""
    chip = await c.start(dut, power_up_ns=15_000_000)
    await bus.cycles(dut, c.POWER_UP_CYCLES)
    await c.manual_init(dut)
    await c.text(dut, HELLO)
    await c.put(dut, c.COMMAND, c.SET_LINE_TWO)
    await c.text(dut, WORLD)
    await c.wait_idle(dut)
    check(chip.violations == [], f"violações {chip.violations}")
    check(
        chip.state.display_on and chip.state.two_lines,
        "função e display ligados",
    )
    check(chip.line(0).rstrip() == HELLO, f"linha 1 {chip.line(0)!r}")
    check(chip.line(1).rstrip() == WORLD, f"linha 2 {chip.line(1)!r}")
    check(chip.busy_polls > 0, "o flag de ocupado foi lido")
    check(not c.flag(await bus.read(dut, c.STATUS), c.TIMEOUT), "sem TIMEOUT")


@cocotb.test()
async def clear_and_entry_mode_take_effect(dut: LcdDut) -> None:
    """Limpe a tela, escreva e recue o cursor com o entry mode."""
    chip = await c.start(dut)
    await c.manual_init(dut)
    await c.text(dut, "ABC")
    await c.put(dut, c.COMMAND, c.CLEAR)
    await c.text(dut, "Z")
    await c.wait_idle(dut)
    check(chip.line(0).rstrip() == "Z", f"linha 1 {chip.line(0)!r}")
    check(chip.violations == [], f"violações {chip.violations}")
    await c.put(dut, c.COMMAND, 0x04)
    await c.put(dut, c.COMMAND, c.SET_LINE_ONE | 5)
    await c.text(dut, "ab")
    await c.wait_idle(dut)
    ddram = chip.state.ddram
    check(ddram[5] == ord("a") and ddram[4] == ord("b"), "decremento")
    check(chip.violations == [], f"violações {chip.violations}")


@cocotb.test()
async def full_queue_drops_and_flags(dut: LcdDut) -> None:
    """Descarte o excesso de uma rajada e acenda DROPPED."""
    chip = await c.start(dut)
    levels: list[int] = []
    for index in range(BURST):
        await bus.write(dut, c.DATA, ord("a") + index)
        status = await bus.read(dut, c.STATUS)
        levels.append((status >> c.LEVEL_SHIFT) & c.LEVEL_MASK)
    status = await bus.read(dut, c.STATUS)
    check(c.flag(status, c.DROPPED), "DROPPED aceso")
    check(max(levels) == FIFO_DEPTH, f"níveis {levels}")
    await c.wait_idle(dut)
    kept = chip.line(0).rstrip()
    check(0 < len(kept) < BURST, f"gravou {kept!r}")
    check(
        kept == "".join(chr(ord("a") + i) for i in range(len(kept))), "ordem"
    )
    await bus.write(dut, c.STATUS, c.DROPPED)
    check(
        not c.flag(await bus.read(dut, c.STATUS), c.DROPPED), "DROPPED limpo"
    )
    check(chip.violations == [], f"violações {chip.violations}")


@cocotb.test()
async def fixed_delay_mode(dut: LcdDut) -> None:
    """Com atraso fixo, o valor curto falha e o padrão basta."""
    chip = await c.start(dut)
    await bus.write(dut, c.CONTROL, c.LCD_ON)
    check(await bus.read(dut, c.CONTROL) == c.LCD_ON, "poll desligado")
    await bus.write(dut, c.DELAY, TOO_SHORT_DELAY)
    check(await bus.read(dut, c.DELAY) == TOO_SHORT_DELAY, "DELAY escrito")
    await c.text(dut, "xy")
    await c.wait_idle(dut)
    check(len(chip.violations) == 1, f"violações {chip.violations}")
    check(chip.busy_polls == 0, "sem leitura do ocupado")
    chip.violations.clear()
    await bus.cycles(dut, CHIP_RECOVER_CYCLES)
    await bus.write(dut, c.DELAY, DELAY_RESET)
    await c.put(dut, c.COMMAND, c.CLEAR)
    await c.text(dut, "ok")
    await c.wait_idle(dut)
    check(chip.violations == [], f"violações {chip.violations}")
    check(chip.line(0).rstrip() == "ok", f"linha 1 {chip.line(0)!r}")
    await bus.write(dut, c.DELAY_LONG, DELAY_LONG_SHORT)
    check(
        await bus.read(dut, c.DELAY_LONG) == DELAY_LONG_SHORT,
        "DELAY_LONG escrito",
    )
    await bus.cycles(dut, CHIP_RECOVER_CYCLES)
    await c.put(dut, c.COMMAND, c.CLEAR)
    await c.text(dut, "q")
    await c.wait_idle(dut)
    check(len(chip.violations) == 1, "limpar com atraso curto é flagrado")


@cocotb.test()
async def pins_follow_control(dut: LcdDut) -> None:
    """Os pinos LCD_ON e LCD_BLON seguem CONTROL."""
    chip = await c.start(dut)
    await bus.write(dut, c.CONTROL, c.POLL_ENABLE | c.BACKLIGHT)
    check(int(dut.o_lcd_on.value) == 0, "LCD_ON desligado")
    check(int(dut.o_lcd_blon.value) == 1, "LCD_BLON ligado")
    await c.put(dut, None, ord("k"))
    seen_oe = seen_rw = False
    for _ in range(SETTLE_CYCLES):
        await bus.cycles(dut, 1)
        seen_oe |= int(dut.o_lcd_data_oe.value) == 1
        seen_rw |= int(dut.o_lcd_rw.value) == 1
        check(
            not (int(dut.o_lcd_data_oe.value) and int(dut.o_lcd_rw.value)),
            "conflito",
        )
    check(seen_oe and seen_rw, "escreveu e leu o ocupado")
    await c.wait_idle(dut)
    check(chip.violations == [], f"violações {chip.violations}")


@cocotb.test()
async def empty_interrupt(dut: LcdDut) -> None:
    """Siga a fila vazia na interrupção enquanto habilitada."""
    await c.start(dut)
    await bus.write(dut, c.CONTROL, c.IRQ_ENABLE | c.POLL_ENABLE | c.LCD_ON)
    check(int(dut.o_irq.value) == 1, "fila vazia pede interrupção")
    for index in range(BURST // 3):
        await bus.write(dut, c.DATA, ord("0") + index)
    check(int(dut.o_irq.value) == 0, "fila com palavras não pede")
    for _ in range(DRAIN_LIMIT):
        await bus.cycles(dut, 1)
        if int(dut.o_irq.value):
            break
    status = await bus.read(dut, c.STATUS)
    check(c.flag(status, c.FIFO_EMPTY), "interrupção com a fila vazia")
    await bus.write(dut, c.CONTROL, c.POLL_ENABLE | c.LCD_ON)
    check(int(dut.o_irq.value) == 0, "desabilitada")
    await c.wait_idle(dut)
