// Propriedades do i2c_master, verificadas na netlist Verilog que o GHDL sintetiza do VHDL, com o divisor de reset
// calculado de clk_freq 100 e scl_freq 5 (divisor 3). O barramento, as entradas SCL e SDA e a máquina de linha são
// livres; um modelo de referência segue o que o processador escreve e os eventos da máquina de linha (fim de comando,
// NACK e arbitragem perdida, expostos como dbg_core_*), e a prova exige que cada registrador, cada leitura e a
// interrupção sejam os do modelo. O primeiro clock é um reset.
module props (input clk);
  (* anyseq *) wire rst, wr, rd, scl, sda;
  (* anyseq *) wire [2:0] adr;
  (* anyseq *) wire [31:0] din;
  wire [31:0] dout;
  wire irq, scl_low, sda_low;
  wire dbg_ctrl_enable, dbg_irq_done_en, dbg_irq_err_en, dbg_st_done, dbg_st_nack, dbg_st_arb_lost, dbg_st_rejected;
  wire dbg_core_busy, dbg_core_active, dbg_core_done, dbg_core_nack, dbg_core_arb_lost;
  wire [15:0] dbg_divider;
  wire [7:0] dbg_tx_data, dbg_core_rx;

  i2c_master dut (.i_clk(clk), .i_rst(rst), .i_write(wr), .i_read(rd), .i_address(adr), .i_data_in(din),
    .o_data_out(dout), .o_irq(irq), .o_scl_low(scl_low), .o_sda_low(sda_low), .i_scl(scl), .i_sda(sda),
    .dbg_ctrl_enable(dbg_ctrl_enable), .dbg_irq_done_en(dbg_irq_done_en), .dbg_irq_err_en(dbg_irq_err_en),
    .dbg_divider(dbg_divider), .dbg_tx_data(dbg_tx_data), .dbg_st_done(dbg_st_done), .dbg_st_nack(dbg_st_nack),
    .dbg_st_arb_lost(dbg_st_arb_lost), .dbg_st_rejected(dbg_st_rejected), .dbg_core_busy(dbg_core_busy),
    .dbg_core_active(dbg_core_active), .dbg_core_done(dbg_core_done), .dbg_core_nack(dbg_core_nack),
    .dbg_core_arb_lost(dbg_core_arb_lost), .dbg_core_rx(dbg_core_rx));

  reg f_past = 0;
  reg m_en = 0, m_dn = 0, m_er = 0;
  reg [15:0] m_div = 16'd3;
  reg [7:0] m_tx = 0;
  reg m_sd = 0, m_sn = 0, m_sa = 0, m_sr = 0;
  // O reset, o aborto e o mestre ligado da borda anterior.
  reg p_rst = 0, p_abort = 0, p_en = 0;

  wire c_start = din[0], c_stop = din[1], c_read = din[2], c_write = din[3];
  wire cmd_ok = m_en && !dbg_core_busy && (c_start || c_stop || c_read || c_write) && !(c_read && c_write)
                && (c_start || dbg_core_active);
  wire cmd_wr = wr && adr == 3'd2;
  wire sta_wr = wr && adr == 3'd5;

  always @(posedge clk) begin
    f_past <= 1;
    p_rst <= rst;
    p_abort <= wr && adr == 3'd0 && din[3];
    p_en <= m_en;
    if (rst) begin
      m_en <= 0; m_dn <= 0; m_er <= 0; m_div <= 16'd3; m_tx <= 0;
      m_sd <= 0; m_sn <= 0; m_sa <= 0; m_sr <= 0;
    end else begin
      if (wr && adr == 3'd0) begin m_en <= din[0]; m_dn <= din[1]; m_er <= din[2]; end
      if (wr && adr == 3'd1) m_div <= (din[15:0] < 16'd2) ? 16'd2 : din[15:0];
      if (wr && adr == 3'd3) m_tx <= din[7:0];
      m_sd <= (m_sd && !(sta_wr && din[2])) || dbg_core_done;
      m_sn <= (m_sn && !(sta_wr && din[3])) || dbg_core_nack;
      m_sa <= (m_sa && !(sta_wr && din[4])) || dbg_core_arb_lost;
      m_sr <= (m_sr && !(sta_wr && din[5])) || (cmd_wr && !cmd_ok);
    end
  end

  always @* if (!f_past) assume (rst);

  always @(posedge clk) if (f_past) begin
    // 1. Os registradores e os bits sticky seguem o modelo, com o reset e a escrita em STATUS que limpa com 1.
    assert (dbg_ctrl_enable == m_en && dbg_irq_done_en == m_dn && dbg_irq_err_en == m_er);
    assert (dbg_divider == m_div && dbg_divider >= 16'd2);
    assert (dbg_tx_data == m_tx);
    assert (dbg_st_done == m_sd && dbg_st_nack == m_sn && dbg_st_arb_lost == m_sa && dbg_st_rejected == m_sr);
    // 2. A leitura devolve o registrador do endereço; sem leitura, e nos endereços livres, zero.
    if (!rd) assert (dout == 32'h0);
    else case (adr)
      3'd0: assert (dout == {29'h0, m_er, m_dn, m_en});
      3'd1: assert (dout == {16'h0, m_div});
      3'd3: assert (dout == {24'h0, m_tx});
      3'd4: assert (dout == {24'h0, dbg_core_rx});
      3'd5: assert (dout == {26'h0, m_sr, m_sa, m_sn, m_sd, dbg_core_active, dbg_core_busy || dbg_core_done});
      default: assert (dout == 32'h0);
    endcase
    // 3. A interrupção é de nível: fim de comando habilitado ou erro habilitado.
    assert (irq == ((m_sd && m_dn) || ((m_sn || m_sa || m_sr) && m_er)));
    // 4. Com o reset, o aborto ou o mestre desligado na borda anterior, as duas linhas estão soltas.
    if (p_rst || p_abort || !p_en) assert (!scl_low && !sda_low);
    // 5. O sinal de erro ou de fim só nasce de um comando: sem comando em curso, nenhum NACK novo.
    if (dbg_core_nack) assert (dbg_core_busy);
  end

`ifdef COVER
  always @(posedge clk) if (f_past) begin
    cover (cmd_wr && cmd_ok);
    cover (cmd_wr && !cmd_ok && m_sr == 0);
    cover (irq && m_sr && m_er);
    cover (rd && adr == 3'd5 && m_sr);
    cover (sta_wr && din[5] && m_sr);
  end
`endif

`ifdef COVER_DONE
  always @(posedge clk) if (f_past) begin
    cover (irq && m_sd && m_dn);
    cover (rd && adr == 3'd5 && m_sd && !dbg_core_busy);
  end
`endif
endmodule
