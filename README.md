# Peripherals

🌐 [Português](README.md) · [English](README.en.md)

Periféricos mapeados em memória do SoC RISC-V RV32: os blocos com que o núcleo conversa pelo barramento, fora do núcleo e das memórias. O núcleo, as memórias, os topos que os conectam e os programas de teste ficam em outros repositórios da organização [insper-riscv](https://github.com/insper-riscv).

## 1. Documentação

- [AUTHORS.md](AUTHORS.md): autores com commits no repositório, com nome e conta do GitHub.
- [CONTRIBUTING.md](CONTRIBUTING.md): regras obrigatórias de contribuição, norma VHDL-2008, nomenclatura, cabeçalhos, normas Python e verificação antes de abrir Pull Request.
- [CITATION.cff](CITATION.cff): metadados para citação do software.
- [docs/bugs/](docs/bugs/README.md): bugs encontrados na primeira simulação dos periféricos, com as correções.
- [contracts/02-barramento-e-memoria.md](https://github.com/insper-riscv/Core/blob/main/docs/pt-br/contracts/02-barramento-e-memoria.md): protocolo de barramento adotado pelos periféricos.

## 2. Estrutura do Repositório

| Caminho | Conteúdo |
| :--- | :--- |
| `GPIO/` | Entrada e saída de uso geral: direção, saída (carga, set, clear, toggle), leitura sincronizada dos pinos e interrupções por borda de subida e descida em cada pino |
| `TIMER/` | Temporizador e PWM: contador com `TOP`, prescaler, comparador de duty cycle, status de overflow e interrupção |
| `UART/` | UART 8N1 mapeada em memória: registradores separados de byte de RX e TX, flags de status e de erro e interrupção de RX opcional; a camada física é a `uart2bus` do OpenCores, trazida para o repositório |
| `tests/python/` | Testes por entidade em cocotb e o catálogo (`tests.json`) que os conduz, em `unittests/{common,GPIO,TIMER,UART}` |
| `tests/vhdl/` | `gpio_tb`, wrapper que permite ao cocotb dirigir os pinos `inout` da GPIO |

## 3. Interface

Todo periférico compartilha o mesmo conjunto de portas, conforme o barramento do contrato do Core: `clock`, `clear`, `data_in`, `address` (deslocamento em palavras dentro do periférico), `write`, `read`, `data_out` e `irq`. Os mapas de registradores estão nas entidades `*_OPERATION_DECODER` e em `tests/python/unittests/*/*_operation_decoder.py`.

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

### 3.3. Registradores da UART

A UART não exige espera do barramento: o software consulta `TX_READY` e `RX_VALID`, e todo acesso mapeado em memória termina em um ciclo. A configuração inicial de hardware é 115200 baud, 8N1 com clock de 50 MHz. Não há FIFO de RX nem de TX: o RX tem um registrador de byte pendente e o transmissor físico aceita um byte por vez.

| Endereço | Registrador |
| :--- | :--- |
| 0 | `TX_DATA` (só escrita): escrever o byte baixo inicia a transmissão; a leitura devolve zero |
| 1 | `RX_DATA` (só leitura): devolve o byte recebido e limpa `RX_VALID`; a escrita não tem efeito |
| 2 | `STATUS`: bit 0 `RX_VALID`, bit 1 `TX_READY`, bit 2 `RX_OVERRUN`, bit 3 `TX_DROPPED`; escrever 1 nos bits 2 e 3 os limpa |
| 3 | `CONTROL`: o bit 0 habilita o pedido de interrupção do RX |

## 4. Verificação e Execução

```bash
git clone --recurse-submodules https://github.com/insper-riscv/Peripherals.git
git clone https://github.com/insper-riscv/Common-Components.git   # ao lado: flip_flop, multiplexadores, somador e registrador com clear
cd Peripherals
uv sync

make check   # Verificação de sintaxe VHDL de todos os fontes em ordem de dependência (GHDL)
make test    # Testes por entidade em cocotb (make test TEST=GPIO para um alvo)
make paths   # Existência de todos os caminhos listados na configuração
```

As ferramentas (GHDL e uv) vêm da imagem `ci-vhdl` do repositório [Infra](https://github.com/insper-riscv/Infra), onde a integração contínua executa.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](LICENSE).
