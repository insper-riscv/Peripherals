// Propriedades da ponte USB (usb_bridge), verificadas na netlist Verilog que o GHDL sintetiza do VHDL. O barramento
// do SoC e os pinos do chip são entradas livres. Um modelo de referência segue o registrador de controle, a máscara,
// o erro pegajoso e a sincronização das interrupções e do pedido de DMA. O ocupado do mestre é lido do sinal
// exposto dbg_busy. O primeiro clock é um reset e nenhum outro clock o é.
module props (input clk);
  (* anyseq *) wire rst, wr, rd, dreq;
  (* anyseq *) wire [3:0] adr;
  (* anyseq *) wire [31:0] din;
  (* anyseq *) wire [15:0] chip_in;
  (* anyseq *) wire [1:0] intr;
  wire [31:0] dout;
  wire irq, cs_n, rd_n, wr_n, rst_n, oe, dack, busy;
  wire [1:0] oaddr;
  wire [15:0] odata;

  usb_bridge dut (.i_clk(clk), .i_rst(rst), .i_data_in(din), .i_address(adr), .i_write(wr), .i_read(rd),
    .o_data_out(dout), .o_irq(irq), .o_otg_cs_n(cs_n), .o_otg_rd_n(rd_n), .o_otg_wr_n(wr_n), .o_otg_rst_n(rst_n),
    .o_otg_addr(oaddr), .o_otg_data(odata), .o_otg_data_oe(oe), .i_otg_data(chip_in), .i_otg_int(intr),
    .i_otg_dreq(dreq), .o_otg_dack(dack), .dbg_busy(busy));

  reg f_past = 0;
  reg m_reset = 0, m_dack = 0, m_err = 0;
  reg [1:0] m_mask = 0, m_i1 = 0, m_i2 = 0;
  reg m_d1 = 0, m_d2 = 0;
  reg p_cs_n = 1, p_rd_n = 1, p_wr_n = 1;
  reg [1:0] p_addr = 0;
  reg [15:0] p_data = 0;
  wire req = (wr || rd) && adr < 4'd4;

  always @(posedge clk) begin
    f_past <= 1;
    p_cs_n <= cs_n;
    p_rd_n <= rd_n;
    p_wr_n <= wr_n;
    p_addr <= oaddr;
    p_data <= odata;
    m_i1 <= rst ? 2'b00 : intr;
    m_i2 <= rst ? 2'b00 : m_i1;
    m_d1 <= rst ? 1'b0 : dreq;
    m_d2 <= rst ? 1'b0 : m_d1;
    if (rst) begin
      m_reset <= 1;
      m_dack <= 0;
      m_err <= 0;
      m_mask <= 0;
    end else begin
      if (wr && adr == 4'd5) begin
        m_reset <= din[0];
        m_dack <= din[1];
      end
      if (wr && adr == 4'd7) m_mask <= din[1:0];
      if (wr && adr == 4'd6 && din[4]) m_err <= 0;
      if (req && busy) m_err <= 1;
    end
  end

  // ---- o ambiente ----
  always @* if (!f_past) assume (rst);
  always @* if (f_past) assume (!rst);

  always @(posedge clk) if (f_past) begin
    // 1. O pino de reset do chip e o reconhecimento de DMA seguem o controle.
    assert (rst_n == !m_reset);
    assert (dack == m_dack);
    // 2. Sem leitura a saída é zero; com leitura, controle, máscara e estado seguem o modelo.
    if (!rd) assert (dout == 32'h0);
    else case (adr)
      4'd5: assert (dout == {30'h0, m_dack, m_reset});
      4'd7: assert (dout == {30'h0, m_mask});
      4'd6: assert (dout == {27'h0, m_err, busy, m_d2, m_i2});
      4'd0, 4'd1, 4'd2, 4'd3: assert (dout == 32'h0);
      default: ;
    endcase
    // 3. A interrupção é de nível: algum nível sincronizado e habilitado.
    assert (irq == ((m_i2 & m_mask) != 2'b00));
    // 4. Segurança do barramento do chip: estrobos nunca juntos nem sem o chip selecionado, a saída de dado só
    //    fora da leitura e nunca sem selecionar o chip, e o chip selecionado só com a ponte ocupada.
    assert (rd_n || wr_n);
    if (cs_n) assert (rd_n && wr_n && !oe);
    assert (!(oe && !rd_n));
    if (!wr_n) assert (oe);
    if (!cs_n) assert (busy);
    // 5. Há ciclo de preparação: o estrobo nunca sobe no ciclo em que o chip é selecionado; e, durante o estrobo,
    //    o endereço e o dado de escrita ficam estáveis.
    if (p_cs_n) assert (rd_n && wr_n);
    if (!rd_n || !wr_n) assert (oaddr == p_addr);
    if (!wr_n && !p_wr_n) assert (odata == p_data);
  end

`ifdef COVER
  always @(posedge clk) if (f_past) begin
    cover (!cs_n && !wr_n && oe);
    cover (!cs_n && !rd_n);
    cover (irq && m_i2[0] && m_mask[0]);
    cover (irq && m_i2[1] && m_mask[1]);
    cover (rd && adr == 4'd6 && m_err);
    cover (rst_n && dack);
  end
`endif
endmodule
