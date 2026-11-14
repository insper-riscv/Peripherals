/* SPDX-License-Identifier: Apache-2.0
 * Driver C23 da ponte USB (usb_bridge) e da camada HPI do Cypress CY7C67200
 * (DE2-115, manual secao 4.17).
 *
 * Camadas:
 *   1. ponte: as nove palavras do periferico (confirmadas pelo RTL do PR #55);
 *   2. HPI: quatro portas do chip, memoria por ADDRESS+DATA, mailbox, status;
 *   3. LCP/BIOS: carga e execucao de codigo no chip, SEM valores embutidos.
 *
 * Nivel de confianca de cada afirmacao (ver docs/pt-br/USB/usb_driver.md):
 *   [C0] confirmado pelo manual da DE2-115 ou pelo RTL do periferico;
 *   [C1] protocolo HPI conhecido, sem fonte em Docs (datasheet ausente);
 *   [C2] valor de memoria, NAO CONFIRMADO: nunca e usado sem o chamador
 *        fornece-lo (rv32_usb_profile_t) ou chamar rv32_usb_profile_unverified().
 * Sem alocacao dinamica, sem esperas ocultas: toda espera e limitada por um
 * orcamento de leituras do STATUS, e atrasos em tempo vem de callback do chamador.
 */
#ifndef RV32_USB_H
#define RV32_USB_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* [C0] Portas do chip = endereco de palavra das quatro primeiras janelas. */
typedef enum {
    RV32_USB_PORT_DATA = 0,    /* HPI_DATA    (HC_DATA na ponte) */
    RV32_USB_PORT_MAILBOX = 1, /* HPI_MAILBOX (HC_CMD) */
    RV32_USB_PORT_ADDRESS = 2, /* HPI_ADDRESS (DC_DATA) */
    RV32_USB_PORT_STATUS = 3   /* HPI_STATUS  (DC_CMD) */
} rv32_usb_port_t;

/* [C0] Bits do registrador STATUS da ponte. */
#define RV32_USB_BRIDGE_INT0 (1u << 0)
#define RV32_USB_BRIDGE_INT1 (1u << 1)
#define RV32_USB_BRIDGE_DREQ (1u << 2)
#define RV32_USB_BRIDGE_BUSY (1u << 3)
#define RV32_USB_BRIDGE_ERROR (1u << 4)

typedef enum {
    RV32_USB_OK = 0,
    RV32_USB_E_INVALID,         /* handle, argumento ou perfil invalido */
    RV32_USB_E_BUSY_TIMEOUT,    /* BUSY nao caiu dentro do orcamento */
    RV32_USB_E_BRIDGE,          /* bit ERROR da ponte (acesso descartado) */
    RV32_USB_E_MAILBOX_TIMEOUT, /* nenhuma mensagem do chip no orcamento */
    RV32_USB_E_NAK,             /* o BIOS respondeu algo diferente de ACK */
    RV32_USB_E_VERIFY           /* leitura de volta difere do escrito */
} rv32_usb_err_t;

typedef struct {
    uintptr_t base;
    size_t poll_budget;
} rv32_usb_t;

/* Nao aloca nem escreve no hardware. base precisa ser nao nula, alinhada a 4 e
 * caber a janela; poll_budget precisa ser > 0. Invalido gera handle invalido.
 */
rv32_usb_t rv32_usb_new(uintptr_t base, size_t poll_budget);
bool rv32_usb_valid(rv32_usb_t usb);

/* ---- Camada 1: ponte [C0] ---------------------------------------------- */

/* Escreve 16 bits numa porta e espera a ponte ficar livre. */
rv32_usb_err_t rv32_usb_port_write(rv32_usb_t usb, rv32_usb_port_t port, uint16_t value);
/* Pede a leitura, espera BUSY cair e devolve RDATA. */
rv32_usb_err_t rv32_usb_port_read(rv32_usb_t usb, rv32_usb_port_t port,
                                  uint16_t *value);
uint32_t rv32_usb_bridge_status(rv32_usb_t usb);
void rv32_usb_bridge_clear_error(rv32_usb_t usb);
/* CTRL.CHIP_RESET: true mantem OTG_RST_N em nivel baixo. */
void rv32_usb_chip_hold_reset(rv32_usb_t usb, bool hold);
/* Preparacao, pulso e recuperacao em ciclos de clock (cada campo 0..255). */
bool rv32_usb_set_timing(rv32_usb_t usb, uint8_t setup, uint8_t pulse, uint8_t recovery);
/* Bit 0 habilita INT0, bit 1 habilita INT1 em o_irq. */
void rv32_usb_irq_mask(rv32_usb_t usb, uint8_t mask);

/* Atraso em microssegundos fornecido pelo chamador (o driver nao conhece o clock). */
typedef void (*rv32_usb_delay_fn)(void *context, uint32_t microseconds);

/* Pulso de reset: segura, espera hold_us, solta, espera boot_us. Os dois tempos
 * dependem do chip e NAO ESTAO CONFIRMADOS: sem valor padrao, o chamador os
 * escolhe a partir do datasheet.
 */
rv32_usb_err_t rv32_usb_chip_reset(rv32_usb_t usb, rv32_usb_delay_fn delay,
                                   void *context, uint32_t hold_us, uint32_t boot_us);

/* ---- Camada 2: HPI [C1] ------------------------------------------------- */

/* Palavras de 16 bits do chip, por endereco de BYTE do chip (par). Escreve em
 * ADDRESS e acessa DATA em sequencia: o ponteiro do chip avanca sozinho a cada
 * acesso a DATA [C1]. Nao ha ordem de bytes: o dado e a palavra de 16 bits.
 */
rv32_usb_err_t rv32_usb_hpi_set_address(rv32_usb_t usb, uint16_t address);
rv32_usb_err_t rv32_usb_hpi_read_words(rv32_usb_t usb, uint16_t address, uint16_t *dst,
                                       size_t count);
rv32_usb_err_t rv32_usb_hpi_write_words(rv32_usb_t usb, uint16_t address,
                                        const uint16_t *src, size_t count);
rv32_usb_err_t rv32_usb_hpi_status(rv32_usb_t usb, uint16_t *status);
rv32_usb_err_t rv32_usb_hpi_mailbox_send(rv32_usb_t usb, uint16_t message);

/* Perfil dos valores [C2]: tudo o que o driver precisa saber do chip e do BIOS e
 * que o datasheet nao confirmou aqui. Campo zero em codigo de comando significa
 * "comando nao configurado" (as funcoes devolvem RV32_USB_E_INVALID).
 */
typedef struct {
    uint16_t mailbox_in_flag; /* bit do HPI_STATUS: ha mensagem do chip para o host */
    uint16_t param_address;   /* endereco dos parametros do LCP no chip */
    uint16_t ack;             /* resposta de aceite do BIOS */
    uint16_t nak;             /* resposta de recusa do BIOS */
    uint16_t cmd_jump_to_code;
    uint16_t cmd_call_code;
    uint16_t cmd_exec_interrupt;
    uint16_t cmd_read_ctrl_reg;
    uint16_t cmd_write_ctrl_reg;
} rv32_usb_profile_t;

/* Valores lembrados de memoria, NAO CONFIRMADOS (ver rv32_usb_unverified.c). */
rv32_usb_profile_t rv32_usb_profile_unverified(void);

/* Espera mensagem do chip no mailbox e le. Precisa de profile->mailbox_in_flag. */
rv32_usb_err_t rv32_usb_hpi_mailbox_receive(rv32_usb_t usb,
                                            const rv32_usb_profile_t *profile,
                                            uint16_t *message);

/* ---- Camada 3: carga e execucao de codigo ------------------------------- */

/* Escreve a imagem na RAM do chip pela HPI e le de volta para conferir. */
rv32_usb_err_t rv32_usb_load_code(rv32_usb_t usb, uint16_t address,
                                  const uint16_t *words, size_t count);

/* Comando LCP generico: escreve params em param_address, envia o codigo no
 * mailbox, espera a resposta e compara com ack/nak; se results != NULL le
 * nresults palavras a partir de param_address depois do ACK (posicao NAO
 * CONFIRMADA). wait_ack false envia e retorna sem esperar.
 */
rv32_usb_err_t rv32_usb_lcp_run(rv32_usb_t usb, const rv32_usb_profile_t *profile,
                                uint16_t command, const uint16_t *params,
                                size_t nparams, uint16_t *results, size_t nresults,
                                bool wait_ack);
/* Comandos nomeados; a disposicao dos parametros e [C2]. */
rv32_usb_err_t rv32_usb_run_code(rv32_usb_t usb, const rv32_usb_profile_t *profile,
                                 uint16_t address, bool wait_ack);
rv32_usb_err_t rv32_usb_call_code(rv32_usb_t usb, const rv32_usb_profile_t *profile,
                                  uint16_t address, bool wait_ack);
rv32_usb_err_t rv32_usb_read_ctrl_reg(rv32_usb_t usb, const rv32_usb_profile_t *profile,
                                      uint16_t reg, uint16_t *value);
rv32_usb_err_t rv32_usb_write_ctrl_reg(rv32_usb_t usb,
                                       const rv32_usb_profile_t *profile, uint16_t reg,
                                       uint16_t value);

/* Teste de fumaca: le o STATUS da HPI e uma palavra do chip no endereco dado. */
rv32_usb_err_t rv32_usb_smoke(rv32_usb_t usb, uint16_t address, uint16_t *hpi_status,
                              uint16_t *word);

typedef enum {
    RV32_USB_DEFAULT_INSTANCE
} rv32_usb_instance_t;

/* Construtor gerado pela plataforma: sem enderecos na aplicacao. */
rv32_usb_t rv32_usb_platform_new(rv32_usb_instance_t instance);

#endif
