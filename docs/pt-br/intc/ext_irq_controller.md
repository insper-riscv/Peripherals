# Controlador de interrupção externa

## 1. O que é

O controlador reúne as linhas de interrupção de nível dos periféricos em um único pedido de interrupção externa, o `MEIP` do núcleo. O software lê o estado das linhas, escolhe quais delas contam e descobre qual está ativa, tudo por registradores de 32 bits no mesmo barramento dos outros periféricos. Não há prioridade programável, limiar nem reivindicação: a interrupção é de nível e o software limpa a causa no periférico de origem.

| Item | Valor |
| :--- | :--- |
| Entidade | `ext_irq_controller` |
| Linhas | `irq_count`, de 1 a `data_width` (8 por padrão) |
| Sincronização | `sync_stages` flip-flops por linha (2 por padrão), pelo `synchronizer` do Common-Components |
| Acesso mapeado | Leitura combinacional e escrita de 1 ciclo, sem espera do barramento |
| Saída | `o_irq_external`, ativa em `1` |

## 2. Registradores

O endereço tem 2 bits e conta palavras. Os valores estão no pacote `ext_irq_consts`.

| Palavra | Nome | Leitura | Escrita |
| ---: | :--- | :--- | :--- |
| 0 | `PENDING` | O bit $n$ é a linha $n$ já sincronizada | Ignorada |
| 1 | `ENABLE` | O bit $n$ habilita a linha $n$ | Grava os bits das linhas existentes |
| 2 | `SOURCE_ID` | Índice da linha ativa de menor índice mais um, ou zero | Ignorada |
| 3 | reservado | Zero | Ignorada |

Os bits acima da última linha leem zero e não são gravados. O `ENABLE` vale zero depois do reset, e a leitura de qualquer registrador não tem efeito colateral.

## 3. Comportamento

Seja $p$ o vetor `PENDING` e $e$ o vetor `ENABLE`. A saída é

$$o\_irq\_external = \big( (p \wedge e) \ne 0 \big)$$

e acompanha as linhas depois da latência do sincronizador, de `sync_stages` ciclos. Como a interrupção é de nível, a saída cai quando a linha cai, sem trava.

O `SOURCE_ID` vale $k + 1$, em que $k$ é o menor índice com $p_k \wedge e_k = 1$, e zero quando não há nenhum. A linha de menor índice vence sempre, e a soma de um mantém o zero como "sem fonte".

## 4. Ligação

1. Cada periférico com saída de interrupção (por exemplo, `o_irq` do `TIMER`, da `GPIO` e da `UART`) liga a uma linha de `i_irq_lines`.
2. `o_irq_external` liga à porta `MEIP` do núcleo, e o software habilita a interrupção no `mie` (`MEIE`).
3. A rotina de tratamento lê `SOURCE_ID` para saber qual periférico atender, limpa a causa nele e retorna.

## 5. Verificação

| Verificação | Arquivo | O que cobre |
| :--- | :--- | :--- |
| Teste de entidade | `tests/python/unittests/intc/ext_irq_controller.py` | Reset, cada linha com a latência do sincronizador, máscara, leitura de volta do `ENABLE`, saída de nível, várias fontes e `SOURCE_ID`, escritas ignoradas, leitura sem efeito colateral e reset |
| Prova formal | `formal/ext_irq_controller_props.sv` | Limitada, 12 ciclos, 4 linhas: a saída vale exatamente $(p \wedge e) \ne 0$, cada endereço devolve o registrador certo e o `SOURCE_ID` é a linha ativa de menor índice mais um |

O cover mostra que duas fontes ativas, uma só e uma linha pendente mascarada são alcançáveis. Os mutantes `extirq_mask_ignored`, `extirq_or_not_and`, `extirq_write_any_address`, `extirq_enable_not_reset`, `extirq_highest_wins`, `extirq_id_zero_based`, `extirq_pending_is_enable` e `extirq_reserved_reads_id` precisam fazer a prova falhar.
