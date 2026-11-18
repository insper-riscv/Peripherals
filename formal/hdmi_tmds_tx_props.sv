// Propriedades do hdmi_tmds_tx, verificadas na netlist Verilog que o GHDL sintetiza do VHDL, com os três clocks
// (sistema, pixel e serial) livres (multiclock): cada um sobe a qualquer momento, em qualquer razão. O invólucro só
// liga o hdmi_tx ao tmds_tx, então as provas olham a fiação que ele mesmo faz, lida pelo barramento do sistema.
//   1. O bit 0 do estado do HDMI (endereço 9) é o pino i_hpd passado pelo sincronizador de dois estágios do
//      sistema, e mais nada.
//   2. Sem o sequenciador do ADV7513, os demais bits do estado (ocupado, concluído, NACK, presente) e todos os bits
//      acima do bit 0 valem zero.
// Os dados de pixel e os pares TMDS são conferidos pelo cocotb, que decodifica o fluxo.
module props (input clk);
  (* anyseq *) wire sclk, pclk, xclk;
  (* anyseq *) wire rst, hpd, write;
  (* anyseq *) wire [10:0] address;
  (* anyseq *) wire [31:0] data_in;
  (* anyseq *) wire [3:0] byteena;
  wire [31:0] data_out;
  wire irq, clk_p;
  wire [2:0] tmds_d;

  hdmi_tmds_tx dut (.i_clk(sclk), .i_pixel_clk(pclk), .i_serial_clk(xclk), .i_rst(rst),
    .i_data_in(data_in), .i_address(address), .i_byteena(byteena), .i_write(write),
    .o_data_out(data_out), .o_irq(irq), .i_hpd(hpd), .o_tmds_d(tmds_d), .o_tmds_clk(clk_p));

  // O modelo do sincronizador do pino, com o valor inicial '0' do VHDL e sem reset, como o do hdmi_tx.
  reg m_stage = 0, m_sync = 0;
  always @(posedge sclk) begin
    m_stage <= hpd;
    m_sync  <= m_stage;
  end

  wire status = address == 11'd9;

  always @* begin
    if (status) begin
      assert (data_out[0] == m_sync);
      assert (data_out[31:1] == 0);
    end
  end

`ifdef COVER
  always @* begin
    cover (status && data_out[0]);
    cover (status && !data_out[0] && m_stage);
  end
`endif
endmodule
