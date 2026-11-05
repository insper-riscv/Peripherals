// Propriedades do uart_fifo, verificadas na netlist Verilog que o GHDL sintetiza do VHDL, contra uma fila de
// referência que desloca as palavras em vez de usar ponteiros. A fila tem DEPTH posições (3 na prova): enche,
// esvazia e dá a volta nos ponteiros dentro da profundidade da prova. A prova é limitada (a memória da fila
// não tem estado exposto para a indução) e cobre todas as sequências de inserção e remoção, com dados quaisquer.
//   1. O nível, as flags de cheia e de vazia e as aceitações seguem o modelo, inclusive a inserção numa fila
//      cheia, aceita só junto de uma remoção aceita.
//   2. A palavra mais antiga é a primeira que entrou e ainda não saiu, ou zero com a fila vazia.
`ifndef DEPTH
`define DEPTH 3
`endif
module props (input clk);
  (* anyseq *) wire reset, push, pop;
  (* anyseq *) wire [7:0] data;
  wire acc_push, acc_pop, full, empty;
  wire [7:0] head;
  wire [1:0] level;

  uart_fifo dut (.i_clk(clk), .i_rst(reset), .i_push(push), .i_push_data(data), .i_pop(pop),
    .o_pop_data(head), .o_push_accepted(acc_push), .o_pop_accepted(acc_pop), .o_full(full), .o_empty(empty),
    .o_level(level));

  // O primeiro clock é um reset, como na placa; as propriedades valem a partir dele.
  reg f_past = 0;
  initial assume (reset);
  always @(posedge clk) if (f_past) assume (!reset);
  always @(posedge clk) f_past <= 1;

  // Fila de referência: a palavra mais antiga fica na posição zero e uma remoção desloca todas.
  reg [8*`DEPTH-1:0] q = 0;
  reg [1:0] n = 0;
  reg [8*`DEPTH-1:0] t;
  wire m_pop = pop && n != 0;
  wire m_push = push && (n != `DEPTH || m_pop);

  always @(posedge clk) begin
    t = q;
    if (m_pop) t = t >> 8;
    if (m_push) t[8 * (n - m_pop) +: 8] = data;
    q <= reset ? 0 : t;
    n <= reset ? 2'd0 : n + m_push - m_pop;
  end

  always @(posedge clk) if (f_past) begin
    assert (level == n);
    assert (full == (n == `DEPTH));
    assert (empty == (n == 0));
    assert (acc_push == m_push);
    assert (acc_pop == m_pop);
    assert (head == (n == 0 ? 8'h0 : q[7:0]));
  end

`ifdef COVER
  always @(posedge clk) if (f_past) begin
    cover (n == `DEPTH && m_push && m_pop);
    cover (n == `DEPTH && push && !m_push);
    cover (n == 0 && pop && push && m_push);
    cover (n == 1 && m_pop && head == 8'hA5);
  end
`endif
endmodule
