# Verificação formal

🌐 [Português](../../pt-br/formal/formal.md) · [English](../../en/formal/formal.md)

As provas formais rodam no SymbiYosys sobre a netlist Verilog que o GHDL sintetiza de cada entidade, com as propriedades escritas em SystemVerilog em volta dela (`formal/<entidade>_props.sv`). O método, os engines (`yices`, `bitwuzla`, `boolector` e `abc-bmc3`), o arquivo `build/formal/result-<engine>.tsv` e a regra do agregador `formal/aggregate.sh` são os do Core. Este documento descreve o que se prova nos periféricos.

## 1. O que se prova

| Entidade | Arquivo | Prova | Propriedades |
| :--- | :--- | :--- | :--- |
| `alu_ge_unsigned` | `alu_ge_unsigned_props.sv` | indução, 8 bits | `o_ge` vale exatamente `a >= b` sem sinal, inclusive na igualdade e nos extremos |
| `counter_overflow` | `counter_overflow_props.sv` | indução, 8 bits | O estouro vale exatamente quando o contador alcançou o topo |
| `clock_prescaler` | `clock_prescaler_props.sv` | limitada, 40 ciclos, 3 bits | Com o prescaler $P$ estável e sem reset, o tick sai a cada $P + 1$ ciclos, sem tick perdido nem duplicado, e dura um ciclo |
| `timer` | `timer_props.sv` | indução | Os registradores de configuração, topo, ciclo de trabalho e prescaler só mudam por escrita do barramento (e o reset os leva ao valor inicial, topo todo em um); o contador só zera, carrega ou avança um por tick com a partida ligada, e para ou reinicia no topo conforme o modo; o status sobe uma vez por estouro, é limpo pela leitura e a máscara decide a interrupção; o PWM é alto enquanto o contador está abaixo do ciclo de trabalho; a leitura de cada endereço devolve o registrador certo |
| `gpio_cell` | `gpio_cell_props.sv` | limitada, 16 ciclos | Direção, saída e máscaras só mudam por escrita (set, clear e toggle com a máscara de bit); a leitura do pino é o pino de dois ciclos atrás; o status sobe na borda selecionada pelas máscaras e só desce por leitura ou reset; com a saída ligada e estável a leitura e a saída não divergem |
| `uart` | `uart_props.sv` | indução e limitada, 200 ciclos | Registradores do invólucro contra o contrato (válido, overrun, descarte, máscara, leitura de cada endereço); nenhum byte se perde com o buffer livre; quadro de transmissão com start, oito dados do menos significativo ao mais e stop, 16 ciclos por bit; recepção de um quadro com ruído nas bordas de cada bit de dado, amostrada no meio do bit |

Cada entidade tem um cover que mostra que a situação provada é alcançável.

## 2. Como cada prova é montada

1. O `timer` e o `uart` têm a netlist com os registradores internos expostos como saídas `dbg_*`, o que deixa a indução enunciar o estado sem mudar a lógica.
2. No `gpio_cell` o pino bidirecional da netlist vira uma entrada e uma saída, e o ambiente dirige o pino só quando a direção é de entrada.
3. No `uart` o gerador de baud roda com `baud_freq = 0` e `baud_limit = 0`, o que faz `ce16` valer em todo ciclo e um bit durar 16 ciclos. As razões reais só mudam quanto tempo o `ce16` leva para chegar, e não o formato do quadro nem o ponto de amostragem em ciclos de `ce16`.
4. O `clock_prescaler` usa 3 bits e o prescaler constante e qualquer; o `timer` usa o `tick` do prescaler como entrada do modelo, porque o período do tick é a propriedade do `clock_prescaler`. As duas provas juntas fixam o ritmo do estouro: o contador avança um por tick e o tick sai a cada $P + 1$ ciclos.

## 3. Mutantes

Cada defeito proposital do VHDL precisa fazer uma prova falhar. O `formal/run.sh` aplica cada edição com `sed` numa cópia do arquivo e exige o veredito `fail`.

| Entidade | Mutantes |
| :--- | :--- |
| `alu_ge_unsigned` | `alu_strict`, `alu_no_invert` |
| `counter_overflow` | `ovf_swapped`, `ovf_strict` |
| `clock_prescaler` | `presc_unregistered`, `presc_strict`, `presc_no_clear` |
| `timer` | `timer_top_enable`, `timer_prescaler_enable`, `timer_top_reset`, `timer_mode_inverted`, `timer_start_ignored`, `timer_mask_ignored`, `timer_status_not_cleared`, `timer_level_not_edge`, `timer_pwm_inverted`, `timer_read_select`, `timer_write_address` |
| `gpio_cell` | `cell_dir_always`, `cell_no_set_clear`, `cell_toggle_is_load`, `cell_mask_ignored`, `cell_fall_uses_rise`, `cell_status_not_cleared`, `cell_pin_not_driven` |
| `uart` | `uart_overrun_ignored`, `uart_read_keeps_valid`, `uart_drop_not_flagged`, `uart_write_when_busy`, `uart_irq_mask_ignored`, `uart_status_ready_inverted`, `uart_tx_stop_low`, `uart_tx_start_high`, `uart_tx_short_frame`, `uart_rx_early_sample`, `uart_rx_late_sample`, `uart_rx_msb_first` |

## 4. Rodando

```bash
make formal                          # engine padrão (bitwuzla)
make formal FORMAL_ENGINE=yices      # outro engine
```

O `abc-bmc3` pula as provas de indução e os covers, que não faz, e responde pelas provas limitadas e pelos mutantes.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).
