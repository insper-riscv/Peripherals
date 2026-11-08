// Propriedades do gpio_cell, verificadas na netlist Verilog que o GHDL sintetiza do VHDL. O pino bidirecional
// da netlist é aberto em duas portas (i_pin, o que o pino vale, e o_pin_drv, o que a célula dirige), o que não
// muda a lógica. O ambiente dirige o pino (ext) só quando a direção é de entrada; como saída, o pino vale o
// registrador de saída. Com -DACTIVE_LOW (generic active_low verdadeiro) o pino vale o oposto do que o programa vê: o
// pino sentido é o inverso do pino da netlist e a célula dirige o inverso do registrador de saída. As oito saídas de o_data_out são: 0 direção, 1 saída, 2 entrada sincronizada do pino,
// 3 máscara de interrupção, 4 máscara de subida, 5 máscara de descida, 6 status, 7 modo de nível.
module props (input clk);
  (* anyseq *) wire reset, ext, d;
  (* anyseq *) wire [7:0] ws;
  (* anyseq *) wire [1:0] op;
  wire [7:0] q;
  wire drv;
  wire pin = q[0] ? drv : ext;
  // O que o programa vê no pino e o que o ambiente externo vale na polaridade do programa.
`ifdef ACTIVE_LOW
  wire lpin = !pin;
  wire lext = !ext;
`else
  wire lpin = pin;
  wire lext = ext;
`endif

  gpio_cell dut (.i_clk(clk), .i_rst(reset), .i_data_in(d), .o_data_out(q), .i_wr_signals(ws), .i_wr_op(op),
    .i_pin(pin), .o_pin_drv(drv));

  // Os registradores não têm valor inicial: o primeiro clock é um reset, como na placa.
  initial assume (reset);

  reg f_past = 0;
  reg m_dir = 0, m_out = 0, m_mask = 0, m_rise = 0, m_fall = 0, m_stat = 0, m_level = 0;
  // A cadeia do sincronizador do pino e o valor anterior da entrada sincronizada.
  reg h1 = 0, h2 = 0, prev = 0;
  // Ciclos seguidos com a saída ligada e o registrador de saída parado (satura em 3).
  reg [1:0] steady = 0;

  wire out_enable = ws[1] || (ws[2] && d);
  wire mux_write = op == 2'd0 ? d : (op == 2'd1 ? 1'b1 : (op == 2'd2 ? 1'b0 : !m_out));
  wire edge_hit = (m_rise && (h2 && !prev)) || (m_fall && (!h2 && prev));
  wire level_hit = (m_rise && h2) || (m_fall && !h2);
  wire intr = m_level ? level_hit : edge_hit;

  always @(posedge clk) begin
    f_past <= 1;
    m_dir  <= reset ? 1'b0 : (ws[0] ? d : m_dir);
    m_out  <= reset ? 1'b0 : (out_enable ? mux_write : m_out);
    m_mask <= reset ? 1'b0 : (ws[3] ? d : m_mask);
    m_rise <= reset ? 1'b0 : (ws[4] ? d : m_rise);
    m_fall <= reset ? 1'b0 : (ws[5] ? d : m_fall);
    m_level <= reset ? 1'b0 : (ws[7] ? d : m_level);
    m_stat <= (reset || ws[6]) ? 1'b0 : ((intr && m_mask) ? 1'b1 : m_stat);
    h1 <= lpin;
    h2 <= h1;
    prev <= h2;
    steady <= (!reset && m_dir && !out_enable && steady != 2'd3) ? steady + 2'd1 : ((!reset && m_dir && !out_enable) ? 2'd3 : 2'd0);
  end

  always @(posedge clk) if (f_past) begin
    // 1. Direção e dado só mudam por escrita (o registrador de direção e o de saída seguem o modelo; o reset os zera).
    assert (q[0] == (reset ? 1'b0 : m_dir));
    assert (q[1] == (reset ? 1'b0 : m_out));
    // 2. As máscaras só mudam por escrita.
    assert (q[3] == (reset ? 1'b0 : m_mask));
    assert (q[4] == (reset ? 1'b0 : m_rise));
    assert (q[5] == (reset ? 1'b0 : m_fall));
    assert (q[7] == (reset ? 1'b0 : m_level));
    // 3. A leitura do pino é o pino de dois ciclos atrás, e portanto reflete o pino estável quando é entrada.
    assert (q[2] == h2);
    if (!q[0] && h1 == h2 && h2 == lpin) assert (q[2] == lext);
    // 4. Status (limpeza síncrona): sobe numa borda selecionada pelas máscaras e só desce por leitura ou reset.
    assert (q[6] == m_stat);
    // 5. Com a saída ligada e estável, a leitura e a saída não divergem.
    if (steady == 2'd3 && q[0]) assert (q[2] == q[1]);
    // 6. Como saída, a célula dirige o registrador de saída na polaridade do pino.
`ifdef ACTIVE_LOW
    if (q[0]) assert (drv == !q[1]);
`else
    if (q[0]) assert (drv == q[1]);
`endif
  end

`ifdef COVER
  always @(posedge clk) if (f_past && !reset) begin
    cover (q[6] && q[4] && !q[0]);
    cover (q[6] && q[5] && !q[0]);
    cover (q[6] && q[7] && q[4] && h2 && !q[0]);
    cover (q[6] && q[7] && q[5] && !h2 && !q[0]);
    cover (steady == 2'd3 && q[0] && q[1]);
    cover (q[0] && ws[1] && !m_out && d);
  end
`endif
endmodule
