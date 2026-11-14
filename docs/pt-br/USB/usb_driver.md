# Driver C da ponte USB e da HPI do CY7C67200

Biblioteca C23 que opera o chip USB da DE2-115 pela ponte `usb_bridge`: acessos às quatro portas da HPI, leitura e escrita da memória do chip, mailbox, reset e carga de código. Ela não inclui pilha USB (enumeração, host de armazenamento ou de teclado), que depende do firmware do chip e do datasheet.

## 1. Onde fica e por quê

Os drivers C de [Peripherals #47](https://github.com/insper-riscv/Peripherals/pull/47) seguem `src/<periférico>/<camada>/driver/c/` com `driver.yaml`, `rv32_<nome>.h`, `rv32_<nome>.c`, `rv32_<nome>_platform.h` e `examples/main.c.in`. Este driver segue a mesma estrutura em `src/USB/soc/driver/c/`, de modo que o SDK o descobre pelo `driver.yaml` sem mudança. A pasta cabe no #47 porque o driver só conhece as nove palavras da ponte, não o topo da plataforma, e a base do periférico vem do `rv32_usb_platform.h` gerado.

| Arquivo | Conteúdo |
| :--- | :--- |
| `rv32_usb.h` | API pública, com a marca de confiança de cada grupo |
| `rv32_usb.c` | Ponte, HPI, carga de código e comandos do BIOS |
| `rv32_usb_unverified.c` | Valores de memória do BIOS, todos não confirmados, isolados num só arquivo |
| `rv32_usb_platform.h` | Base e orçamento de espera da plataforma (valores zero até o gerador preencher) |
| `tests/c/usb_hpi.c` | Teste no computador contra o modelo da ponte e do chip |

## 2. Níveis de confiança

O datasheet e o guia de programação do CY7C67200 não estão em `Docs`. O manual da DE2-115 (seção 4.17) só cita os dois documentos. Cada afirmação do driver tem um dos níveis abaixo, e o header marca o nível em cada grupo.

| Nível | Significado | Itens |
| :--- | :--- | :--- |
| C0 | Confirmado pelo manual da DE2-115 ou pelo RTL da ponte | Chip CY7C67200 em modo HPI; a HPI dá acesso à memória interna do chip e tem um mailbox bidirecional (manual 4.17); pinos `OTG_*` da tabela 4-25; as nove palavras da ponte, o `STATUS` e o protocolo de leitura em duas fases por `RDATA` (`usb_consts.vhd`, `usb_regs.vhd`) |
| C1 | Protocolo HPI conhecido, sem fonte local | Os quatro endereços do chip são dado, mailbox, endereço e estado (a nomenclatura vem do doc da ponte, e o manual não a traz); escrever em ADDRESS posiciona o ponteiro e cada acesso a DATA o avança; a memória é de palavras de 16 bits |
| C2 | Valor lembrado de memória, não confirmado | Bit do mailbox no status da HPI, endereço da área de parâmetros do LCP, códigos de aceite e recusa do BIOS, códigos dos comandos de saltar, chamar, ler e escrever registrador de controle, disposição dos parâmetros e dos resultados, tempos de reset e de boot |

Nada de C2 é usado sem o chamador pedir. Os campos de `rv32_usb_profile_t` valem zero por padrão, e um código de comando zero faz a função devolver `RV32_USB_E_INVALID`. Quem tiver o datasheet monta o próprio perfil. `rv32_usb_profile_unverified()` devolve os valores lembrados para uso de laboratório e fica em arquivo separado para poder ser removido.

## 3. API

### 3.1. Ponte

| Função | Efeito |
| :--- | :--- |
| `rv32_usb_new(base, poll_budget)` | Handle, sem escrita no hardware; base nula, desalinhada ou orçamento zero geram handle inválido |
| `rv32_usb_port_write(usb, porta, valor)` | Espera a ponte livre, escreve 16 bits na porta, espera concluir e confere `ERROR` |
| `rv32_usb_port_read(usb, porta, &valor)` | Pede a leitura, espera `BUSY` cair e devolve `RDATA`, como o doc da ponte manda |
| `rv32_usb_chip_hold_reset`, `rv32_usb_chip_reset` | `CTRL.CHIP_RESET`; o pulso recebe um callback de atraso e os dois tempos do chamador |
| `rv32_usb_set_timing`, `rv32_usb_irq_mask` | `TIMING` (preparação, pulso, recuperação) e `IRQ_MASK` |

Toda espera é limitada por `poll_budget` leituras do `STATUS`, sem tempo embutido. Um `ERROR` antigo é limpo na entrada de um acesso, e um `ERROR` surgido durante o acesso vira `RV32_USB_E_BRIDGE`.

### 3.2. HPI e carga de código

| Função | Efeito |
| :--- | :--- |
| `rv32_usb_hpi_read_words`, `rv32_usb_hpi_write_words` | Posicionam ADDRESS e acessam DATA em sequência, com endereço de byte par |
| `rv32_usb_hpi_status`, `rv32_usb_hpi_mailbox_send`, `rv32_usb_hpi_mailbox_receive` | Porta de estado e mailbox; o recebimento espera a flag do perfil |
| `rv32_usb_load_code` | Escreve a imagem em palavras de 16 bits e relê para conferir |
| `rv32_usb_lcp_run`, `rv32_usb_run_code`, `rv32_usb_call_code`, `rv32_usb_read_ctrl_reg`, `rv32_usb_write_ctrl_reg` | Comandos do BIOS pelo perfil: parâmetros na área do LCP, comando no mailbox, resposta comparada com aceite e recusa |
| `rv32_usb_smoke` | Lê o estado da HPI e uma palavra do chip |

A API usa palavras de 16 bits e não bytes, de modo que o driver não assume ordem de bytes da imagem.

## 4. Uso

```c
rv32_usb_t usb = rv32_usb_platform_new(RV32_USB_DEFAULT_INSTANCE);
uint16_t status, word;

rv32_usb_chip_hold_reset(usb, false);
/* espera de boot: tempo do datasheet, a cargo do chamador */
if (rv32_usb_smoke(usb, ENDERECO_DO_REGISTRADOR, &status, &word) != RV32_USB_OK) {
    /* falha da ponte ou do chip */
}
```

`ENDERECO_DO_REGISTRADOR` vem do datasheet. O driver não traz endereço de registrador do chip como valor confirmado.

## 5. Verificação

`make usb-driver-test` compila o driver com `-std=c23 -Wall -Wextra -Wpedantic -Werror -Wconversion -Wshadow` e as funções `rv32_usb_hook_*` do teste substituem o acesso MMIO por um modelo em C. O modelo tem duas partes. A ponte segue o RTL: leitura de porta só pede o acesso, `RDATA` vale ao fim do `BUSY`, pedido com `BUSY` é descartado e liga `ERROR`. O chip é uma suposição do autor (portas HPI, ponteiro com autoincremento, mailbox, BIOS com os valores C2). O teste cobre handle, fumaça, autoincremento, erros da ponte, registradores, reset, carga com e sem corrupção, comandos do BIOS, recusa, silêncio do BIOS e perfil vazio. Passar prova a coerência do driver com o modelo e com a ponte, não o comportamento do chip real.

## 6. O que o datasheet precisa confirmar

1. Bit do mailbox no status da HPI e a polaridade de cada flag.
2. Existência de leitura fantasma após posicionar ADDRESS e o ponteiro após o último acesso.
3. Códigos de comando, aceite e recusa do BIOS, a área de parâmetros e onde ficam os resultados.
4. Se o salto de código responde com aceite antes de executar.
5. Larguras do pulso de reset e do tempo de boot, e o modo de boot pela HPI.
6. Registrador de revisão do chip (candidato para o primeiro teste na placa).
7. O firmware de host e de dispositivo, e suas estruturas, para a enumeração de pendrive ou teclado (item T27).

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).
