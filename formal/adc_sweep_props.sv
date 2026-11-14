// Propriedades do adc_sweep (varredura dos oito canais e registradores), verificadas na netlist Verilog que o GHDL
// sintetiza do VHDL. O lado do quadro e livre, com a unica premissa de que o chip so conclui um quadro pedido (o
// pulso de conclusao so vem depois do pedido e uma vez por pedido). O primeiro clock e um reset. LAT e o atraso de
// canal do generic channel_latency (0 ou 1).
//   SWEEP  O canal pedido e o numero do quadro dentro da varredura, a varredura tem 8 + LAT quadros e so recomeca
//          com ENABLE; o resultado de um quadro vai ao canal quadro - LAT; BUSY, SWEEP_DONE, VALID, CONTROL e
//          DIVIDER leem o que as escritas e os quadros determinam, e a interrupcao e SWEEP_DONE com IRQ_ENABLE.
`ifndef LAT
`define LAT 1
`endif
`ifndef RESET_DIVIDER
`define RESET_DIVIDER 3
`endif
module props (input clk);
  (* anyseq *) wire rst, we, frame_done;
  (* anyseq *) wire [3:0] adr;
  (* anyseq *) wire [31:0] wdata;
  (* anyseq *) wire [11:0] fdata;
  wire [31:0] rdata;
  wire irq, frame_start;
  wire [2:0] frame_ch;
  wire [15:0] divider;

  adc_sweep dut (.i_clk(clk), .i_rst(rst), .i_data_in(wdata), .i_address(adr), .i_write(we), .o_data_out(rdata),
    .o_irq(irq), .o_frame_start(frame_start), .o_frame_channel(frame_ch), .i_frame_done(frame_done),
    .i_frame_data(fdata), .o_divider(divider));

  reg f_past = 0;
  reg m_wait = 0, m_en = 0, m_irq_en = 0, m_done = 0, m_valid = 0;
  reg [15:0] m_div = `RESET_DIVIDER;
  reg [3:0] m_frame = 0;
  reg [11:0] m_ch [0:7];
  reg p_busy = 0, p_start_write = 0, p_en = 0, p_rst = 0, p_last = 0;
  integer j;
  initial for (j = 0; j < 8; j = j + 1) m_ch[j] = 0;

  wire busy_now = frame_start || m_wait;
  wire last_frame = (m_frame == 4'd7 + `LAT);

  always @* if (!f_past) assume (rst);
  // O chip so conclui um quadro pedido, depois do ciclo do pedido.
  always @* assume (!frame_done || (m_wait && !frame_start));

  always @(posedge clk) begin
    f_past <= 1;
    p_rst <= rst;
    p_busy <= busy_now;
    p_en <= m_en;
    p_start_write <= we && adr == 4'd8 && wdata[2];
    p_last <= frame_done && last_frame;
    if (rst) begin
      m_wait <= 0; m_en <= 0; m_irq_en <= 0; m_done <= 0; m_valid <= 0; m_frame <= 0;
      m_div <= `RESET_DIVIDER;
      for (j = 0; j < 8; j = j + 1) m_ch[j] <= 0;
    end else begin
      if (frame_start) m_wait <= 1;
      if (frame_done) begin
        m_wait <= 0;
        if (m_frame >= `LAT) m_ch[m_frame - `LAT] <= fdata;
        if (last_frame) begin m_frame <= 0; m_done <= 1; m_valid <= 1; end
        else m_frame <= m_frame + 1;
      end
      if (we && adr == 4'd8) begin m_en <= wdata[0]; m_irq_en <= wdata[1]; end
      if (we && adr == 4'd10) m_div <= wdata[15:0];
      if (we && adr == 4'd9 && !(frame_done && last_frame)) m_done <= m_done && !wdata[1];
    end
  end

  always @(posedge clk) if (f_past && !p_rst) begin
    // 1. Os pedidos de quadro nao se sobrepoem e pedem o canal igual ao numero do quadro.
    if (frame_start) assert (!m_wait && frame_ch == m_frame[2:0] && m_frame <= 4'd7 + `LAT);
    // 2. Um quadro novo depois de repouso so nasce de ENABLE ou de uma escrita de START no ciclo anterior.
    if (frame_start && !p_busy) assert (p_en || p_start_write);
    // 3. Depois do ultimo quadro a varredura recomeca so com ENABLE ligado, e para sem ele.
    if (p_last) assert (frame_start == p_en);
    // 4. Os registradores leem o que as escritas e os quadros determinam.
    if (adr < 4'd8) assert (rdata == {20'b0, m_ch[adr[2:0]]});
    if (adr == 4'd8) assert (rdata == {30'b0, m_irq_en, m_en});
    if (adr == 4'd9) assert (rdata == {29'b0, m_valid, m_done, busy_now});
    if (adr == 4'd10) assert (rdata == {16'b0, m_div});
    if (adr > 4'd10) assert (rdata == 32'b0);
    assert (divider == m_div);
    // 5. A interrupcao e SWEEP_DONE com IRQ_ENABLE.
    assert (irq == (m_irq_en && m_done));
  end

`ifdef COVER
  always @(posedge clk) if (f_past) begin
    cover (m_done && last_frame == 0 && m_valid && m_en);
    cover (irq);
    cover (p_last && p_en && frame_start);
    cover (m_valid && !m_en && !busy_now);
  end
`endif
endmodule
