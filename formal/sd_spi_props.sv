// Propriedades do sd_spi (controlador de cartão SD no modo SPI), verificadas na netlist Verilog que o GHDL
// sintetiza do VHDL, com filas de 3 bytes e o divisor de reset em zero (SCLK a um quarto do clock). O primeiro
// clock é um reset, como na placa; as propriedades valem a partir dele.
//   REGS (padrão)  CONTROL e DIVIDER guardam o que se escreve e leem de volta, a seleção de chip e a interrupção
//                  seguem o CONTROL, as marcas persistentes só caem por escrita de 1 em STATUS, o reset zera tudo
//                  e o bit BUSY de STATUS cobre o byte em andamento.
//   BYTE           Sem escrita no divisor: cada byte tem exatamente 8 bordas de subida de SCLK, SCLK e o pulso de
//                  fim só ocorrem com o byte em andamento e MOSI fica em nível alto quando o mestre está ocioso.
`ifndef DIVRST
`define DIVRST 0
`endif
module props (input clk);
  (* anyseq *) wire rst, we, re, miso;
  (* anyseq *) wire [2:0] adr;
  (* anyseq *) wire [31:0] wdata;
  wire [31:0] rdata;
  wire irq, sclk, mosi, cs_n;
  wire dbg_phy_busy, dbg_phy_done, dbg_tx_fifo_empty, dbg_rx_fifo_empty;
  wire dbg_done_flag, dbg_rx_overrun, dbg_tx_dropped, dbg_cs_assert;
  wire [15:0] dbg_divider;

  sd_spi dut (.i_clk(clk), .i_rst(rst), .i_data_in(wdata), .i_address(adr), .i_write(we), .i_read(re),
    .o_data_out(rdata), .o_irq(irq), .o_sd_sclk(sclk), .o_sd_mosi(mosi), .i_sd_miso(miso), .o_sd_cs_n(cs_n),
    .dbg_phy_busy(dbg_phy_busy), .dbg_phy_done(dbg_phy_done), .dbg_tx_fifo_empty(dbg_tx_fifo_empty),
    .dbg_rx_fifo_empty(dbg_rx_fifo_empty), .dbg_done_flag(dbg_done_flag), .dbg_rx_overrun(dbg_rx_overrun),
    .dbg_tx_dropped(dbg_tx_dropped), .dbg_cs_assert(dbg_cs_assert), .dbg_divider(dbg_divider));

  reg f_past = 0;
  reg [4:0] m_ctl = 0;
  reg [15:0] m_div = `DIVRST;
  reg d_ovr = 0, d_drop = 0, d_done = 0, sclk_prev = 0;
  reg [3:0] rises = 0;
  // Pedido de limpeza de cada marca no ciclo anterior (escrita em STATUS com o bit dela em 1) e reset anterior.
  reg p_clear_ovr = 0, p_clear_drop = 0, p_clear_done = 0, p_rst = 0;
  reg p_event_done = 0;

  wire wr_ctl = we && adr == 3'd3;
  wire wr_div = we && adr == 3'd4;
  wire wr_sts = we && adr == 3'd2;

  always @(posedge clk) begin
    f_past <= 1;
    d_ovr <= dbg_rx_overrun; d_drop <= dbg_tx_dropped; d_done <= dbg_done_flag;
    sclk_prev <= sclk;
    if (rst) begin
      m_ctl <= 0; m_div <= `DIVRST; rises <= 0;
    end else begin
      if (wr_ctl) m_ctl <= wdata[4:0];
      if (wr_div) m_div <= wdata[15:0];
      if (dbg_phy_done) rises <= 0;
      else if (sclk && !sclk_prev) rises <= rises + 1;
    end
  end

  always @* if (!f_past) assume (rst);
`ifdef BYTE
  always @* assume (!wr_div);
`endif

  always @(posedge clk) if (f_past) begin
`ifndef BYTE
    // 1. CONTROL e DIVIDER leem de volta o que foi escrito, e uma escrita em outro endereço não os altera.
    if (adr == 3'd3) assert (rdata == {27'b0, m_ctl});
    if (adr == 3'd4) assert (rdata == {16'b0, m_div});
    assert (dbg_cs_assert == m_ctl[0]);
    assert (cs_n == !m_ctl[0]);
    assert (dbg_divider == m_div);
    // 2. A saída de interrupção soma quatro causas, cada uma com a sua habilitação.
    assert (irq == ((m_ctl[1] && !dbg_rx_fifo_empty) || (m_ctl[2] && dbg_tx_fifo_empty) ||
                    (m_ctl[3] && dbg_done_flag) || (m_ctl[4] && (dbg_rx_overrun || dbg_tx_dropped))));
    // 3. Uma marca persistente só cai por reset ou se a escrita em STATUS levou 1 no bit dela no ciclo anterior.
    if (d_ovr && !dbg_rx_overrun) assert (p_clear_ovr || p_rst);
    if (d_drop && !dbg_tx_dropped) assert (p_clear_drop || p_rst);
    if (d_done && !dbg_done_flag) assert (p_clear_done || p_rst);
    // 3b. Uma escrita de 1 em DONE sem fim de byte no mesmo ciclo limpa a marca.
    if (p_clear_done && !p_event_done && !p_rst) assert (!dbg_done_flag);
    // 4. STATUS reflete as filas e o mestre.
    if (adr == 3'd2) begin
      assert (rdata[0] == !dbg_rx_fifo_empty);
      assert (rdata[2] == dbg_tx_fifo_empty);
      assert (rdata[3] == (dbg_phy_busy || dbg_phy_done || !dbg_tx_fifo_empty));
      assert (rdata[5] == dbg_done_flag && rdata[6] == dbg_rx_overrun && rdata[7] == dbg_tx_dropped);
      assert (rdata[31:24] == 8'd0);
    end
    // 5. O reset deixa tudo ocioso.
    if (p_rst) begin
      assert (!irq && cs_n && !dbg_done_flag && !dbg_rx_overrun && !dbg_tx_dropped);
      assert (dbg_rx_fifo_empty && dbg_tx_fifo_empty && !dbg_phy_busy);
    end
`else
    // 6. SCLK só se move com o byte em andamento, e o byte acaba com oito bordas de subida.
    if (!dbg_phy_busy) assert (!sclk);
    if (!dbg_phy_busy) assert (mosi);
    if (dbg_phy_done) assert (!dbg_phy_busy && rises == 4'd8);
`endif
  end

  always @(posedge clk) begin
    p_clear_ovr <= wr_sts && wdata[6]; p_clear_drop <= wr_sts && wdata[7]; p_clear_done <= wr_sts && wdata[5];
    p_rst <= rst;
    p_event_done <= dbg_phy_done && dbg_tx_fifo_empty;
  end

`ifdef COVER
  always @(posedge clk) if (f_past) begin
`ifndef BYTE
    cover (irq && m_ctl[3] && dbg_done_flag);
    cover (irq && m_ctl[1] && !dbg_rx_fifo_empty);
    cover (dbg_tx_dropped);
`else
    cover (dbg_phy_done);
    cover (dbg_phy_done && rises == 4'd8 && mosi);
`endif
  end
`endif
endmodule
