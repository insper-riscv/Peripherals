// Propriedades do tv_regs, verificadas na netlist Verilog que o GHDL sintetiza do VHDL, com uma memória de 3
// palavras (fb_width = 3, fb_height = 2). Um modelo de referência, escrito a partir do mapa de registradores e
// não do VHDL, guarda o controle, o estado, o contador de quadros, a decimação, o formato, o campo, o ponteiro de
// leitura e os toggles do pedido de captura. Seja qual for a sequência de acessos, de toggles de fim de captura
// e de erro e de resultados que o outro domínio produza, as saídas e a leitura de cada endereço são as do modelo.
//   1. O pedido de captura só inverte o toggle com START escrito e a captura parada, e deixa o estado ocupado.
//   2. A configuração (decimação, formato e campo) só muda com a captura parada, e nenhum fator vale zero.
//   3. O quadro pronto e o contador só avançam num fim de captura com resultado completo, e o erro de sincronismo
//      sobe num erro do receptor ou numa captura abortada; as escritas de 1 limpam o quadro pronto e o erro.
//   4. O ponteiro de leitura nunca sai da memória, e o reset zera todos os registradores.
module props (input clk);
  localparam DEPTH = 3;
  (* anyseq *) wire reset, write, read, present, done_tog, cap_ok, err_tog;
  (* anyseq *) wire [3:0] addr;
  (* anyseq *) wire [31:0] data, rd_data;
  wire [31:0] dout;
  wire irq, start_tog, run, fmt;
  wire [7:0] x_div, y_div;
  wire [1:0] field_sel, rd_addr;

  tv_regs dut (.i_clk(clk), .i_rst(reset), .i_write(write), .i_read(read), .i_address(addr), .i_data_in(data),
    .o_data_out(dout), .o_irq(irq), .i_present(present), .i_done_tog(done_tog), .i_cap_ok(cap_ok),
    .i_err_tog(err_tog), .o_start_tog(start_tog), .o_x_div(x_div), .o_y_div(y_div), .o_field_sel(field_sel),
    .o_format(fmt), .o_decoder_run(run), .o_rd_addr(rd_addr), .i_rd_data(rd_data));

  // Os registradores não têm valor inicial: o primeiro clock é um reset, como na placa.
  initial assume (reset);

  reg f_past = 0;
  reg m_busy = 0, m_ready = 0, m_error = 0, m_firq = 0, m_eirq = 0, m_run = 0, m_fmt = 0, m_tog = 0;
  reg m_dseen = 0, m_eseen = 0;
  reg [31:0] m_count = 0;
  reg [7:0] m_x = 1, m_y = 1;
  reg [1:0] m_fsel = 0, m_ptr = 0;

  wire done_ev = m_busy && (done_tog != m_dseen);
  wire err_ev = (err_tog != m_eseen);
  wire is_wr = write && addr == 4'd0;
  wire start_ok = is_wr && data[0] && !m_busy;
  wire w_ptr = write && addr == 4'd6 && data < DEPTH;
  wire r_dat = read && addr == 4'd7;
  wire [1:0] ptr_next = w_ptr ? data[1:0] : (r_dat ? (m_ptr == DEPTH - 1 ? 2'd0 : m_ptr + 2'd1) : m_ptr);

  always @(posedge clk) begin
    f_past <= 1;
    m_dseen <= done_tog;
    m_eseen <= err_tog;
    m_ptr <= reset ? 2'd0 : ptr_next;
    if (err_ev) m_error <= 1;
    if (done_ev) begin
      m_busy <= 0;
      m_ready <= cap_ok;
      m_error <= m_error || !cap_ok || err_ev;
      if (cap_ok) m_count <= m_count + 1;
    end
    if (is_wr) begin
      m_firq <= data[1];
      m_eirq <= data[2];
      m_run <= data[3];
      if (start_ok) begin
        m_tog <= !m_tog;
        m_busy <= 1;
        m_ready <= 0;
      end
    end
    if (write && addr == 4'd1) begin
      if (data[1] && !done_ev) m_ready <= 0;
      if (data[2] && !err_ev && !done_ev) m_error <= 0;
    end
    if (write && addr == 4'd3 && !m_busy) begin
      m_x <= data[7:0] == 0 ? 8'd1 : data[7:0];
      m_y <= data[15:8] == 0 ? 8'd1 : data[15:8];
    end
    if (write && addr == 4'd4 && !m_busy) begin
      m_fmt <= data[0];
      m_fsel <= data[2:1];
    end
    if (reset) begin
      m_busy <= 0; m_ready <= 0; m_error <= 0; m_count <= 0; m_firq <= 0; m_eirq <= 0; m_run <= 0;
      m_x <= 1; m_y <= 1; m_fmt <= 0; m_fsel <= 0;
    end
  end

  reg [31:0] expect_dout;
  always @(*) begin
    case (addr)
      4'd0: expect_dout = {28'b0, m_run, m_eirq, m_firq, 1'b0};
      4'd1: expect_dout = {28'b0, present, m_error, m_ready, m_busy};
      4'd2: expect_dout = m_count;
      4'd3: expect_dout = {16'b0, m_y, m_x};
      4'd4: expect_dout = {29'b0, m_fsel, m_fmt};
      4'd5: expect_dout = {16'd2, 16'd3};
      4'd6: expect_dout = {30'b0, m_ptr};
      4'd7: expect_dout = rd_data;
      4'd8: expect_dout = {16'd480, 16'd720};
      default: expect_dout = 32'b0;
    endcase
  end

  // O toggle de pedido não é zerado pelo reset (o outro domínio guarda o último valor); começa igual ao do modelo.
  always @(*) if (!f_past) assume (start_tog == m_tog);

  always @(*) if (f_past) begin
    assert (dout == expect_dout);
    assert (irq == ((m_firq && m_ready) || (m_eirq && m_error)));
    assert (start_tog == m_tog);
    assert (x_div == m_x && y_div == m_y && x_div != 0 && y_div != 0);
    assert (fmt == m_fmt && field_sel == m_fsel);
    assert (run == m_run);
    assert (rd_addr == ptr_next);
    assert (rd_addr < DEPTH);
  end

  // Depois de um reset, tudo está no estado inicial.
  reg p_rst = 0;
  always @(posedge clk) p_rst <= reset;
  always @(*) if (f_past && p_rst) begin
    assert (!m_busy && !m_ready && !m_error && m_count == 0 && m_ptr == 0);
    assert (!irq && !run && x_div == 1 && y_div == 1);
  end

`ifdef COVER
  always @(posedge clk) if (f_past && !reset) begin
    cover (done_ev && cap_ok && m_busy);
    cover (done_ev && !cap_ok);
    cover (m_count == 2 && irq);
    cover (start_ok && m_ready);
  end
`endif
endmodule
