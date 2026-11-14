// Propriedades do eth_regs, verificadas na netlist Verilog que o GHDL sintetiza do VHDL, com buffers de 4
// palavras. Um modelo ideal guarda o registrador de controle, a habilitação e as pendências de interrupção, o
// endereço MAC, o comprimento de envio, o ponteiro do buffer de envio e a ocupação do transmissor. Seja qual for a
// sequência de acessos e de eventos:
//   1. Os registradores guardados são os do modelo, inclusive o valor de reset (indução).
//   2. A interrupção vale exatamente (pendência E habilitação) em algum bit, e uma pendência só sobe por evento.
//   3. O pulso de início de envio sai um ciclo depois do comando aceito, e só com o transmissor livre e o
//      comprimento diferente de zero; um comando recusado vira erro e nunca pulso.
//   4. Os endereços lidos devolvem o que o modelo guarda, e o que não é registrador lê zero.
module props (input clk);
  localparam [5:0] A_CTRL = 6'd0, A_STATUS = 6'd1, A_IRQ = 6'd2, A_IRQEN = 6'd3, A_MAC_LO = 6'd4, A_MAC_HI = 6'd5,
                   A_TX_LEN = 6'd6, A_TX_CMD = 6'd7, A_TX_DATA = 6'd8;
  (* anyseq *) wire reset, write, read;
  (* anyseq *) wire [5:0] addr;
  (* anyseq *) wire [31:0] data, rx_ram_data;
  (* anyseq *) wire tx_done, mdio_busy, mdio_done, no_ack, phy_int, ev_frame, ev_crc, ev_phy, ev_dropped, ev_filtered;
  (* anyseq *) wire rx_ready;
  (* anyseq *) wire [4:0] rx_len;
  (* anyseq *) wire [15:0] mdio_rdata;
  wire [31:0] dout;
  wire irq, enable, promisc, bcast, mcast, accept_err, phy_reset, soft_reset, tx_we, tx_start, rx_release;
  wire mdio_start, mdio_write;
  wire [47:0] mac;
  wire [1:0] tx_addr, rx_addr;
  wire [31:0] tx_data;
  wire [4:0] tx_len;
  wire [4:0] m_phy, m_reg;
  wire [15:0] m_wdata;
  wire [6:0] dbg_ctrl;
  wire [4:0] dbg_irq_enable;
  wire [3:0] dbg_irq_pending;
  wire [47:0] dbg_mac_addr;
  wire [4:0] dbg_tx_len;
  wire [2:0] dbg_tx_ptr;
  wire dbg_tx_busy;

  eth_regs dut (.i_clk(clk), .i_rst(reset), .i_write(write),
    .i_read(read), .i_address(addr), .i_data_in(data), .o_data_out(dout), .o_irq(irq), .o_enable(enable),
    .o_promiscuous(promisc), .o_broadcast(bcast), .o_multicast(mcast), .o_accept_errors(accept_err),
    .o_phy_reset(phy_reset), .o_soft_reset(soft_reset), .o_mac_addr(mac), .o_tx_ram_we(tx_we),
    .o_tx_ram_addr(tx_addr), .o_tx_ram_data(tx_data), .o_tx_len(tx_len), .o_tx_start(tx_start),
    .i_tx_done(tx_done), .i_rx_ready(rx_ready), .i_rx_len(rx_len), .i_rx_ram_data(rx_ram_data),
    .o_rx_ram_addr(rx_addr), .o_rx_release(rx_release), .o_mdio_start(mdio_start), .o_mdio_write(mdio_write),
    .o_mdio_phy_addr(m_phy), .o_mdio_reg_addr(m_reg), .o_mdio_wdata(m_wdata), .i_mdio_busy(mdio_busy),
    .i_mdio_done(mdio_done), .i_mdio_rdata(mdio_rdata), .i_mdio_no_ack(no_ack), .i_phy_int(phy_int),
    .i_ev_frame(ev_frame), .i_ev_crc(ev_crc), .i_ev_phy(ev_phy), .i_ev_dropped(ev_dropped),
    .i_ev_filtered(ev_filtered), .dbg_ctrl(dbg_ctrl), .dbg_irq_enable(dbg_irq_enable),
    .dbg_irq_pending(dbg_irq_pending), .dbg_mac_addr(dbg_mac_addr), .dbg_tx_len(dbg_tx_len),
    .dbg_tx_ptr(dbg_tx_ptr), .dbg_tx_busy(dbg_tx_busy));

  // Os registradores têm o valor inicial do VHDL, o mesmo do modelo, e a prova vale de qualquer estado alcançável.
  reg [6:0] m_ctrl = 7'b0000100;
  reg [4:0] m_irqen = 0;
  reg [3:0] m_pend = 0;
  reg [47:0] m_mac = 0;
  reg [4:0] m_len = 0;
  reg [2:0] m_ptr = 0;
  reg m_busy = 0, m_start = 0;

  wire w_ctrl = write && addr == A_CTRL;
  wire w_irq = write && addr == A_IRQ;
  wire w_irqen = write && addr == A_IRQEN;
  wire w_mac_lo = write && addr == A_MAC_LO;
  wire w_mac_hi = write && addr == A_MAC_HI;
  wire w_len = write && addr == A_TX_LEN;
  wire w_cmd = write && addr == A_TX_CMD;
  wire w_data = write && addr == A_TX_DATA;
  wire go = w_cmd && data[0] && !m_busy && m_len != 0;
  wire tx_error = (w_cmd && data[0] && m_busy) || (w_cmd && data[0] && m_len == 0) || (w_data && m_ptr == 4);
  wire err_event = ev_crc || ev_phy || ev_dropped || tx_error;
  wire data_ok = w_data && !m_busy && m_ptr < 4;
  wire ptr_reset = w_cmd && data[1] && !m_busy;

  reg [3:0] pend_next;
  integer k;
  always @* begin
    pend_next = m_pend;
    for (k = 0; k < 4; k = k + 1) if (w_irq && data[k]) pend_next[k] = 1'b0;
    if (ev_frame) pend_next[0] = 1'b1;
    if (tx_done) pend_next[1] = 1'b1;
    if (err_event) pend_next[2] = 1'b1;
    if (mdio_done) pend_next[3] = 1'b1;
  end

  always @(posedge clk) begin
    m_ctrl <= reset ? 7'b0000100 : (w_ctrl ? data[6:0] : m_ctrl);
    m_irqen <= reset ? 5'd0 : (w_irqen ? data[4:0] : m_irqen);
    m_pend <= reset ? 4'd0 : pend_next;
    m_mac[31:0] <= reset ? 32'd0 : (w_mac_lo ? data : m_mac[31:0]);
    m_mac[47:32] <= reset ? 16'd0 : (w_mac_hi ? data[15:0] : m_mac[47:32]);
    m_len <= reset ? 5'd0 : ((w_len && !m_busy) ? data[4:0] : m_len);
    m_ptr <= reset ? 3'd0 : (tx_done ? 3'd0 : (ptr_reset ? 3'd0 : (data_ok ? m_ptr + 3'd1 : m_ptr)));
    m_busy <= reset ? 1'b0 : (tx_done ? 1'b0 : (go ? 1'b1 : m_busy));
    m_start <= reset ? 1'b0 : go;
  end

  wire [4:0] irq_hit = {m_pend, phy_int} & {m_irqen[3:0], m_irqen[4]};

  always @(posedge clk) begin
    assert (dbg_ctrl == m_ctrl);
    assert (dbg_irq_enable == m_irqen);
    assert (dbg_irq_pending == m_pend);
    assert (dbg_mac_addr == m_mac);
    assert (dbg_tx_len == m_len);
    assert (dbg_tx_ptr == m_ptr);
    assert (dbg_tx_busy == m_busy);
    assert (tx_start == m_start);
    assert (irq == (irq_hit != 0));
    assert (!tx_start || !$past(m_busy));
    assert (enable == m_ctrl[0] && promisc == m_ctrl[1] && bcast == m_ctrl[2] && mcast == m_ctrl[3]);
    assert (accept_err == m_ctrl[4] && phy_reset == m_ctrl[6]);
    assert (!tx_start || $past(m_len) != 0);
    assert (mac == m_mac);
    assert (addr != A_CTRL || dout == {25'd0, m_ctrl});
    assert (addr != A_IRQEN || dout == {27'd0, m_irqen});
    assert (addr != A_MAC_LO || dout == m_mac[31:0]);
    assert (addr != A_MAC_HI || dout == {16'd0, m_mac[47:32]});
    assert (addr != A_IRQ || dout == {27'd0, phy_int, m_pend});
    assert (addr != A_TX_LEN || dout == {27'd0, m_len});
    assert (!(addr == 6'd14 || addr == 6'd15 || addr >= 6'd22) || dout == 32'd0);
  end

`ifdef COVER
  always @(posedge clk) begin
    cover (irq);
    cover (tx_start);
    cover (m_busy && tx_error);
  end
`endif
endmodule
