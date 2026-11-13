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
- [docs/pt-br/UART/serial_uart.md](docs/pt-br/UART/serial_uart.md): a UART serial 8N1, suas filas, registradores, erros e parâmetros de temporização.
- [docs/pt-br/UART/jtag_uart.md](docs/pt-br/UART/jtag_uart.md): a UART sobre JTAG (os registradores do core, o lado do hospedeiro e os limites), com o defeito que a moldou em [docs/pt-br/bugs/](docs/pt-br/bugs/JTAG_UART_RESPOSTA_PERDIDA.md).
- [docs/pt-br/PS2/ps2_host.md](docs/pt-br/PS2/ps2_host.md): a camada física PS/2 (`ps2_host`: canais 0 e 1 do cabo Y, filtro de glitch, quadro de 11 bits e envio de comandos).
- [docs/pt-br/PS2/ps2_keyboard.md](docs/pt-br/PS2/ps2_keyboard.md): o teclado PS/2 (`ps2_keyboard`: fila de scancodes do conjunto 2, registradores `DATA`, `STATUS`, `COMMAND` e `CONTROL`, comandos e interrupção).
- [docs/pt-br/PS2/ps2_mouse.md](docs/pt-br/PS2/ps2_mouse.md): o mouse PS/2 (inicialização, pacotes de 3 bytes, acumuladores saturados de deslocamento, botões, interrupção, canal 1 e cabo Y).
- [docs/pt-br/video/video.md](docs/pt-br/video/video.md): o periférico de vídeo VGA 640x480 a 60 Hz (framebuffer de duas portas com clocks independentes, ampliação do pixel, paleta opcional, contador de quadros e mapa de registradores).
- [docs/pt-br/LCD/lcd.md](docs/pt-br/LCD/lcd.md): o controlador do LCD 16x2 (HD44780) da DE2-115 (fila de escrita, temporização do barramento paralelo, espera pelo flag de ocupado ou por atraso, inicialização opcional em hardware e registradores).
- [docs/pt-br/flash-controller/flash_controller.md](docs/pt-br/flash-controller/flash_controller.md): o controlador de FLASH (registradores de comando, endereço, estado e buffer de página).
- [contracts/01-es-de-placa.md](docs/pt-br/contracts/01-es-de-placa.md) e [contracts/02-console.md](docs/pt-br/contracts/02-console.md): contratos K8 (vetores de E/S por papel, polaridade normalizada, largura zero) e K9 (console `jtag` ou `pinos`).
- [contracts/02-barramento-e-memoria.md](https://github.com/insper-riscv/Core/blob/main/docs/pt-br/contracts/02-barramento-e-memoria.md): protocolo de barramento adotado pelos periféricos.

## 2. Estrutura do Repositório

| Caminho | Conteúdo |
| :--- | :--- |
| `src/common/` | Submódulo Common-Components, editado só na origem |
| `src/GPIO/soc/` | Entrada e saída de uso geral: direção, saída (carga, set, clear, toggle), leitura sincronizada dos pinos e interrupções por borda de subida, de descida ou por nível em cada pino |
| `src/TIMER/soc/` | Temporizador e PWM: contador com `TOP`, prescaler, comparador de duty cycle, status de overflow e interrupção |
| `src/CLINT/soc/` | CLINT: `mtime` de 64 bits com vai-um registrado, `mtimecmp`, `msip` e as saídas de interrupção de timer e de software |
| `src/UART/serial/` | UART 8N1 mapeada em memória: filas parametrizáveis de RX e TX, registradores separados, níveis, flags de status e de erro e interrupção de RX opcional; a camada física é a `uart2bus` do OpenCores, trazida para o repositório |
| `src/UART/jtag/` | UART sobre JTAG: o núcleo escreve e lê bytes por registradores e um hospedeiro faz o mesmo pelo Virtual JTAG (`jtag_uart`); `cyclone-v/` guarda a casca do Virtual JTAG, só para a placa |
| `src/PLIC/soc/` | PLIC: gateways de nível, árbitro por prioridade com desempate por id, registradores no leiaute do `riscv-plic-1.0.0` e a saída `MEIP` (`plic`) |
| `src/PS2/host/` | Camada física PS/2 de um canal (`ps2_host`): sincronizador, filtro de glitch, recepção de quadros de 11 bits com paridade ímpar e envio de comandos com o clock inibido; uma instância por canal (teclado no canal 0, mouse no canal 1) |
| `src/PS2/keyboard/` | Teclado PS/2 mapeado em memória (`ps2_keyboard`): fila de bytes de scancode, status com overflow e erro, envio de comandos e interrupção de nível |
| `src/PS2/mouse/` | Mouse PS/2: decodificador de protocolo, acumuladores saturados por eixo e registradores (`ps2_mouse`), e o topo `ps2_mouse_top` que o liga ao `ps2_host` |
| `src/video/soc/` | Vídeo VGA: gerador de temporização 640x480 a 60 Hz, memória de duas portas do framebuffer, caminho de pixel com paleta opcional e registradores com estado de retrace e contador de quadros (`video`) |
| `src/LCD/soc/` | Controlador do LCD 16x2 (HD44780): registradores e fila de escrita (`lcd_regs`), camada física do barramento paralelo (`lcd_phy`), inicialização opcional (`lcd_init`) e o topo `lcd` |
| `src/flash-controller/soc/` | Controlador de FLASH: registradores de comando, endereço, estado e buffer de página que levam os comandos de apagar, gravar e proteger ao chip de FLASH do repositório Memory |
| `src/display/` | Display de sete segmentos: o registrador do valor, o conversor de hexadecimal para segmentos (`soc/`) e a casca do Virtual JTAG da placa (`cyclone-v/`) |
| `tests/python/` | Testes por entidade em cocotb e o catálogo (`tests.json`) que os conduz, em `unittests/{CLINT,GPIO,LCD,PLIC,PS2,TIMER,UART,display,flash_controller,video}` |
| `tests/vhdl/` | `gpio_tb`, wrapper que permite ao cocotb dirigir os pinos `inout` da GPIO, `ps2_host_tb`, com dois canais `ps2_host`, `ps2_keyboard_tb`, com o teclado e as linhas acessíveis ao cocotb, e `ps2_cable_tb`, com o teclado e o mouse ativos ao mesmo tempo |
| `formal/` | Propriedades em SystemVerilog de `gpio_cell`, `timer`, `clock_prescaler`, `counter_overflow`, `alu_ge_unsigned`, `clint`, `plic`, `plic_gateway`, `plic_arbiter`, `flash_controller`, `uart_fifo` e `uart`, o `run.sh` e o agregador dos engines |
| `docs/pt-br/`, `docs/en/` | Documentos do CLINT (`CLINT/`), do PLIC (`PLIC/`), do PS/2 (`PS2/`), da UART (`UART/`), do controlador de FLASH (`flash-controller/`), do vídeo (`video/`), das provas formais (`formal/`) e do defeito da UART sobre JTAG (`bugs/`) |

## 3. Interface

Todo periférico compartilha o mesmo conjunto de portas, conforme o barramento do contrato do Core: `i_clk`, `i_rst`, `i_data_in`, `i_address` (deslocamento em palavras dentro do periférico), `i_write`, `i_read`, `o_data_out` e `o_irq`; o CLINT não tem `i_read`, porque a leitura não tem efeito colateral. Os mapas de registradores estão nas entidades `*_operation_decoder` e em `tests/python/unittests/*/*_operation_decoder.py`.

### 3.1. Registradores da GPIO

| Endereço | Registrador |
| :--- | :--- |
| 0 | Direção (1 = saída) |
| 1, 2, 3, 4 | Saída: carga, set, clear e toggle (a leitura devolve o registrador de saída) |
| 5, 6, 7 | Máscara de interrupção, máscara de borda de subida e máscara de borda de descida |
| 8 | Status de interrupção (a leitura devolve o valor e o limpa) |
| 9 | Pinos, após um sincronizador de dois estágios |

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

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](LICENSE).
