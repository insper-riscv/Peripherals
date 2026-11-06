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
| `clint_mtime` | `clint_mtime_props.sv` | limitada, 12 ciclos | O valor mostrado (metade alta com o vai-um pendente) é sempre o do contador ideal de 64 bits: soma um por incremento, a escrita vence o incremento do próprio ciclo e o vai-um entre as metades nunca se perde |
| `clint` | `clint_props.sv` | limitada, 20 ciclos, `tick_cycles` 3 | `MTIP` é a comparação sem sinal de 64 bits do ciclo anterior, `MSIP` é o bit 0 do `msip`, o `mtime` soma um a cada três ciclos e a leitura de cada endereço (inclusive fora do mapa) devolve o registrador do modelo; na escrita do porte (baixa com `0xFFFFFFFF`, alta, baixa) o `MTIP` só vale se o valor antigo ou o final do `mtimecmp` já foi alcançado pelo `mtime` |
| `plic_gateway` | `plic_gateway_props.sv` | limitada, 16 ciclos | O pendente segue o gateway ideal: um pedido por atendimento, o claim o limpa, só o complete desmascara a fonte e o pendente não cai com a linha |
| `plic_arbiter` | `plic_arbiter_props.sv` | indução, 6 fontes, 3 bits | `o_id` é a fonte pendente e habilitada de maior prioridade estritamente acima do limiar, com desempate pelo menor id, e zero com `o_valid` baixo sem candidata |
| `plic` | `plic_props.sv` | limitada, 14 ciclos, 4 fontes, 2 bits | `o_meip` vale exatamente quando existe uma candidata; o claim devolve a candidata de maior prioridade com desempate por id, ou zero; o complete desmascara só a fonte escrita e habilitada; o pedido nasce numa fonte livre com a linha em 1; a leitura de cada endereço e o estado visível seguem o modelo |
| `gpio_cell` | `gpio_cell_props.sv` | limitada, 16 ciclos | Direção, saída e máscaras só mudam por escrita (set, clear e toggle com a máscara de bit); a leitura do pino é o pino de dois ciclos atrás; no modo de nível o status sobe com o nível alto (máscara de subida) ou baixo (máscara de descida); o status sobe na borda selecionada pelas máscaras e só desce por leitura ou reset; com a saída ligada e estável a leitura e a saída não divergem |
| `uart_fifo` | `uart_fifo_props.sv` | limitada, 14 ciclos, 3 palavras | Nível, flags de cheia e de vazia e aceitações seguem uma fila de referência que desloca as palavras; uma inserção numa fila cheia só é aceita junto de uma remoção aceita; a palavra mais antiga é a primeira que entrou e ainda não saiu, ou zero com a fila vazia |
| `jtag_uart` | `jtag_uart_props.sv` | limitada, 14 ciclos, filas de 4 bytes | Com o lado do hospedeiro parado, `CONTROL` guarda e devolve os três bits, e a interrupção é o OU de transmissão vazia habilitada e erro habilitado, com o erro limpo pela leitura de `STATUS` |
| `uart` | `uart_props.sv` | indução e limitada, 200 ciclos | Níveis das filas, flags de overrun e de descarte, máscara, as três causas de interrupção (recepção, transmissor vazio e erro) e leitura de cada endereço contra o contrato, a partir de qualquer estado; o byte da fila de transmissão só chega ao PHY com ele livre; quadro de transmissão com start, oito dados do menos significativo ao mais e stop, 16 ciclos por bit; recepção de um quadro com ruído nas bordas de cada bit de dado, amostrada no meio do bit |
| `flash_controller` | `flash_controller_props.sv` | limitada, 14 ciclos, página de 4 palavras | O pulso de comando sai só da escrita no registrador 0, com os três bits baixos do dado e o endereço guardado; a leitura de cada endereço devolve o endereço do comando, o estado do chip, o índice do buffer ou os registradores de interrupção, e zero nos demais e sem leitura; a conclusão e a recusa do chip viram bits de status que só a escrita de um limpa, e `o_irq` é o OU do status com a habilitação; o índice do buffer avança a cada escrita de dado e é definido pela escrita no registrador 3; o chip lê do buffer, uma borda depois, a palavra que a escrita deixou no índice |

Cada entidade tem um cover que mostra que a situação provada é alcançável.

## 2. Como cada prova é montada

1. O `timer` e o `uart` têm a netlist com os registradores internos e os níveis das filas expostos como saídas `dbg_*`, o que deixa a indução enunciar o estado sem mudar a lógica.
2. No `gpio_cell` o pino bidirecional da netlist vira uma entrada e uma saída, e o ambiente dirige o pino só quando a direção é de entrada.
3. No `uart` o gerador de baud roda com `baud_freq = 0` e `baud_limit = 0`, o que faz `ce16` valer em todo ciclo e um bit durar 16 ciclos. As razões reais só mudam quanto tempo o `ce16` leva para chegar, e não o formato do quadro nem o ponto de amostragem em ciclos de `ce16`. As filas têm 3 posições na prova, o menor valor com ponteiros que dão a volta fora de uma potência de dois, o que deixa o enchimento ao alcance da indução e dos covers.
4. O `clock_prescaler` usa 3 bits e o prescaler constante e qualquer; o `timer` usa o `tick` do prescaler como entrada do modelo, porque o período do tick é a propriedade do `clock_prescaler`. As duas provas juntas fixam o ritmo do estouro: o contador avança um por tick e o tick sai a cada $P + 1$ ciclos.

## 3. Mutantes

Cada defeito proposital do VHDL precisa fazer uma prova falhar. O `formal/run.sh` aplica cada edição com `sed` numa cópia do arquivo e exige o veredito `fail`.

| Entidade | Mutantes |
| :--- | :--- |
| `alu_ge_unsigned` | `alu_strict`, `alu_no_invert` |
| `counter_overflow` | `ovf_swapped`, `ovf_strict` |
| `clock_prescaler` | `presc_unregistered`, `presc_strict`, `presc_no_clear` |
| `timer` | `timer_top_enable`, `timer_prescaler_enable`, `timer_top_reset`, `timer_mode_inverted`, `timer_start_ignored`, `timer_mask_ignored`, `timer_status_not_cleared`, `timer_level_not_edge`, `timer_pwm_inverted`, `timer_read_select`, `timer_write_address` |
| `clint_mtime` | `mtime_carry_lost`, `mtime_hi_incoherent`, `mtime_write_loses` |
| `clint` | `clint_msip_bit`, `clint_cmp_reset_zero`, `clint_cmp_hi_address`, `clint_mtip_unregistered`, `clint_read_swapped`, `clint_tick_early`, `clint_mtime_hi_address`, `clint_strict_compare`, `clint_seq_cmp_clear_not_ones` |
| `plic_gateway` | `plicgw_no_mask`, `plicgw_claim_ignored`, `plicgw_complete_ignored`, `plicgw_reset_ignored` |
| `plic_arbiter` | `plicarb_tie_highest`, `plicarb_threshold_not_strict`, `plicarb_enable_ignored`, `plicarb_pending_ignored`, `plicarb_threshold_ignored`, `plicarb_last_wins` |
| `plic` | `plic_claim_not_clearing`, `plic_complete_any_id`, `plic_complete_ignores_enable`, `plic_complete_any_address`, `plic_claim_any_address`, `plic_priority_address`, `plic_pending_reads_enable`, `plic_meip_constant`, `plic_threshold_shifted`, `plic_claim_reads_zero`, `plic_enable_not_reset`, `plic_enable_bit_shifted`, `plic_claim_address` |
| `gpio_cell` | `cell_dir_always`, `cell_no_set_clear`, `cell_toggle_is_load`, `cell_mask_ignored`, `cell_fall_uses_rise`, `cell_status_not_cleared`, `cell_level_ignored`, `cell_level_fall_is_high`, `cell_level_mode_write`, `cell_pin_not_driven` |
| `uart_fifo` | `fifo_no_wrap`, `fifo_overwrite_when_full`, `fifo_no_reuse_on_pop`, `fifo_pop_not_counted`, `fifo_push_not_counted`, `fifo_pop_keeps_head`, `fifo_empty_shows_data`, `fifo_pop_when_empty` |
| `flash_controller` | `flashc_ptr_stuck`, `flashc_cmd_any_write`, `flashc_status_swapped`, `flashc_addr_any_write`, `flashc_op_shifted`, `flashc_word_misplaced`, `flashc_read_ungated`, `flashc_ptr_write_ignored`, `flashc_done_on_busy_rising`, `flashc_refused_level`, `flashc_irq_mask_ignored`, `flashc_w1c_clears_all`, `flashc_event_loses_to_clear`, `flashc_status_bit_lost` |
| `jtag_uart` | `jtagu_tx_empty_inverted`, `jtagu_error_mask_ignored`, `jtagu_control_bit_swapped`, `jtagu_lost_stays` |
| `uart` | `uart_overrun_ignored`, `uart_drop_not_flagged`, `uart_w1c_wrong_bit`, `uart_tx_pops_when_busy`, `uart_rx_pops_on_any_read`, `uart_irq_mask_ignored`, `uart_irq_tx_empty_inverted`, `uart_irq_error_ignores_drop`, `uart_irq_error_mask_ignored`, `uart_control_bit_swapped`, `uart_status_ready_inverted`, `uart_idle_ignores_phy`, `uart_levels_swapped`, `uart_tx_stop_low`, `uart_tx_start_high`, `uart_tx_short_frame`, `uart_rx_early_sample`, `uart_rx_late_sample`, `uart_rx_msb_first` |

## 4. Rodando

```bash
make formal                          # engine padrão (bitwuzla)
make formal FORMAL_ENGINE=yices      # outro engine
```

O `abc-bmc3` pula as provas de indução e os covers, que não faz, e responde pelas provas limitadas e pelos mutantes.

## 5. Avisos são erros

Um aviso do GHDL, do Yosys ou do SymbiYosys indica código fora da norma ou no limite dela, e a causa se corrige no código ou na prova. Nenhuma opção esconde um aviso (`-Wno-*` não existe no `formal/run.sh`).

1. Depois de cada `ghdl -a` e `ghdl --synth`, o `formal/run.sh` varre a saída do GHDL. Depois de cada `sby`, varre todos os logs da prova. Isso vale para as provas e para os mutantes.
2. A função `scan_warnings` casa a palavra `warning` ou o plural, em qualquer caixa, como palavra inteira. Pega `arquivo.vhd:12:5:warning: ...` do GHDL e `Warning: ...` do Yosys e do SymbiYosys. Não pega nomes com sublinhado (`warning_count`), porque o sublinhado faz parte da palavra, e ignora o resumo do Yosys com contagem zero (`Warnings: 0 unique messages, 0 total`).
3. Cada linha encontrada vai para `build/formal/warnings.txt` e para a saída de erro no formato `arquivo:linha:texto`. No fim da execução, um `warnings.txt` não vazio reprova o `formal/run.sh`.
4. Há uma exceção exata, só para o motor `abc-bmc3`: as três mensagens que o próprio ABC imprime sobre o arquivo AIGER que o SymbiYosys lhe entrega (`Treating undriven bit props.\clk like $anyseq`, `Treating a total of N undriven bits in props like $anyseq` e `The last N outputs are interpreted as constraints`). Elas descrevem o formato de arquivo da ferramenta, não o projeto, e estão na variável `abc_notes`. Yices, bitwuzla e boolector não têm exceção, e qualquer outra mensagem, em qualquer motor, é erro.

Os avisos que a netlist de cada prova tinha e a causa tratada:

| Aviso | Origem | Tratamento |
| :--- | :--- | :--- |
| `comparing non-numeric vector is unexpected` | `baudGen.vhd` (OpenCores), comparação de `std_logic_vector` | A comparação passa a ser entre `unsigned`, com o comportamento igual e a mudança registrada no cabeçalho e no `ORIGIN.md` |
| `unhandled attribute "ramstyle"` e `"altera_attribute"` | Dicas de síntese do Quartus em `uart_fifo.vhd` e `synchronizer.vhd` | O GHDL não conhece estes atributos, que não mudam a lógica provada. A netlist é sintetizada de uma cópia sem estas duas dicas, com as linhas no mesmo lugar. Qualquer outro atributo desconhecido segue sendo erro |
| `Wire ... is used but has no driver` | Multiplexador de leitura da fila de 3 palavras depois do `memory_map` (inclusive no abc-bmc3), cujo quarto endereço nunca é alcançado | O ramo sem driver recebe zero (`setundef -undriven -zero`) |
| `Yosys has only limited support for tri-state logic` | Saída PWM de três estados do `timer` | O estado de alta impedância vira zero na netlist, como no pino do `gpio_cell`. As propriedades olham o registrador interno do PWM, não o pino |
| `Identifier ... is implicitly declared` e `Wire ... is used but has no driver` | Mutantes que deixam um sinal exposto sem leitor (`timer_level_not_edge`, `uart_levels_swapped`), que o GHDL não escreve na netlist | A saída `dbg_` de um sinal que não existe na netlist é a constante zero, e o mutante segue sendo pego pelas propriedades dos sinais que ele muda |

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).
