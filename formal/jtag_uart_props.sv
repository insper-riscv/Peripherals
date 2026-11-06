// Propriedades do lado do core do jtag_uart (interrupção), verificadas na netlist Verilog que o GHDL sintetiza do
// VHDL, com filas de 4 bytes (log2_depth = 2; a lógica é a mesma das de 64). O lado do hospedeiro fica parado
// (tdi e os estados da cadeia em zero, e tck ligado ao clock para a netlist ter um só domínio), então a fila de recepção nunca recebe e a de transmissão só esvazia
// no reset: as propriedades cobrem o registrador CONTROL, a causa de transmissão vazia e a causa de erro. A
// causa de recepção é coberta pelo teste de entidade, que conduz a cadeia JTAG. O primeiro clock é um reset.
module props (input clk);
  (* anyseq *) wire rst, we, re;
  (* anyseq *) wire [7:0] adr;
  (* anyseq *) wire [31:0] wdata;
  wire [31:0] rdata;
  wire irq, tdo;

  jtag_uart dut (.i_clk(clk), .i_rst(rst), .i_addr(adr), .i_wdata(wdata), .i_we(we), .i_re(re), .o_rdata(rdata),
    .o_irq(irq), .i_tck(clk), .i_tdi(1'b0), .o_tdo(tdo), .i_ir_in(2'b00), .i_state_cdr(1'b0),
    .i_state_sdr(1'b0), .i_state_udr(1'b0), .i_state_uir(1'b0));

  reg f_past = 0;
  reg [2:0] m_en = 0;
  reg [2:0] m_tx = 0;
  reg m_lost = 0;

  wire wr_tx = we && adr == 8'd0;
  wire rd_stat = re && adr == 8'd2;

  always @(posedge clk) begin
    f_past <= 1;
    if (rst) begin
      m_en <= 0; m_tx <= 0; m_lost <= 0;
    end else begin
      if (we && adr == 8'd3) m_en <= wdata[2:0];
      if (wr_tx) begin
        if (m_tx == 3'd4) m_lost <= 1; else m_tx <= m_tx + 1;
      end
      if (rd_stat) m_lost <= 0;
    end
  end

  always @* if (!f_past) assume (rst);
  always @* if (f_past) assume (!rst);

  always @(posedge clk) if (f_past) begin
    // 1. CONTROL guarda três bits e lê de volta; a escrita em outro endereço não o altera.
    if (re && adr == 8'd3) assert (rdata == {29'b0, m_en});
    // 2. A saída é de nível: transmissão vazia habilitada ou erro habilitado (recepção nunca recebe aqui).
    assert (irq == ((m_tx == 3'd0 && m_en[1]) || (m_lost && m_en[2])));
  end

`ifdef COVER
  always @(posedge clk) if (f_past) begin
    cover (irq && m_en[1] && m_tx == 3'd0);
    cover (irq && m_en[2] && m_lost);
    cover (!irq && m_en[1] && m_tx != 3'd0);
  end
`endif
endmodule
