// Propriedades do lcd_regs, verificadas na netlist Verilog que o GHDL sintetiza do VHDL, contra um modelo de
// referência dos registradores. O barramento e o estado da fila, da camada física e da inicialização são entradas
// livres (a fila é provada à parte, em uart_fifo_props.sv). A fila tem DEPTH posições na prova (3, o nível cabe em
// dois bits). O primeiro clock é um reset, como na placa, e as propriedades valem a partir dele.
//   1. CONTROL guarda a habilitação da interrupção, a espera pelo ocupado (só com RW ligado), LCD_ON e LCD_BLON, e
//      volta ao valor de reset: espera ligada com RW, LCD_ON ligado, o resto desligado.
//   2. DELAY e DELAY_LONG só mudam por escrita no seu endereço e voltam ao valor de reset.
//   3. DROPPED sobe quando a fila recusa uma inserção pedida, TIMEOUT sobe com o pulso da camada física, e os dois
//      só descem por escrita de 1 no bit; um evento simultâneo com a limpeza vence.
//   4. A inserção é pedida só por escrita em COMMAND ou DATA, com RS = 1 só em DATA e o byte baixo do dado.
//   5. A interrupção é a fila vazia habilitada e fora da inicialização; a leitura de cada endereço devolve o
//      registrador do modelo (STATUS com o nível da fila, BUSY e as flags), e zero fora do mapa.
`ifndef DEPTH
`define DEPTH 3
`endif
`ifndef RESET_DELAY
`define RESET_DELAY 5
`endif
`ifndef RESET_DELAY_LONG
`define RESET_DELAY_LONG 9
`endif
module props (input clk);
  (* anyseq *) wire reset, write, push_acc, full, empty, phy_busy, init_busy, timeout;
  (* anyseq *) wire [2:0] addr;
  (* anyseq *) wire [31:0] wdata;
  (* anyseq *) wire [1:0] level;
  wire [31:0] rdata, delay, delay_long;
  wire irq, push, push_rs, poll, lcd_on, blon;
  wire [7:0] push_data;

  lcd_regs dut (.i_clk(clk), .i_rst(reset), .i_data_in(wdata), .i_address(addr), .i_write(write),
    .o_data_out(rdata), .o_irq(irq), .o_push(push), .o_push_rs(push_rs), .o_push_data(push_data),
    .i_push_accepted(push_acc), .i_fifo_full(full), .i_fifo_empty(empty), .i_fifo_level(level),
    .i_phy_busy(phy_busy), .i_init_busy(init_busy), .i_timeout(timeout), .o_poll_enable(poll),
    .o_delay(delay[23:0]), .o_delay_long(delay_long[23:0]), .o_lcd_on(lcd_on), .o_lcd_blon(blon));
  assign delay[31:24] = 0;
  assign delay_long[31:24] = 0;

  reg f_past = 0;
  initial assume (reset);
  always @(posedge clk) f_past <= 1;
  // A fila não está cheia e vazia ao mesmo tempo, e o nível acompanha as flags; sem isso o estado seria impossível.
  always @(*) begin
    assume (!(full && empty));
    assume (empty == (level == 0));
    assume (full == (level == `DEPTH));
  end

  // Modelo dos registradores.
  reg m_ie = 0, m_poll = 0, m_on = 1, m_bl = 0, m_drop = 0, m_to = 0;
  reg [23:0] m_dly = `RESET_DELAY, m_dlyl = `RESET_DELAY_LONG;
`ifdef NORW
  localparam POLL_RESET = 1'b0;
`else
  localparam POLL_RESET = 1'b1;
`endif
  wire wr_ctl = write && addr == 3'd3;
  wire wr_stat = write && addr == 3'd2;
  wire m_push = write && (addr == 3'd0 || addr == 3'd1);

  always @(posedge clk) begin
    if (reset) begin
      m_ie <= 0; m_poll <= POLL_RESET; m_on <= 1; m_bl <= 0; m_drop <= 0; m_to <= 0;
      m_dly <= `RESET_DELAY; m_dlyl <= `RESET_DELAY_LONG;
    end else begin
      if (wr_ctl) begin
        m_ie <= wdata[0];
`ifndef NORW
        m_poll <= wdata[1];
`endif
        m_on <= wdata[2];
        m_bl <= wdata[3];
      end
      if (write && addr == 3'd4) m_dly <= wdata[23:0];
      if (write && addr == 3'd5) m_dlyl <= wdata[23:0];
      m_drop <= (m_drop && !(wr_stat && wdata[4])) || (m_push && !push_acc);
      m_to <= (m_to && !(wr_stat && wdata[5])) || timeout;
    end
  end

  // Valor esperado da leitura de cada endereço.
  reg [31:0] want;
  always @(*) begin
    want = 0;
    case (addr)
      3'd2: want = {16'd0, 6'd0, level, 2'd0, m_to, m_drop, init_busy, empty, full,
                    phy_busy || init_busy || !empty};
      3'd3: want = {28'd0, m_bl, m_on, m_poll, m_ie};
      3'd4: want = {8'd0, m_dly};
      3'd5: want = {8'd0, m_dlyl};
      default: want = 0;
    endcase
  end

  always @(posedge clk) if (f_past) begin
    assert (poll == m_poll);
    assert (lcd_on == m_on);
    assert (blon == m_bl);
    assert (delay == {8'd0, m_dly});
    assert (delay_long == {8'd0, m_dlyl});
    assert (push == m_push);
    assert (push_rs == (addr == 3'd1));
    assert (push_data == wdata[7:0]);
    assert (irq == (m_ie && empty && !init_busy));
    assert (rdata == want);
`ifdef NORW
    assert (!poll);
`endif
  end

`ifdef COVER
  always @(posedge clk) if (f_past) begin
    cover (m_drop && !m_to && wr_stat);
    cover (m_to);
    cover (irq);
    cover (m_dly != `RESET_DELAY && m_poll != POLL_RESET);
    cover (m_drop && m_to);
  end
`endif
endmodule
