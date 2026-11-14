// Propriedades do audio (modo escravo, filas de 3 palavras), verificadas na netlist Verilog que o GHDL sintetiza do
// VHDL. O barramento e os pinos do codec são livres. A netlist expõe como saídas sinais internos (níveis das filas,
// eventos de erro, pulsos de inserção e remoção) para o modelo enunciar o contrato de cada registrador.
//   1. CONTROL, IRQ_LEVEL, LEVELS, CONFIG e CAPS leem de volta o que o contrato diz, e o reset leva tudo ao valor
//      inicial (nada habilitado, palavra de 24 bits, limiares 0 e 1).
//   2. Os níveis das filas só mudam por inserção aceita e remoção; uma escrita em TX_DATA é recusada exatamente
//      quando a fila está cheia sem remoção no mesmo ciclo, e a recusa marca TX_DROPPED.
//   3. Os três flags de STATUS sobem com seu evento (evento novo vence limpeza simultânea) e só caem por escrita de 1.
//   4. A interrupção é o OU dos três termos: nível da reprodução abaixo do limiar, nível da gravação no limiar e
//      erro pendente, cada um com seu habilitador.
//   5. Com a geração de clock desabilitada o clock mestre fica em '0', e no modo escravo BCLK e LRCK não são
//      dirigidos.
`ifndef DEPTH
`define DEPTH 3
`endif
module props (input clk);
  (* anyseq *) wire reset, write, read, bclk_in, adclrck_in, daclrck_in, adcdat_in;
  (* anyseq *) wire [3:0] addr;
  (* anyseq *) wire [31:0] wdata;
  wire [31:0] rdata;
  wire irq, xck, bclk_out, bclk_oe, adclrck_out, adclrck_oe, daclrck_out, daclrck_oe, dacdat;
  wire [1:0] d_tx_level, d_rx_level;
  wire d_push_ok, d_pop, d_underflow, d_rx_valid, d_rx_right, d_rx_space;

  audio dut (.i_clk(clk), .i_rst(reset), .i_write(write), .i_read(read), .i_address(addr), .i_data_in(wdata),
    .o_data_out(rdata), .o_irq(irq), .o_xck(xck), .i_bclk(bclk_in), .o_bclk(bclk_out), .o_bclk_oe(bclk_oe),
    .i_adclrck(adclrck_in), .o_adclrck(adclrck_out), .o_adclrck_oe(adclrck_oe), .i_daclrck(daclrck_in),
    .o_daclrck(daclrck_out), .o_daclrck_oe(daclrck_oe), .i_adcdat(adcdat_in), .o_dacdat(dacdat),
    .dbg_tx_level(d_tx_level), .dbg_rx_level(d_rx_level), .dbg_tx_push_ok(d_push_ok), .dbg_tx_pop(d_pop),
    .dbg_tx_underflow(d_underflow), .dbg_rx_valid(d_rx_valid), .dbg_rx_right(d_rx_right),
    .dbg_rx_space(d_rx_space));

  // Os registradores não têm valor inicial: o primeiro clock é um reset, como na placa.
  initial assume (reset);

  reg f_past = 0;
  reg [6:0] m_en = 0;
  reg [1:0] m_word = 2'd1;
  reg [15:0] m_tx_thr = 0, m_rx_thr = 16'd1;
  reg m_under = 0, m_over = 0, m_drop = 0;
  reg [1:0] m_txl = 0;
  reg en_clk_prev = 0;

  wire wr_ctrl   = write && addr == 4'd0;
  wire wr_status = write && addr == 4'd1;
  wire wr_tx     = write && addr == 4'd3;
  wire wr_irq    = write && addr == 4'd5;
  wire rd_rx     = read && addr == 4'd4;
  wire ev_drop   = wr_tx && !d_push_ok;
  wire ev_over   = d_rx_valid && !d_rx_right && !d_rx_space;
  wire [1:0] m_txl_next = reset ? 2'd0 : m_txl + {1'b0, d_push_ok && wr_tx} - {1'b0, d_pop && m_txl != 2'd0};

  always @(posedge clk) begin
    f_past <= 1;
    en_clk_prev <= m_en[5];
    m_en     <= reset ? 7'd0 : (wr_ctrl ? wdata[6:0] : m_en);
    m_word   <= reset ? 2'd1 : (wr_ctrl ? wdata[9:8] : m_word);
    m_tx_thr <= reset ? 16'd0 : (wr_irq ? wdata[15:0] : m_tx_thr);
    m_rx_thr <= reset ? 16'd1 : (wr_irq ? wdata[31:16] : m_rx_thr);
    m_under  <= reset ? 1'b0 : (d_underflow ? 1'b1 : ((wr_status && wdata[4]) ? 1'b0 : m_under));
    m_over   <= reset ? 1'b0 : (ev_over ? 1'b1 : ((wr_status && wdata[5]) ? 1'b0 : m_over));
    m_drop   <= reset ? 1'b0 : (ev_drop ? 1'b1 : ((wr_status && wdata[6]) ? 1'b0 : m_drop));
    m_txl    <= m_txl_next;
  end

  always @(posedge clk) if (f_past) assume (!reset);

  wire m_txie = m_en[2], m_rxie = m_en[3], m_errie = m_en[4];

  always @(posedge clk) if (f_past) begin
    // 1. Os registradores de configuração leem de volta o que foi escrito.
    if (addr == 4'd0) assert (rdata == {22'd0, m_word, 1'b0, m_en});
    if (addr == 4'd5) assert (rdata == {m_rx_thr, m_tx_thr});
    if (addr == 4'd2) assert (rdata == {14'd0, d_rx_level, 14'd0, d_tx_level});
    if (addr == 4'd12) assert (rdata == {16'(`DEPTH), 16'(`DEPTH)});
    if (addr == 4'd13) assert (rdata == 32'd2);
    // 2. O nível da fila de reprodução segue as inserções aceitas e as remoções, e a recusa só ocorre cheia.
    assert (d_tx_level == m_txl);
    assert (d_tx_level <= `DEPTH);
    assert (d_rx_level <= `DEPTH);
    if (wr_tx) assert (d_push_ok == (m_txl != `DEPTH || d_pop));
    // 3. Os flags de STATUS seguem seus eventos.
    if (addr == 4'd1) begin
      assert (rdata[4] == m_under);
      assert (rdata[5] == m_over);
      assert (rdata[6] == m_drop);
      assert (rdata[0] == (m_txl != `DEPTH));
      assert (rdata[2] == (m_txl == 0));
    end
    // 4. A interrupção é o OU dos três termos, cada um com seu habilitador.
    assert (irq == ((m_txie && {14'd0, d_tx_level} <= m_tx_thr) || (m_rxie && {14'd0, d_rx_level} >= m_rx_thr)
      || (m_errie && (m_under || m_over || m_drop))));
    // 5. Sem clock habilitado o mestre para, e no modo escravo BCLK e LRCK são só entradas.
    if (!en_clk_prev && !m_en[5]) assert (!xck);
    assert (!bclk_oe && !adclrck_oe && !daclrck_oe);
  end

`ifdef COVER
  always @(posedge clk) if (f_past) begin
    cover (m_drop);
    cover (m_txl == `DEPTH);
    cover (m_under);
    cover (m_txie && irq);
    cover (d_pop);
  end
`endif
endmodule
