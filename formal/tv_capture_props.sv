// Propriedades do tv_capture, verificadas na netlist Verilog que o GHDL sintetiza do VHDL (fb 3x2, origem 8x6),
// com os eventos do receptor BT.656 como entradas livres, sujeitos só ao que o receptor garante: o início de campo
// é um início de linha, o fim de campo, o início de linha e um pixel não coincidem, e a configuração fica parada
// durante a captura. O protocolo da captura de um quadro:
//   1. Só há captura (ocupado) depois de um pedido, e ela termina com um único pulso de fim e fica parada.
//   2. O resultado é de quadro completo só se, desde o pedido, o campo pedido começou e acabou; com os dois
//      campos, o primeiro e depois o segundo, nessa ordem.
//   3. Um pixel só é aceito durante a captura, só um ciclo depois de um pixel do receptor, e o índice dele cabe na
//      memória (menor que fb_width * fb_height, com uma memória que não é potência de dois).
//   4. O reset para a captura sem pulso de fim e sem pixel.
`ifndef FSEL
`define FSEL 0
`endif
module props (input clk);
  localparam N = 6;
  (* anyseq *) wire reset, start, line_start, field_start, field_end, field, present, pix;
  (* anyseq *) wire [7:0] y, cb, cr;
  wire busy, done, ok, we, fmt_o;
  wire [2:0] index;
  wire [7:0] oy, ocb, ocr;
  wire [1:0] fsel = `FSEL;
  wire [7:0] xdiv, ydiv;
  (* anyseq *) wire [1:0] xdiv_s, ydiv_s;
  assign xdiv = {6'b0, xdiv_s};
  assign ydiv = {6'b0, ydiv_s};

  tv_capture dut (.i_clk(clk), .i_rst(reset), .i_start(start), .i_x_div(xdiv), .i_y_div(ydiv),
    .i_field_sel(fsel), .i_format(1'b0), .i_line_start(line_start), .i_field_start(field_start),
    .i_field_end(field_end), .i_field(field), .i_present(present), .i_pix_valid(pix), .i_y(y), .i_cb(cb),
    .i_cr(cr), .o_busy(busy), .o_done(done), .o_ok(ok), .o_we(we), .o_index(index), .o_format(fmt_o),
    .o_y(oy), .o_cb(ocb), .o_cr(ocr));

  initial assume (reset);
  reg f_past = 0;
  always @(posedge clk) f_past <= 1;

  // O que o receptor garante.
  always @(*) begin
    assume (!field_start || line_start);
    assume (!(field_end && (line_start || pix)));
    assume (!(line_start && pix));
  end

  // Modelo do protocolo: o que foi visto desde o pedido.
  reg m_armed = 0, m_s0 = 0, m_e0 = 0, m_s1 = 0, m_e1 = 0, p_pix = 0, p_busy = 0, p_done = 0, p_rst = 0;
  wire both = (`FSEL == 0) || (`FSEL == 3);
  wire want = both ? 1'b0 : (`FSEL == 2);
  always @(posedge clk) begin
    p_pix <= pix; p_busy <= busy; p_done <= done; p_rst <= reset;
    if (done) m_armed <= 0;
    if (start && !busy) begin m_armed <= 1; m_s0 <= 0; m_e0 <= 0; m_s1 <= 0; m_e1 <= 0; end
    if (m_armed) begin
      if (field_start && field == want && !m_s0) m_s0 <= 1;
      if (field_end && m_s0 && field == want && !m_e0) m_e0 <= 1;
      if (both && field_start && m_e0 && field == 1'b1) m_s1 <= 1;
      if (both && field_end && m_s1 && field == 1'b1) m_e1 <= 1;
    end
    if (reset) begin m_armed <= 0; m_s0 <= 0; m_e0 <= 0; m_s1 <= 0; m_e1 <= 0; end
  end

  // Configuração parada durante a captura.
  reg [1:0] hx, hy;
  always @(posedge clk) begin hx <= xdiv_s; hy <= ydiv_s; end
  always @(*) if (f_past && busy && !done) begin assume (hx == xdiv_s); assume (hy == ydiv_s); end

  always @(posedge clk) if (f_past) begin
    // Fim sem captura, ou repetido, não existe.
    if (done) assert (p_busy && !busy && !p_done);
    // Quadro completo só com a sequência de campos pedida.
    if (done && ok) assert (both ? m_e1 : m_e0);
    // Pixel só na captura e um ciclo depois de um pixel do receptor.
    if (we) assert (p_pix && (busy || done));
    if (we) assert (index < N);
    if (p_rst) assert (!busy && !we && !done);
  end

`ifdef COVER
  always @(posedge clk) if (f_past) begin
    cover (done && ok);
    cover (we && busy);
    cover (done && !ok);
  end
`endif
endmodule
