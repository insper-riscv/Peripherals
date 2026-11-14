/* SPDX-License-Identifier: Apache-2.0
 * Teste do driver USB no computador, contra um MODELO escrito junto com o driver.
 *
 * SUPOSICAO: o modelo do CY7C67200 abaixo (portas HPI, ponteiro com
 * autoincremento, mailbox, flag de mailbox no bit 0 do status, comandos do BIOS)
 * reflete o que o autor lembra do chip, sem datasheet. Passar neste teste prova
 * que o driver e coerente com o modelo e com a ponte do RTL (usb_regs.vhd), NAO
 * que o chip real se comporta assim. O modelo da ponte segue o RTL (secao 2 do
 * doc da ponte): leitura de porta so pede o acesso e o dado fica em RDATA; pedido
 * com BUSY ligado e descartado e liga ERROR.
 */
#include "rv32_usb.h"

#include <assert.h>
#include <stdio.h>
#include <string.h>

#define BASE 0x40000000u
#define MEM_WORDS 0x8000

/* Perfil que o modelo implementa (os mesmos valores de rv32_usb_unverified.c). */
static const rv32_usb_profile_t MODEL_PROFILE = {
    .mailbox_in_flag = 0x0001,
    .param_address = 0x0144,
    .ack = 0x0FED,
    .nak = 0xDEAD,
    .cmd_jump_to_code = 0xCE00,
    .cmd_exec_interrupt = 0xCE01,
    .cmd_read_ctrl_reg = 0xCE02,
    .cmd_write_ctrl_reg = 0xCE03,
    .cmd_call_code = 0xCE04,
};

static struct {
    /* ponte */
    uint32_t ctrl, irq_mask, timing, rdata;
    bool error;
    unsigned busy_left;
    unsigned busy_per_access;
    bool force_error_next;
    unsigned accesses;
    unsigned discarded;
    /* chip */
    uint16_t mem[MEM_WORDS];
    uint16_t ctrl_regs[16];
    uint16_t ptr;
    bool mbx_full;
    uint16_t mbx_reply;
    unsigned mbx_delay_left;
    unsigned mbx_delay;
    bool bios_silent;
    bool bios_nak;
    bool corrupt_writes;
    uint16_t jump_target;
    uint16_t call_target;
    unsigned last_status_flags;
} m;

static void model_reset(void)
{
    memset(&m, 0, sizeof(m));
    m.ctrl = 1;
    m.busy_per_access = 2;
}

static void bios_command(uint16_t cmd)
{
    const uint16_t *p = &m.mem[MODEL_PROFILE.param_address / 2];

    if (m.bios_silent) {
        return;
    }

    m.mbx_reply = m.bios_nak ? MODEL_PROFILE.nak : MODEL_PROFILE.ack;
    m.mbx_full = true;
    m.mbx_delay_left = m.mbx_delay;

    if (m.bios_nak) {
        return;
    }

    if (cmd == MODEL_PROFILE.cmd_jump_to_code) {
        m.jump_target = p[0];
    } else if (cmd == MODEL_PROFILE.cmd_call_code) {
        m.call_target = p[0];
    } else if (cmd == MODEL_PROFILE.cmd_write_ctrl_reg) {
        m.ctrl_regs[p[0] & 15u] = p[1];
    } else if (cmd == MODEL_PROFILE.cmd_read_ctrl_reg) {
        m.mem[MODEL_PROFILE.param_address / 2] = m.ctrl_regs[p[0] & 15u];
    }
}

static uint16_t chip_read(unsigned port)
{
    switch (port) {
    case RV32_USB_PORT_DATA: {
        uint16_t v = m.mem[(m.ptr / 2u) % MEM_WORDS];

        m.ptr = (uint16_t)(m.ptr + 2u);

        return v;
    }
    case RV32_USB_PORT_MAILBOX: {
        uint16_t v = m.mbx_reply;

        m.mbx_full = false;

        return v;
    }
    case RV32_USB_PORT_ADDRESS:
        return m.ptr;
    default:
        return (m.mbx_full && m.mbx_delay_left == 0) ? 0x0001u : 0u;
    }
}

static void chip_write(unsigned port, uint16_t value)
{
    switch (port) {
    case RV32_USB_PORT_DATA:
        m.mem[(m.ptr / 2u) % MEM_WORDS] = m.corrupt_writes ? (uint16_t)(value ^ 1u) : value;
        m.ptr = (uint16_t)(m.ptr + 2u);
        break;
    case RV32_USB_PORT_MAILBOX:
        bios_command(value);
        break;
    case RV32_USB_PORT_ADDRESS:
        m.ptr = value;
        break;
    default:
        break;
    }
}

uint32_t rv32_usb_hook_read(uintptr_t address)
{
    unsigned word = (unsigned)((address - BASE) / 4u);

    if (word <= 3) {
        if (m.busy_left > 0) {
            m.error = true;
            m.discarded++;

            return 0;
        }

        m.accesses++;
        m.rdata = chip_read(word);
        m.busy_left = m.busy_per_access;

        return 0;
    }

    switch (word) {
    case 4:
        return m.busy_left > 0 ? 0xBAD0u : m.rdata;
    case 5:
        return m.ctrl;
    case 6: {
        uint32_t status = (m.busy_left > 0 ? RV32_USB_BRIDGE_BUSY : 0u) |
                          (m.error ? RV32_USB_BRIDGE_ERROR : 0u);

        if (m.busy_left > 0) {
            m.busy_left--;
        }

        if (m.mbx_delay_left > 0) {
            m.mbx_delay_left--;
        }

        return status;
    }
    case 7:
        return m.irq_mask;
    default:
        return m.timing;
    }
}

void rv32_usb_hook_write(uintptr_t address, uint32_t value)
{
    unsigned word = (unsigned)((address - BASE) / 4u);

    if (word <= 3) {
        if (m.busy_left > 0) {
            m.error = true;
            m.discarded++;

            return;
        }

        m.accesses++;
        chip_write(word, (uint16_t)value);
        m.busy_left = m.busy_per_access;

        if (m.force_error_next) {
            m.force_error_next = false;
            m.error = true;
        }

        return;
    }

    if (word == 5) {
        m.ctrl = value & 3u;
    } else if (word == 6) {
        if ((value & RV32_USB_BRIDGE_ERROR) != 0) {
            m.error = false;
        }
    } else if (word == 7) {
        m.irq_mask = value & 3u;
    } else if (word == 8) {
        m.timing = value & 0xffffffu;
    }
}

static unsigned reset_log[4];
static unsigned reset_calls;

static void fake_delay(void *context, uint32_t microseconds)
{
    (void)context;
    assert(reset_calls < 4);
    reset_log[reset_calls++] = (unsigned)(m.ctrl | (microseconds << 4));
}

static rv32_usb_t make(void)
{
    model_reset();

    rv32_usb_t usb = rv32_usb_new(BASE, 64);

    assert(rv32_usb_valid(usb));

    return usb;
}

static void test_handle(void)
{
    assert(!rv32_usb_valid(rv32_usb_new(0, 8)));
    assert(!rv32_usb_valid(rv32_usb_new(3, 8)));
    assert(!rv32_usb_valid(rv32_usb_new(BASE, 0)));
    assert(!rv32_usb_valid(rv32_usb_new(UINTPTR_MAX - 3, 8)));
    assert(!rv32_usb_valid(rv32_usb_platform_new(RV32_USB_DEFAULT_INSTANCE)));

    uint16_t v;

    assert(rv32_usb_port_read(rv32_usb_new(0, 8), RV32_USB_PORT_DATA, &v) ==
           RV32_USB_E_INVALID);
}

static void test_smoke(void)
{
    rv32_usb_t usb = make();
    uint16_t status = 0xffff;
    uint16_t word = 0;

    m.mem[0x10] = 0x1234;
    assert(rv32_usb_smoke(usb, 0x20, &status, &word) == RV32_USB_OK);
    assert(word == 0x1234);
    assert(status == 0);
    assert(m.discarded == 0);
    assert(rv32_usb_smoke(usb, 0x21, &status, &word) == RV32_USB_E_INVALID);
}

static void test_words_autoincrement(void)
{
    rv32_usb_t usb = make();
    const uint16_t src[5] = {0xA001, 0xA002, 0xA003, 0xA004, 0xA005};
    uint16_t dst[5] = {0};

    assert(rv32_usb_hpi_write_words(usb, 0x0200, src, 5) == RV32_USB_OK);

    for (unsigned i = 0; i < 5; i++) {
        assert(m.mem[0x100 + i] == src[i]);
    }

    assert(m.ptr == 0x0200 + 10);
    assert(rv32_usb_hpi_read_words(usb, 0x0200, dst, 5) == RV32_USB_OK);
    assert(memcmp(src, dst, sizeof(src)) == 0);
    assert(rv32_usb_hpi_read_words(usb, 0x0200, dst, 0) == RV32_USB_E_INVALID);
    assert(rv32_usb_hpi_read_words(usb, 0x0200, NULL, 1) == RV32_USB_E_INVALID);
    assert(m.discarded == 0);
}

static void test_bridge_errors(void)
{
    rv32_usb_t usb = make();
    uint16_t v = 0;

    /* BUSY dura mais que o orcamento: tempo esgotado, sem pedido descartado. */
    m.busy_per_access = 1000;
    assert(rv32_usb_port_write(usb, RV32_USB_PORT_ADDRESS, 0) == RV32_USB_E_BUSY_TIMEOUT);
    assert(rv32_usb_port_read(usb, RV32_USB_PORT_DATA, &v) == RV32_USB_E_BUSY_TIMEOUT);

    /* ERROR depois do acesso vira E_BRIDGE e e limpo. */
    usb = make();
    m.force_error_next = true;
    assert(rv32_usb_port_write(usb, RV32_USB_PORT_ADDRESS, 0) == RV32_USB_E_BRIDGE);
    assert(!m.error);
    assert(rv32_usb_port_write(usb, RV32_USB_PORT_ADDRESS, 0) == RV32_USB_OK);

    /* ERROR antigo e limpo na entrada e nao contamina o acesso seguinte. */
    m.error = true;
    assert(rv32_usb_port_read(usb, RV32_USB_PORT_STATUS, &v) == RV32_USB_OK);
}

static void test_registers(void)
{
    rv32_usb_t usb = make();

    assert(rv32_usb_set_timing(usb, 2, 6, 4));
    assert(m.timing == (2u | (6u << 8) | (4u << 16)));
    rv32_usb_irq_mask(usb, 0xff);
    assert(m.irq_mask == 3);
    assert(m.ctrl == 1);
    rv32_usb_chip_hold_reset(usb, false);
    assert(m.ctrl == 0);
    rv32_usb_chip_hold_reset(usb, true);
    assert(m.ctrl == 1);

    reset_calls = 0;
    assert(rv32_usb_chip_reset(usb, fake_delay, NULL, 10, 20) == RV32_USB_OK);
    assert(reset_calls == 2);
    assert(reset_log[0] == (1u | (10u << 4)));
    assert(reset_log[1] == (0u | (20u << 4)));
    assert(rv32_usb_chip_reset(usb, NULL, NULL, 1, 1) == RV32_USB_E_INVALID);
}

static void test_load_and_lcp(void)
{
    rv32_usb_t usb = make();
    const rv32_usb_profile_t p = rv32_usb_profile_unverified();
    const uint16_t code[3] = {0x1111, 0x2222, 0x3333};
    uint16_t v = 0;

    assert(memcmp(&p, &MODEL_PROFILE, sizeof(p)) == 0);
    assert(rv32_usb_load_code(usb, 0x0400, code, 3) == RV32_USB_OK);
    assert(m.mem[0x200] == 0x1111 && m.mem[0x202] == 0x3333);

    m.corrupt_writes = true;
    assert(rv32_usb_load_code(usb, 0x0400, code, 3) == RV32_USB_E_VERIFY);
    m.corrupt_writes = false;

    m.mbx_delay = 3;
    assert(rv32_usb_run_code(usb, &p, 0x0400, true) == RV32_USB_OK);
    assert(m.jump_target == 0x0400);
    assert(rv32_usb_call_code(usb, &p, 0x0500, true) == RV32_USB_OK);
    assert(m.call_target == 0x0500);
    assert(rv32_usb_write_ctrl_reg(usb, &p, 5, 0xBEEF) == RV32_USB_OK);
    assert(m.ctrl_regs[5] == 0xBEEF);
    assert(rv32_usb_read_ctrl_reg(usb, &p, 5, &v) == RV32_USB_OK);
    assert(v == 0xBEEF);

    /* Sem esperar o ACK, a resposta fica no mailbox. */
    m.mbx_full = false;
    assert(rv32_usb_run_code(usb, &p, 0x0600, false) == RV32_USB_OK);
    assert(m.mbx_full);
    assert(rv32_usb_hpi_mailbox_receive(usb, &p, &v) == RV32_USB_OK);
    assert(v == p.ack);

    m.bios_nak = true;
    assert(rv32_usb_run_code(usb, &p, 0x0400, true) == RV32_USB_E_NAK);
    m.bios_nak = false;
    m.bios_silent = true;
    assert(rv32_usb_run_code(usb, &p, 0x0400, true) == RV32_USB_E_MAILBOX_TIMEOUT);
    m.bios_silent = false;

    /* Perfil vazio: nada e inventado, tudo recusa. */
    const rv32_usb_profile_t empty = {0};

    assert(rv32_usb_run_code(usb, &empty, 0x0400, true) == RV32_USB_E_INVALID);
    assert(rv32_usb_hpi_mailbox_receive(usb, &empty, &v) == RV32_USB_E_INVALID);
    assert(rv32_usb_run_code(usb, NULL, 0x0400, true) == RV32_USB_E_INVALID);
    assert(m.discarded == 0);
}

int main(void)
{
    test_handle();
    test_smoke();
    test_words_autoincrement();
    test_bridge_errors();
    test_registers();
    test_load_and_lcp();
    puts("usb_hpi: PASS");

    return 0;
}
