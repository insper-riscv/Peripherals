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
- [docs/pt-br/intc/ext_irq_controller.md](docs/pt-br/intc/ext_irq_controller.md): o controlador de interrupção externa (as linhas dos periféricos reunidas em um `MEIP`, com registradores de pendência, habilitação e fonte).
- [docs/pt-br/flash-controller/flash_controller.md](docs/pt-br/flash-controller/flash_controller.md): o controlador de FLASH (registradores de comando, endereço, estado e buffer de página).
- [contracts/02-barramento-e-memoria.md](https://github.com/insper-riscv/Core/blob/main/docs/pt-br/contracts/02-barramento-e-memoria.md): protocolo de barramento adotado pelos periféricos.

## 2. Estrutura do Repositório

| Caminho | Conteúdo |
| :--- | :--- |
| `src/common/` | Submódulo Common-Components, editado só na origem |
| `src/GPIO/soc/` | Entrada e saída de uso geral: direção, saída (carga, set, clear, toggle), leitura sincronizada dos pinos e interrupções por borda de subida e descida em cada pino |
| `src/TIMER/soc/` | Temporizador e PWM: contador com `TOP`, prescaler, comparador de duty cycle, status de overflow e interrupção |
| `src/CLINT/soc/` | CLINT: `mtime` de 64 bits com vai-um registrado, `mtimecmp`, `msip` e as saídas de interrupção de timer e de software |
| `src/UART/serial/` | UART 8N1 mapeada em memória: filas parametrizáveis de RX e TX, registradores separados, níveis, flags de status e de erro e interrupção de RX opcional; a camada física é a `uart2bus` do OpenCores, trazida para o repositório |
| `src/UART/jtag/` | UART sobre JTAG: o núcleo escreve e lê bytes por registradores e um hospedeiro faz o mesmo pelo Virtual JTAG (`jtag_uart`); `cyclone-v/` guarda a casca do Virtual JTAG, só para a placa |
| `src/PLIC/soc/` | PLIC: gateways de nível, árbitro por prioridade com desempate por id, registradores no leiaute do `riscv-plic-1.0.0` e a saída `MEIP` (`plic`) |
| `src/intc/soc/` | Controlador de interrupção externa: reúne as linhas de interrupção dos periféricos em um único `MEIP`, com registradores de pendência, habilitação e fonte (`ext_irq_controller`) |
| `src/flash-controller/soc/` | Controlador de FLASH: registradores de comando, endereço, estado e buffer de página que levam os comandos de apagar, gravar e proteger ao chip de FLASH do repositório Memory |
| `src/display/` | Display de sete segmentos: o registrador do valor, o conversor de hexadecimal para segmentos (`soc/`) e a casca do Virtual JTAG da placa (`cyclone-v/`) |
| `tests/python/` | Testes por entidade em cocotb e o catálogo (`tests.json`) que os conduz, em `unittests/{CLINT,GPIO,PLIC,intc,TIMER,UART,display,flash_controller}` |
| `tests/vhdl/` | `gpio_tb`, wrapper que permite ao cocotb dirigir os pinos `inout` da GPIO |
| `formal/` | Propriedades em SystemVerilog de `gpio_cell`, `timer`, `clock_prescaler`, `counter_overflow`, `alu_ge_unsigned`, `clint`, `clint_mtime`, `ext_irq_controller`, `flash_controller`, `uart_fifo` e `uart`, o `run.sh` e o agregador dos engines |
| `docs/pt-br/`, `docs/en/` | Documentos do CLINT (`CLINT/`), do PLIC (`PLIC/`), da UART (`UART/`), do controlador de interrupção externa (`intc/`), do controlador de FLASH (`flash-controller/`), das provas formais (`formal/`) e do defeito da UART sobre JTAG (`bugs/`) |

## 3. Interface

Todo periférico compartilha o mesmo conjunto de portas, conforme o barramento do contrato do Core: `i_clk`, `i_rst`, `i_data_in`, `i_address` (deslocamento em palavras dentro do periférico), `i_write`, `i_read`, `o_data_out` e `o_irq`. Os mapas de registradores estão nas entidades `*_operation_decoder` e em `tests/python/unittests/*/*_operation_decoder.py`.

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
