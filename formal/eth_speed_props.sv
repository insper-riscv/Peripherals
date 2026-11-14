// Propriedades do eth_speed, verificadas na netlist Verilog que o GHDL sintetiza do VHDL. O mestre MDIO e o
// programa são entradas livres, e os registradores do modo, da velocidade aprendida e do estado da consulta são
// expostos pelo script.
//   1. O registrador de modo é o dado escrito no endereço SPEED_ADDR (14) e nenhum outro.
//   2. A velocidade em uso é a aprendida no modo automático e a forçada nos outros, e nunca é o código 11.
//   3. A palavra lida em SPEED é o modo, a velocidade em uso e os três bits da última resposta do PHY, e mais nada.
//   4. A consulta só começa a ler o registrador 17 do PHY de endereço 16, nunca no mesmo ciclo de um pedido do
//      programa, e o mestre aparece ocupado ao programa durante toda a consulta.
//   5. (limitada, com -DSEQ) A velocidade aprendida só muda no fim de uma leitura que o PHY respondeu, com enlace ativo e velocidade
//      resolvida, e passa a valer os bits 15 a 14 lidos.
module props (input clk);
  (* anyseq *) wire rst, write, sw_start, mdio_busy, mdio_done, no_ack;
  (* anyseq *) wire [5:0] address;
  (* anyseq *) wire [31:0] data_in;
  (* anyseq *) wire [15:0] rdata;
  wire [31:0] data_out;
  wire start, hold;
  wire [4:0] phy, reg_addr;
  wire [1:0] speed;
  wire [1:0] dbg_mode, dbg_learned, dbg_state;

  eth_speed dut (.i_clk(clk), .i_rst(rst), .i_write(write), .i_address(address), .i_data_in(data_in),
    .o_data_out(data_out), .i_sw_start(sw_start), .i_mdio_busy(mdio_busy), .i_mdio_done(mdio_done),
    .i_mdio_no_ack(no_ack), .i_mdio_rdata(rdata), .o_mdio_start(start), .o_mdio_phy_addr(phy),
    .o_mdio_reg_addr(reg_addr), .o_mdio_hold(hold), .o_speed(speed),
    .dbg_mode(dbg_mode), .dbg_learned(dbg_learned), .dbg_state(dbg_state));

  // O modelo do registrador de modo, com o valor inicial do VHDL.
  reg [1:0] m_mode = 2'b00;
  always @(posedge clk) begin
    if (rst) m_mode <= 2'b00;
    else if (write && address == 6'b001110) m_mode <= data_in[1:0];
  end

  // Valores de um ciclo atrás, para a propriedade da velocidade aprendida.
  reg past_valid = 0;
  reg [1:0] past_learned = 2'b10, past_state = 0;
  reg past_rst = 1, past_done = 0, past_no_ack = 0;
  reg [15:0] past_rdata = 0;
  always @(posedge clk) begin
    past_valid <= 1;
    past_learned <= dbg_learned;
    past_state <= dbg_state;
    past_rst <= rst;
    past_done <= mdio_done;
    past_no_ack <= no_ack;
    past_rdata <= rdata;
  end

  wire [1:0] forced = m_mode == 2'b01 ? 2'b00 : (m_mode == 2'b10 ? 2'b01 : 2'b10);

  always @* begin
    assert (dbg_mode == m_mode);
    assert (dbg_state != 2'b11);
    assert (dbg_learned != 2'b11);
    assert (speed == (m_mode == 2'b00 ? dbg_learned : forced));
    assert (speed != 2'b11);
    assert (data_out[1:0] == m_mode);
    assert (data_out[5:4] == speed);
    assert (data_out[3:2] == 2'b00 && data_out[7:6] == 2'b00 && data_out[31:11] == 0);
    assert (hold == (dbg_state != 2'b00));
    assert (!(start && sw_start));
    assert (!start || dbg_state == 2'b01);
    assert (phy == 5'd16 && reg_addr == 5'd17);
  end

`ifdef SEQ
  always @(posedge clk) if (past_valid && !past_rst) begin
    if (dbg_learned != past_learned) begin
      assert (past_state == 2'b10 && past_done && !past_no_ack && past_rdata[10] && past_rdata[11]);
      assert (dbg_learned == past_rdata[15:14]);
    end
  end
`endif

`ifdef COVER
  always @(posedge clk) begin
    cover (past_valid && !past_rst && dbg_learned != past_learned);
    cover (past_valid && start);
    cover (past_valid && sw_start && dbg_state == 2'b01);
  end
`endif
endmodule
