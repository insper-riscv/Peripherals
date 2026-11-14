// Propriedades do ir_fifo, verificadas na netlist Verilog que o GHDL sintetiza do VHDL, contra uma fila de
// referência que desloca as palavras em vez de usar ponteiros. A fila tem DEPTH posições (3 na prova) e palavras de
// 8 bits. A prova é limitada e cobre todas as sequências de empilhar, remover e esvaziar, com dados quaisquer.
//   1. O nível e as flags de cheia e de vazia seguem o modelo; o esvaziamento zera a fila e vence o empilhamento.
//   2. O empilhamento numa fila cheia é recusado, mesmo com uma remoção no mesmo ciclo, e o aviso o acompanha.
//   3. A palavra mais antiga é a primeira que entrou e ainda não saiu, ou zero com a fila vazia.
`ifndef DEPTH
`define DEPTH 3
`endif
module props (input clk);
  (* anyseq *) wire reset, flush, push, pop;
  (* anyseq *) wire [7:0] data;
  wire full, empty, refused;
  wire [7:0] head;
  wire [1:0] level;

  ir_fifo dut (.i_clk(clk), .i_rst(reset), .i_flush(flush), .i_push(push), .i_push_data(data), .i_pop(pop),
    .o_pop_data(head), .o_full(full), .o_empty(empty), .o_level(level), .o_refused(refused));

  // O primeiro clock é um reset, como na placa; as propriedades valem a partir dele.
  reg f_past = 0;
  initial assume (reset);
  always @(posedge clk) f_past <= 1;

  // Fila de referência: a palavra mais antiga fica na posição zero e uma remoção desloca todas.
  reg [8*`DEPTH-1:0] q = 0;
  reg [1:0] n = 0;
  reg [8*`DEPTH-1:0] t;
  wire m_pop = pop && n != 0;
  wire m_push = push && n != `DEPTH;

  always @(posedge clk) begin
    t = q;
    if (m_pop) t = t >> 8;
    if (m_push) t[8 * (n - m_pop) +: 8] = data;
    q <= (reset || flush) ? 0 : t;
    n <= (reset || flush) ? 2'd0 : n + m_push - m_pop;
  end

  always @(posedge clk) if (f_past) begin
    assert (level == n);
    assert (full == (n == `DEPTH));
    assert (empty == (n == 0));
    assert (refused == (push && n == `DEPTH));
    assert (head == (n == 0 ? 8'h0 : q[7:0]));
  end

`ifdef COVER
  always @(posedge clk) if (f_past) begin
    cover (n == `DEPTH && refused);
    cover (n == `DEPTH && push && pop && refused);
    cover (n == 2 && flush && !reset);
    cover (n == 1 && m_pop && head == 8'hA5);
  end
`endif
endmodule
