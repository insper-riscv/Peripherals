/* SPDX-License-Identifier: Apache-2.0 */
#include "rv32_usb.h"
#include <rv32_usb_platform.h>

/* Offsets em palavras [C0] (usb_consts.vhd). */
enum {
    REG_RDATA = 4,
    REG_CTRL = 5,
    REG_STATUS = 6,
    REG_IRQ_MASK = 7,
    REG_TIMING = 8,
    WORD_COUNT = 9
};

#define CTRL_CHIP_RESET 1u

/* Em teste no host, o MMIO e substituido por um modelo (tests/c/usb_hpi.c). */
#ifdef RV32_USB_MMIO_HOOK
uint32_t rv32_usb_hook_read(uintptr_t address);
void rv32_usb_hook_write(uintptr_t address, uint32_t value);
#define MMIO_READ(address) rv32_usb_hook_read(address)
#define MMIO_WRITE(address, value) rv32_usb_hook_write((address), (value))
#else
#define MMIO_READ(address) (*(volatile uint32_t *)(address))
#define MMIO_WRITE(address, value) (*(volatile uint32_t *)(address) = (value))
#endif

static uintptr_t reg_address(rv32_usb_t usb, unsigned word)
{
    return usb.base + 4u * word;
}

rv32_usb_t rv32_usb_new(uintptr_t base, size_t poll_budget)
{
    rv32_usb_t usb = {0};

    if (base != 0 && base % 4 == 0 && base <= UINTPTR_MAX - 4u * WORD_COUNT &&
        poll_budget > 0) {
        usb.base = base;
        usb.poll_budget = poll_budget;
    }

    return usb;
}

bool rv32_usb_valid(rv32_usb_t usb)
{
    return usb.base != 0 && usb.poll_budget > 0;
}

uint32_t rv32_usb_bridge_status(rv32_usb_t usb)
{
    return rv32_usb_valid(usb) ? MMIO_READ(reg_address(usb, REG_STATUS)) : 0;
}

void rv32_usb_bridge_clear_error(rv32_usb_t usb)
{
    if (rv32_usb_valid(usb)) {
        MMIO_WRITE(reg_address(usb, REG_STATUS), RV32_USB_BRIDGE_ERROR);
    }
}

/* Espera BUSY cair. Na entrada de um acesso (clear_stale), um ERROR antigo (de
 * outro usuario da ponte) e limpo; depois do acesso ele e preservado para check_error.
 */
static rv32_usb_err_t wait_idle_for(rv32_usb_t usb, bool clear_stale)
{
    for (size_t i = 0; i < usb.poll_budget; i++) {
        uint32_t status = rv32_usb_bridge_status(usb);

        if ((status & RV32_USB_BRIDGE_BUSY) == 0) {
            if (clear_stale && (status & RV32_USB_BRIDGE_ERROR) != 0) {
                rv32_usb_bridge_clear_error(usb);
            }

            return RV32_USB_OK;
        }
    }

    return RV32_USB_E_BUSY_TIMEOUT;
}

static rv32_usb_err_t wait_idle(rv32_usb_t usb)
{
    return wait_idle_for(usb, true);
}

static rv32_usb_err_t wait_done(rv32_usb_t usb)
{
    return wait_idle_for(usb, false);
}

/* Depois de um acesso: ERROR ligado significa que o pedido foi descartado. */
static rv32_usb_err_t check_error(rv32_usb_t usb)
{
    if ((rv32_usb_bridge_status(usb) & RV32_USB_BRIDGE_ERROR) != 0) {
        rv32_usb_bridge_clear_error(usb);

        return RV32_USB_E_BRIDGE;
    }

    return RV32_USB_OK;
}

static bool port_valid(rv32_usb_port_t port)
{
    return port >= RV32_USB_PORT_DATA && port <= RV32_USB_PORT_STATUS;
}

rv32_usb_err_t rv32_usb_port_write(rv32_usb_t usb, rv32_usb_port_t port, uint16_t value)
{
    if (!rv32_usb_valid(usb) || !port_valid(port)) {
        return RV32_USB_E_INVALID;
    }

    rv32_usb_err_t err = wait_idle(usb);

    if (err != RV32_USB_OK) {
        return err;
    }

    MMIO_WRITE(reg_address(usb, (unsigned)port), value);
    err = wait_done(usb);

    return err != RV32_USB_OK ? err : check_error(usb);
}

rv32_usb_err_t rv32_usb_port_read(rv32_usb_t usb, rv32_usb_port_t port, uint16_t *value)
{
    if (!rv32_usb_valid(usb) || !port_valid(port) || value == NULL) {
        return RV32_USB_E_INVALID;
    }

    rv32_usb_err_t err = wait_idle(usb);

    if (err != RV32_USB_OK) {
        return err;
    }

    /* A leitura da porta so PEDE o acesso; o dado fica em RDATA [C0]. */
    (void)MMIO_READ(reg_address(usb, (unsigned)port));
    err = wait_done(usb);

    if (err != RV32_USB_OK) {
        return err;
    }

    err = check_error(usb);

    if (err == RV32_USB_OK) {
        *value = (uint16_t)(MMIO_READ(reg_address(usb, REG_RDATA)) & 0xffffu);
    }

    return err;
}

void rv32_usb_chip_hold_reset(rv32_usb_t usb, bool hold)
{
    if (rv32_usb_valid(usb)) {
        MMIO_WRITE(reg_address(usb, REG_CTRL), hold ? CTRL_CHIP_RESET : 0u);
    }
}

bool rv32_usb_set_timing(rv32_usb_t usb, uint8_t setup, uint8_t pulse, uint8_t recovery)
{
    if (!rv32_usb_valid(usb)) {
        return false;
    }

    MMIO_WRITE(reg_address(usb, REG_TIMING),
               (uint32_t)setup | ((uint32_t)pulse << 8) | ((uint32_t)recovery << 16));

    return true;
}

void rv32_usb_irq_mask(rv32_usb_t usb, uint8_t mask)
{
    if (rv32_usb_valid(usb)) {
        MMIO_WRITE(reg_address(usb, REG_IRQ_MASK), mask & 3u);
    }
}

rv32_usb_err_t rv32_usb_chip_reset(rv32_usb_t usb, rv32_usb_delay_fn delay,
                                   void *context, uint32_t hold_us, uint32_t boot_us)
{
    if (!rv32_usb_valid(usb) || delay == NULL) {
        return RV32_USB_E_INVALID;
    }

    rv32_usb_chip_hold_reset(usb, true);
    delay(context, hold_us);
    rv32_usb_chip_hold_reset(usb, false);
    delay(context, boot_us);

    return RV32_USB_OK;
}

rv32_usb_err_t rv32_usb_hpi_set_address(rv32_usb_t usb, uint16_t address)
{
    return rv32_usb_port_write(usb, RV32_USB_PORT_ADDRESS, address);
}

rv32_usb_err_t rv32_usb_hpi_read_words(rv32_usb_t usb, uint16_t address, uint16_t *dst,
                                       size_t count)
{
    if (dst == NULL || count == 0 || (address & 1u) != 0) {
        return RV32_USB_E_INVALID;
    }

    rv32_usb_err_t err = rv32_usb_hpi_set_address(usb, address);

    for (size_t i = 0; err == RV32_USB_OK && i < count; i++) {
        err = rv32_usb_port_read(usb, RV32_USB_PORT_DATA, &dst[i]);
    }

    return err;
}

rv32_usb_err_t rv32_usb_hpi_write_words(rv32_usb_t usb, uint16_t address,
                                        const uint16_t *src, size_t count)
{
    if (src == NULL || count == 0 || (address & 1u) != 0) {
        return RV32_USB_E_INVALID;
    }

    rv32_usb_err_t err = rv32_usb_hpi_set_address(usb, address);

    for (size_t i = 0; err == RV32_USB_OK && i < count; i++) {
        err = rv32_usb_port_write(usb, RV32_USB_PORT_DATA, src[i]);
    }

    return err;
}

rv32_usb_err_t rv32_usb_hpi_status(rv32_usb_t usb, uint16_t *status)
{
    return rv32_usb_port_read(usb, RV32_USB_PORT_STATUS, status);
}

rv32_usb_err_t rv32_usb_hpi_mailbox_send(rv32_usb_t usb, uint16_t message)
{
    return rv32_usb_port_write(usb, RV32_USB_PORT_MAILBOX, message);
}

rv32_usb_err_t rv32_usb_hpi_mailbox_receive(rv32_usb_t usb,
                                            const rv32_usb_profile_t *profile,
                                            uint16_t *message)
{
    if (!rv32_usb_valid(usb) || profile == NULL || profile->mailbox_in_flag == 0 ||
        message == NULL) {
        return RV32_USB_E_INVALID;
    }

    for (size_t i = 0; i < usb.poll_budget; i++) {
        uint16_t status = 0;
        rv32_usb_err_t err = rv32_usb_hpi_status(usb, &status);

        if (err != RV32_USB_OK) {
            return err;
        }

        if ((status & profile->mailbox_in_flag) != 0) {
            return rv32_usb_port_read(usb, RV32_USB_PORT_MAILBOX, message);
        }
    }

    return RV32_USB_E_MAILBOX_TIMEOUT;
}

rv32_usb_err_t rv32_usb_load_code(rv32_usb_t usb, uint16_t address,
                                  const uint16_t *words, size_t count)
{
    rv32_usb_err_t err = rv32_usb_hpi_write_words(usb, address, words, count);

    if (err != RV32_USB_OK) {
        return err;
    }

    /* Releitura palavra a palavra, com o ponteiro do chip em sequencia. */
    err = rv32_usb_hpi_set_address(usb, address);

    for (size_t i = 0; err == RV32_USB_OK && i < count; i++) {
        uint16_t word = 0;

        err = rv32_usb_port_read(usb, RV32_USB_PORT_DATA, &word);

        if (err == RV32_USB_OK && word != words[i]) {
            err = RV32_USB_E_VERIFY;
        }
    }

    return err;
}

rv32_usb_err_t rv32_usb_lcp_run(rv32_usb_t usb, const rv32_usb_profile_t *profile,
                                uint16_t command, const uint16_t *params,
                                size_t nparams, uint16_t *results, size_t nresults,
                                bool wait_ack)
{
    if (!rv32_usb_valid(usb) || profile == NULL || command == 0 ||
        profile->param_address == 0 || (nparams > 0 && params == NULL) ||
        (nresults > 0 && (results == NULL || !wait_ack))) {
        return RV32_USB_E_INVALID;
    }

    rv32_usb_err_t err = RV32_USB_OK;

    if (nparams > 0) {
        err = rv32_usb_hpi_write_words(usb, profile->param_address, params, nparams);
    }

    if (err == RV32_USB_OK) {
        err = rv32_usb_hpi_mailbox_send(usb, command);
    }

    if (err != RV32_USB_OK || !wait_ack) {
        return err;
    }

    uint16_t reply = 0;

    err = rv32_usb_hpi_mailbox_receive(usb, profile, &reply);

    if (err != RV32_USB_OK) {
        return err;
    }

    if (reply != profile->ack) {
        return RV32_USB_E_NAK;
    }

    return nresults > 0
               ? rv32_usb_hpi_read_words(usb, profile->param_address, results, nresults)
               : RV32_USB_OK;
}

rv32_usb_err_t rv32_usb_run_code(rv32_usb_t usb, const rv32_usb_profile_t *profile,
                                 uint16_t address, bool wait_ack)
{
    return profile == NULL ? RV32_USB_E_INVALID
                           : rv32_usb_lcp_run(usb, profile, profile->cmd_jump_to_code,
                                              &address, 1, NULL, 0, wait_ack);
}

rv32_usb_err_t rv32_usb_call_code(rv32_usb_t usb, const rv32_usb_profile_t *profile,
                                  uint16_t address, bool wait_ack)
{
    return profile == NULL ? RV32_USB_E_INVALID
                           : rv32_usb_lcp_run(usb, profile, profile->cmd_call_code,
                                              &address, 1, NULL, 0, wait_ack);
}

rv32_usb_err_t rv32_usb_read_ctrl_reg(rv32_usb_t usb, const rv32_usb_profile_t *profile,
                                      uint16_t reg, uint16_t *value)
{
    return profile == NULL ? RV32_USB_E_INVALID
                           : rv32_usb_lcp_run(usb, profile, profile->cmd_read_ctrl_reg,
                                              &reg, 1, value, 1, true);
}

rv32_usb_err_t rv32_usb_write_ctrl_reg(rv32_usb_t usb,
                                       const rv32_usb_profile_t *profile, uint16_t reg,
                                       uint16_t value)
{
    const uint16_t params[2] = {reg, value};

    return profile == NULL ? RV32_USB_E_INVALID
                           : rv32_usb_lcp_run(usb, profile, profile->cmd_write_ctrl_reg,
                                              params, 2, NULL, 0, true);
}

rv32_usb_err_t rv32_usb_smoke(rv32_usb_t usb, uint16_t address, uint16_t *hpi_status,
                              uint16_t *word)
{
    if (hpi_status == NULL || word == NULL) {
        return RV32_USB_E_INVALID;
    }

    rv32_usb_err_t err = rv32_usb_hpi_status(usb, hpi_status);

    return err != RV32_USB_OK ? err : rv32_usb_hpi_read_words(usb, address, word, 1);
}

rv32_usb_t rv32_usb_platform_new(rv32_usb_instance_t instance)
{
    switch (instance) {
    case RV32_USB_DEFAULT_INSTANCE:
        return rv32_usb_new(RV32_USB_DEFAULT_BASE, RV32_USB_DEFAULT_POLL_BUDGET);
    default:
        return rv32_usb_new(0, 0);
    }
}
