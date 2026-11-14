/* SPDX-License-Identifier: Apache-2.0
 * VALORES NAO CONFIRMADOS do CY7C67200.
 *
 * O datasheet e o guia de programacao do chip NAO estao em Docs (o manual da
 * DE2-115 so os cita na secao 4.17). Os numeros abaixo vem da memoria de quem
 * escreveu o driver sobre o BIOS do EZ-OTG (comandos LCP e flag do mailbox).
 * Cada um DEVE ser conferido no datasheet antes de ser tratado como correto;
 * qualquer codigo do chip que dependa deles esta marcado [C2] no header.
 * Quem tiver o datasheet pode montar o proprio rv32_usb_profile_t e ignorar
 * este arquivo (basta nao chamar rv32_usb_profile_unverified).
 */
#include "rv32_usb.h"

rv32_usb_profile_t rv32_usb_profile_unverified(void)
{
    rv32_usb_profile_t profile = {
        /* NAO CONFIRMADO: bit do HPI_STATUS "mailbox com mensagem para o host". */
        .mailbox_in_flag = 0x0001,
        /* NAO CONFIRMADO: area de parametros do LCP no chip. */
        .param_address = 0x0144,
        /* NAO CONFIRMADO: respostas do BIOS. */
        .ack = 0x0FED,
        .nak = 0xDEAD,
        /* NAO CONFIRMADO: codigos de comando do BIOS. */
        .cmd_jump_to_code = 0xCE00,
        .cmd_exec_interrupt = 0xCE01,
        .cmd_read_ctrl_reg = 0xCE02,
        .cmd_write_ctrl_reg = 0xCE03,
        .cmd_call_code = 0xCE04,
    };

    return profile;
}
