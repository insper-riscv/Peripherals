// Propriedades do ext_irq_controller (4 linhas, sincronizador de 2 estágios), verificadas na netlist Verilog que o
// GHDL sintetiza do VHDL. O modelo de referência guarda a cadeia de sincronização (h1, h2) e a máscara (m_en), ambas
// zeradas pelo reset. Os registradores não têm valor inicial: o primeiro clock é um reset, como na placa.
module props (input clk);
  (* anyseq *) wire reset, wr, rd;
  (* anyseq *) wire [3:0] lines;
  (* anyseq *) wire [1:0] addr;
  (* anyseq *) wire [31:0] d;
  wire [31:0] q;
  wire irq;

  ext_irq_controller dut (.i_clk(clk), .i_rst(reset), .i_irq_lines(lines), .i_data_in(d), .i_address(addr),
    .i_write(wr), .i_read(rd), .o_data_out(q), .o_irq_external(irq));

  initial assume (reset);

  reg f_past = 0;
  reg [3:0] h1 = 0, h2 = 0, m_en = 0;

  // Linhas pendentes e habilitadas, e a de menor índice mais um.
  wire [3:0] act = h2 & m_en;
  wire [31:0] sid = act[0] ? 32'd1 : act[1] ? 32'd2 : act[2] ? 32'd3 : act[3] ? 32'd4 : 32'd0;

  always @(posedge clk) begin
    f_past <= 1;
    h1   <= reset ? 4'd0 : lines;
    h2   <= reset ? 4'd0 : h1;
    m_en <= reset ? 4'd0 : ((wr && addr == 2'd1) ? d[3:0] : m_en);
  end

  always @(posedge clk) if (f_past) begin
`ifndef COVER
    // 1. A saída vale exatamente (pendente e habilitada) diferente de zero.
    assert (irq == (act != 4'd0));
    // 2. Cada endereço devolve o registrador certo, e o endereço reservado lê zero.
    if (addr == 2'd0) assert (q == {28'd0, h2});
    if (addr == 2'd1) assert (q == {28'd0, m_en});
    if (addr == 2'd2) assert (q == sid);
    if (addr == 2'd3) assert (q == 32'd0);
    // 3. Sem linhas pendentes e habilitadas não há fonte; com alguma, a fonte é a de menor índice.
    assert ((sid == 32'd0) == (act == 4'd0));
`else
    // Duas fontes ativas ao mesmo tempo, e uma só.
    cover (irq && act == 4'b1010);
    cover (irq && act == 4'b0100);
    cover (!irq && h2 != 4'd0);
`endif
  end
endmodule
