# Peripherals

🌐 [Português](README.md) · [English](README.en.md)

Periféricos mapeados em memória do SoC RISC-V RV32: os blocos com que o núcleo conversa pelo barramento, fora do núcleo e das memórias. O núcleo, as memórias, os topos que os conectam e os programas de teste ficam em outros repositórios da organização [insper-riscv](https://github.com/insper-riscv).

## 1. Documentação

- [AUTHORS.md](AUTHORS.md): autores com commits no repositório, com nome e conta do GitHub.
- [CONTRIBUTING.md](CONTRIBUTING.md): regras obrigatórias de contribuição, norma VHDL-2008, nomenclatura, cabeçalhos, normas Python e verificação antes de abrir Pull Request.
- [CITATION.cff](CITATION.cff): metadados para citação do software.
- [docs/bugs/](docs/bugs/README.md): bugs encontrados na primeira simulação dos periféricos, com as correções.
- [docs/pt-br/formal/formal.md](docs/pt-br/formal/formal.md): provas formais dos periféricos, engines de solver e a regra do agregador que decide o check `formal` do CI.
- [docs/pt-br/PLIC/plic.md](docs/pt-br/PLIC/plic.md): o PLIC (`riscv-plic-1.0.0` de um hart e um contexto: prioridades, limiar, habilitação, claim e complete, gateway de nível e a saída `MEIP`).
- [docs/pt-br/CLINT/clint.md](docs/pt-br/CLINT/clint.md): o CLINT (`mtime`, `mtimecmp` e `msip` de 64 bits no leiaute da SiFive, as saídas `MTIP` e `MSIP` e a escrita segura do `mtimecmp`).
- [docs/pt-br/UART/serial_uart.md](docs/pt-br/UART/serial_uart.md): a UART serial, suas filas, registradores, formato do quadro (paridade e bits de parada), controle de fluxo por hardware, erros, parâmetros de temporização e a ligação aos cabeçalhos de expansão.
- [docs/pt-br/UART/jtag_uart.md](docs/pt-br/UART/jtag_uart.md): a UART sobre JTAG (os registradores do core, o lado do hospedeiro e os limites), com o defeito que a moldou em [docs/pt-br/bugs/](docs/pt-br/bugs/JTAG_UART_RESPOSTA_PERDIDA.md).
- [docs/pt-br/PS2/ps2_host.md](docs/pt-br/PS2/ps2_host.md): a camada física PS/2 (`ps2_host`: canais 0 e 1 do cabo Y, filtro de glitch, quadro de 11 bits e envio de comandos).
- [docs/pt-br/PS2/ps2_keyboard.md](docs/pt-br/PS2/ps2_keyboard.md): o teclado PS/2 (`ps2_keyboard`: fila de scancodes do conjunto 2, registradores `DATA`, `STATUS`, `COMMAND` e `CONTROL`, comandos e interrupção).
- [docs/pt-br/PS2/ps2_mouse.md](docs/pt-br/PS2/ps2_mouse.md): o mouse PS/2 (inicialização, pacotes de 3 bytes, acumuladores saturados de deslocamento, botões, interrupção, canal 1 e cabo Y).
- [docs/pt-br/video/video.md](docs/pt-br/video/video.md): o periférico de vídeo VGA genérico (modo, polaridade e largura do canal por generics, padrão 640x480 a 60 Hz com 4 bits por canal; framebuffer de duas portas com clocks independentes, ampliação do pixel, formato indexado com paleta ou direto, contador de quadros e mapa de registradores).
- [docs/pt-br/ADC/max10_adc.md](docs/pt-br/ADC/max10_adc.md): o ADC interno do MAX 10 (varredura de canais por máscara sobre a interface Avalon-ST do núcleo `altera_modular_adc`, registrador e flags por canal, período, interrupção, geração do IP no Quartus, canais A0 a A5 da DE10-Lite e exemplo em C).
- [docs/pt-br/SD/sd_spi.md](docs/pt-br/SD/sd_spi.md): o controlador de cartão SD no modo SPI (mestre SPI com divisor configurável, filas de transmissão e recepção, seleção de chip, interrupções, pinos das placas, sequência de inicialização e exemplo em C de leitura de setor).
- [docs/pt-br/IR/ir_receiver.md](docs/pt-br/IR/ir_receiver.md): o receptor de infravermelho da DE2-115 (decodificador NEC com repetição e endereço estendido, FIFO de quadros, medida bruta de pulso e espaço, erros e interrupção).
- [docs/pt-br/LCD/lcd.md](docs/pt-br/LCD/lcd.md): o controlador do LCD 16x2 (HD44780) da DE2-115 (fila de escrita, temporização do barramento paralelo, espera pelo flag de ocupado ou por atraso, inicialização opcional em hardware e registradores).
- [docs/pt-br/I2C/i2c_master.md](docs/pt-br/I2C/i2c_master.md): o mestre I2C de uso geral (início, repetição de início e parada, bytes com ACK e NACK, esticamento de clock, arbitragem, divisor de 100 kHz e 400 kHz, interrupção, mapa de registradores e exemplo em C para EEPROM de 2 a 64 Kbit).
- [docs/pt-br/audio/audio.md](docs/pt-br/audio/audio.md): a interface de áudio I2S para o codec WM8731 (`audio`: clock mestre fracionário, clocks de bit e de canal, serializador e desserializador de 16, 24 e 32 bits, filas, tom de teste em hardware e interrupção).
- [docs/pt-br/ETH/eth.md](docs/pt-br/ETH/eth.md): o MAC Ethernet de 10/100 Mbit/s em MII com mestre MDIO (envio com preâmbulo, preenchimento e FCS, recepção com filtro e FIFO assíncrona de Gray, buffers de quadro, contadores, interrupções e pinos das portas da DE2-115).
- [docs/pt-br/HDMI/hdmi_tx.md](docs/pt-br/HDMI/hdmi_tx.md): a saída de vídeo HDMI para o transmissor ADV7513 (`hdmi_tx`: invólucro sobre os blocos do vídeo genérico, framebuffer indexado de 8 bits com paleta de 24 bits ou RGB565, modos CEA-861 por generics, escritor I2C e sequenciador de inicialização do chip, registradores, interrupções e as resoluções que cabem nos blocos M10K da DE10-Nano).
- [docs/pt-br/HDMI/hdmi_audio.md](docs/pt-br/HDMI/hdmi_audio.md): a saída de áudio HDMI pelo I2S do ADV7513 (`hdmi_audio`: invólucro mestre e só de reprodução sobre o periférico de áudio, MCLK de 128 ou 256 vezes a taxa, taxas de 32, 44,1 e 48 kHz, palavra de 16 ou 24 bits, tabela de áudio do sequenciador do `hdmi_tx`).
- [docs/pt-br/TV/tv.md](docs/pt-br/TV/tv.md): a captura de vídeo do decodificador de TV ADV7180 da DE2-115 (receptor BT.656, conversão para RGB565 ou luminância, decimação, memória de quadro de dois clocks, registradores e interrupção de fim de quadro).
- [docs/pt-br/ETH/eth_rgmii.md](docs/pt-br/ETH/eth_rgmii.md): o mesmo MAC a 10, 100 e 1000 Mbit/s em RGMII (camada RGMII, registradores DDR, registrador `SPEED`, atraso do clock, resultado de síntese e plano de restrições).
- [docs/pt-br/SD/sd_native.md](docs/pt-br/SD/sd_native.md): o controlador de cartão SD no modo nativo (comando com CRC7, respostas curta e longa conferidas, blocos de 512 bytes em uma ou quatro linhas com CRC16 por linha, buffer de bloco, detecção de ocupado em DAT0, divisor de SD_CLK, interrupções, pinos das placas, sequência de inicialização e exemplo em C).
- [docs/pt-br/flash-controller/flash_controller.md](docs/pt-br/flash-controller/flash_controller.md): o controlador de FLASH (registradores de comando, endereço, estado e buffer de página).
- [docs/pt-br/USB/usb_bridge.md](docs/pt-br/USB/usb_bridge.md): a ponte paralela de 16 bits para o chip USB da placa (quatro portas de acesso, temporização por registrador, interrupções, reset do chip e leitura do identificador).
- [docs/pt-br/USB/usb_driver.md](docs/pt-br/USB/usb_driver.md): o driver C da ponte USB e da HPI do CY7C67200 (portas, memória do chip, mailbox, carga de código, níveis de confiança e o que falta do datasheet).
- [contracts/01-es-de-placa.md](docs/pt-br/contracts/01-es-de-placa.md) e [contracts/02-console.md](docs/pt-br/contracts/02-console.md): contratos K8 (vetores de E/S por papel, polaridade normalizada, largura zero) e K9 (console `jtag` ou `pinos`).
- [contracts/02-barramento-e-memoria.md](https://github.com/insper-riscv/Core/blob/main/docs/pt-br/contracts/02-barramento-e-memoria.md): protocolo de barramento adotado pelos periféricos.

## 2. Estrutura do Repositório

| Caminho | Conteúdo |
| :--- | :--- |
| `src/common/` | Submódulo Common-Components, editado só na origem |
| `src/GPIO/soc/` | Entrada e saída de uso geral: blocos de grupos adaptativos (partição, direção fixa e polaridade por pino vindas de generics) com direção, saída (carga, set, clear, toggle), leitura sincronizada dos pinos e interrupções por borda de subida, de descida ou por nível em cada pino |
| `src/TIMER/soc/` | Temporizador e PWM: contador com `TOP`, prescaler, comparador de duty cycle, status de overflow e interrupção |
| `src/CLINT/soc/` | CLINT: `mtime` de 64 bits com vai-um registrado, `mtimecmp`, `msip` e as saídas de interrupção de timer e de software |
| `src/UART/serial/` | UART mapeada em memória (8N1 por padrão, com paridade e segundo bit de parada opcionais): filas parametrizáveis de RX e TX, registradores separados, níveis, flags de status e de erro, controle de fluxo RTS e CTS opcional e interrupção de RX opcional; a camada física é a `uart2bus` do OpenCores, trazida para o repositório |
| `src/UART/jtag/` | UART sobre JTAG: o núcleo escreve e lê bytes por registradores e um hospedeiro faz o mesmo pelo Virtual JTAG (`jtag_uart`); `cyclone-v/` guarda a casca do Virtual JTAG, só para a placa |
| `src/PLIC/soc/` | PLIC: gateways de nível, árbitro por prioridade com desempate por id, registradores no leiaute do `riscv-plic-1.0.0` e a saída `MEIP` (`plic`) |
| `src/PS2/host/` | Camada física PS/2 de um canal (`ps2_host`): sincronizador, filtro de glitch, recepção de quadros de 11 bits com paridade ímpar e envio de comandos com o clock inibido; uma instância por canal (teclado no canal 0, mouse no canal 1) |
| `src/PS2/keyboard/` | Teclado PS/2 mapeado em memória (`ps2_keyboard`): fila de bytes de scancode, status com overflow e erro, envio de comandos e interrupção de nível |
| `src/PS2/mouse/` | Mouse PS/2: decodificador de protocolo, acumuladores saturados por eixo e registradores (`ps2_mouse`), e o topo `ps2_mouse_top` que o liga ao `ps2_host` |
| `src/video/soc/` | Vídeo VGA genérico: gerador de temporização por generics, memória de duas portas do framebuffer, caminho de pixel indexado ou direto, backend VGA com largura de canal por generic e registradores com estado de retrace e contador de quadros (`video`) |
| `src/ADC/soc/` | ADC interno do MAX 10: sequenciador de varredura com a interface Avalon-ST de comando e resposta do núcleo (`max10_adc_sequencer`) e registradores por canal com período e interrupção (`max10_adc`) |
| `src/ADC/max10/` | Só para a placa: instância do IP `altera_modular_adc` gerado, PLL de 10 MHz e o topo `max10_adc_shell`; `ip/` traz o script que gera o IP no Quartus |
| `src/SD/spi/` | Cartão SD no modo SPI: mestre SPI de um byte (`sd_spi_phy`) e o topo mapeado em memória com filas, seleção de chip e interrupção (`sd_spi`) |
| `src/I2C/soc/` | Mestre I2C: máquina de linha com início, parada, byte, ACK, esticamento de clock e arbitragem (`i2c_core`) e registradores com interrupção (`i2c_master`), com os pinos como par saída-baixa e entrada |
| `src/audio/soc/` | Áudio I2S: gerador fracionário do clock mestre, clocks de bit e de canal do modo mestre, serializador, desserializador, tom de teste e registradores com filas (`audio`) |
| `src/ETH/` | MAC Ethernet em MII (`eth`: registradores, transmissor, receptor, FIFO assíncrona, armazenamento de quadros, memória de duas portas, CRC-32 e travessias de clock) e o mestre MDIO em `mdio/` |
| `src/HDMI/soc/`, `src/HDMI/adv7513/` | Saída HDMI para o ADV7513: caminho de pixel de 24 bits, registrador de saída, registradores do HDMI e topo `hdmi_tx` (reaproveitam a temporização, a memória e os registradores do vídeo), escritor I2C de escrita e sequenciador de inicialização por tabela |
| `src/TV/soc/` | Captura de TV: receptor BT.656 de 8 bits, controle da captura de um quadro com decimação, conversão YCbCr para RGB565 ou luminância e registradores com interrupção de fim de quadro (`tv`) |
| `src/SD/native/` | Cartão SD no modo nativo: gerador de SD_CLK (`sd_clock_gen`), controle de comando (`sd_cmd`), controle de dados (`sd_data`), CRC7 e CRC16 seriais (`sd_crc7`, `sd_crc16`), buffer de bloco (`sd_block_buffer`) e o topo mapeado em memória (`sd_native`) |
| `src/flash-controller/soc/` | Controlador de FLASH: registradores de comando, endereço, estado e buffer de página que levam os comandos de apagar, gravar e proteger ao chip de FLASH do repositório Memory |
| `src/USB/soc/` | Ponte USB: mestre do barramento paralelo do chip (preparação, pulso, retenção e recuperação configuráveis), registradores e topo `usb_bridge` com sincronizadores; `driver/c/` traz o driver C23 da ponte e da HPI |
| `src/display/` | Display de sete segmentos: o registrador do valor, o conversor de hexadecimal para segmentos (`soc/`) e a casca do Virtual JTAG da placa (`cyclone-v/`) |
| `tests/python/` | Testes por entidade em cocotb e o catálogo (`tests.json`) que os conduz, em `unittests/{ADC,CLINT,ETH,GPIO,HDMI,I2C,IR,LCD,PLIC,PS2,SD,TIMER,TV,UART,USB,audio,display,flash_controller,video}` |
| `src/LCD/soc/` | Controlador do LCD 16x2 (HD44780): registradores e fila de escrita (`lcd_regs`), camada física do barramento paralelo (`lcd_phy`), inicialização opcional (`lcd_init`) e o topo `lcd` |
| `tests/vhdl/` | `max10_adc_tb` e o modelo comportamental do núcleo do ADC (`max10_adc_core_model`), `gpio_tb`, wrapper que permite ao cocotb dirigir os pinos `inout` da GPIO, `ps2_host_tb`, com dois canais `ps2_host`, `ps2_keyboard_tb`, com o teclado e as linhas acessíveis ao cocotb, e `ps2_cable_tb`, com o teclado e o mouse ativos ao mesmo tempo |
| `formal/` | Propriedades em SystemVerilog de `max10_adc_sequencer`, `gpio_cell`, `gpio`, `seg_display`, `timer`, `clock_prescaler`, `counter_overflow`, `alu_ge_unsigned`, `clint`, `plic`, `plic_gateway`, `plic_arbiter`, `flash_controller`, `uart_fifo`, `uart`, `sd_spi`, `sd_crc7`, `sd_crc16`, `sd_cmd`, `ir_fifo`, `ir_regs`, `lcd_phy`, `lcd_regs`, `usb_bridge`, `i2c_core`, `i2c_master`, `audio_xck_gen`, `audio_frame_clocks`, `audio`, `eth_crc32`, `eth_async_fifo`, `eth_regs`, `hdmi_timing`, `hdmi_regs`, `hdmi_init_seq` e `hdmi_i2c_writer`, `tv_regs` e `tv_capture`, o `run.sh` e o agregador dos engines |
| `docs/pt-br/`, `docs/en/` | Documento do ADC (`ADC/`), documentos do CLINT (`CLINT/`), do PLIC (`PLIC/`), do PS/2 (`PS2/`), da UART (`UART/`), do controlador de FLASH (`flash-controller/`), do vídeo (`video/`), do cartão SD (`SD/`), do receptor de infravermelho (`IR/`), do LCD (`LCD/`), da ponte USB (`USB/`), do mestre I2C (`I2C/`), do áudio (`audio/`), da Ethernet (`ETH/`), do HDMI (`HDMI/`, vídeo e áudio), da captura de TV (`TV/`), das provas formais (`formal/`) e do defeito da UART sobre JTAG (`bugs/`) |
| `tests/quartus/` | Script que gera o IP do ADC e sintetiza o `max10_adc_shell` no Quartus Prime Lite |
| `src/IR/soc/` | Receptor de infravermelho: filtro e medidor de pulsos, decodificador NEC, FIFO de quadros e registradores (`ir_receiver`) |

## 3. Interface

Todo periférico compartilha o mesmo conjunto de portas, conforme o barramento do contrato do Core: `i_clk`, `i_rst`, `i_data_in`, `i_address` (deslocamento em palavras dentro do periférico), `i_write`, `i_read`, `o_data_out` e `o_irq`; o CLINT não tem `i_read`, porque a leitura não tem efeito colateral. Os mapas de registradores estão nas entidades `*_operation_decoder` e em `tests/python/unittests/*/*_operation_decoder.py`.

### 3.1. Registradores da GPIO

Cada grupo do bloco tem o seu arquivo de 16 palavras (64 bytes), e o grupo $g$ começa na palavra $16g$; o detalhe está em `docs/pt-br/GPIO/gpio.md`. Os endereços abaixo são os de um grupo.

| Endereço | Registrador |
| :--- | :--- |
| 0 | Direção (1 = saída) |
| 1, 2, 3, 4 | Saída: carga, set, clear e toggle (a leitura devolve o registrador de saída) |
| 5, 6, 7 | Máscara de interrupção, máscara de borda de subida e máscara de borda de descida |
| 8 | Status de interrupção (a leitura devolve o valor e o limpa) |
| 9 | Pinos, após um sincronizador de dois estágios |
| 10 | Modo de nível da interrupção por pino |

### 3.2. Registradores do TIMER

| Endereço | Registrador |
| :--- | :--- |
| 0 | Configuração: bit 0 inicia, bit 1 satura em `TOP` (senão dá a volta), bit 2 habilita PWM, bit 3 habilita interrupção |
| 1 | Contador (a escrita o carrega) |
| 2 | Reset do contador (a escrita o zera) |
| 3, 4 | `TOP` (reinicia com todos os bits em 1) e duty cycle |
| 5 | Status de overflow (a leitura devolve o valor e o limpa) |
| 6 | Saída PWM |
| 7 | Prescaler (o contador avança a cada `prescaler + 1` ciclos) |

### 3.3. Registradores do CLINT

O endereço tem 14 bits de palavra. O leiaute é o do CLINT da SiFive, com os detalhes em [docs/pt-br/CLINT/clint.md](docs/pt-br/CLINT/clint.md).

| Deslocamento | Registrador |
| :--- | :--- |
| `0x0000` | `msip` (bit 0) |
| `0x4000`, `0x4004` | `mtimecmp` baixa e alta (reset com todos os bits em 1) |
| `0xBFF8`, `0xBFFC` | `mtime` baixa e alta |

### 3.4. Registradores da UART

A UART não exige espera do barramento: o software consulta `TX_READY` e `RX_VALID`, e todo acesso mapeado em memória termina em um ciclo. A configuração inicial é 115200 baud, 8N1 com clock de 50 MHz e filas de 16 bytes em cada sentido. As profundidades são parâmetros independentes.

| Endereço | Registrador |
| :--- | :--- |
| 0 | `TX_DATA` (só escrita): enfileira o byte baixo; a leitura devolve zero |
| 1 | `RX_DATA` (só leitura): devolve e remove o byte recebido mais antigo; a escrita não tem efeito |
| 2 | `STATUS`: bits 0 `RX_VALID`, 1 `TX_READY`, 2 `RX_OVERRUN`, 3 `TX_DROPPED`, 4 `RX_FULL`, 5 `TX_EMPTY`, 6 `TX_IDLE`, 15:8 `RX_LEVEL` e 23:16 `TX_LEVEL`; escrever 1 nos bits 2 e 3 os limpa |
| 3 | `CONTROL`: o bit 0 habilita o pedido de interrupção do RX |

## 4. Verificação e Execução

### 4.1. Execução local

```bash
git clone --recurse-submodules https://github.com/insper-riscv/Peripherals.git
cd Peripherals
uv sync

make check   # Verificação de sintaxe VHDL de todos os fontes em ordem de dependência (GHDL)
make test    # Testes por entidade em cocotb (make test TEST=GPIO para um alvo)
make paths   # Caminhos do paths.yaml e árvore do repositório (riscv-tools check-tree)
make formal  # Provas formais (SymbiYosys) com o engine de FORMAL_ENGINE (bitwuzla por padrão)
```

### 4.2. Execução via Docker

A imagem `ghcr.io/insper-riscv/ci-vhdl:latest` publicada pelo repositório [insper-riscv/Infra](https://github.com/insper-riscv/Infra) já traz o GHDL (backend LLVM), Yosys, SymbiYosys, os solvers Yices, Bitwuzla e Boolector, `uv`, Python 3.14 e cocotb pré-instalados:

```bash
docker run --rm -v "$PWD:/workspace" -w /workspace ghcr.io/insper-riscv/ci-vhdl:latest \
  bash -c "uv sync && make check && make test && make paths && make formal"
```

GPIO, TIMER, CLINT, PLIC, UART (serial/JTAG), display e controlador de FLASH incluem drivers C23 e descritores para integração automática pelo SDK. Todos os handles são criados por funções `*_new()`, sem alocação dinâmica. As APIs recebem números de pino, dígito ou fonte; endereços e máscaras ficam na implementação. Veja [o uso e os padrões dos drivers](docs/pt-br/GPIO/gpio.md).

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](LICENSE).

Cada descritor C também fornece um template de exemplo. O SDK 0.8 gera um projeto C independente em `vendor/<DRIVER>/example`, herdando plataforma e profile. Os exemplos usam construtores, índices numéricos e esperas limitadas. O exemplo de FLASH apenas lê status. Copie o projeto antes de editar arquivos gerenciados.
