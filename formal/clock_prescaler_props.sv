// Propriedades do clock_prescaler, verificadas na netlist Verilog que o GHDL sintetiza do VHDL.
// Com o prescaler P estável e sem reset, o tick sai exatamente a cada P + 1 ciclos: nem um tick perdido
// nem um duplicado. O modelo é um contador de ciclos independente do hardware: "gap" conta os ciclos
// desde o reset ou desde o último tick, e o tick aparece um ciclo depois de gap chegar a P.
`ifndef WIDTH
`define WIDTH 3
`endif
module props (input clk);
  localparam W = `WIDTH;
  (* anyseq *) wire reset;
  (* anyconst *) wire [W-1:0] presc;
  wire tick;

  clock_prescaler dut (.i_clk(clk), .i_rst(reset), .i_prescaler_in(presc), .o_tick(tick));

  // Os registradores não têm valor inicial: o primeiro clock é um reset, como na placa. O reset não volta
  // depois: a propriedade vale a partir dele, com o prescaler constante.
  reg f_past = 0;
  initial assume (reset);
  always @(posedge clk) if (f_past) assume (!reset);

  reg [W:0] gap = 0;
  // O tick esperado: no ciclo seguinte àquele em que o contador de ciclos alcançou P.
  reg expect_tick = 0;

  always @(posedge clk) begin
    f_past <= 1;
    expect_tick <= !reset && f_past && (gap == presc);
    gap <= (reset || gap >= presc) ? 0 : gap + 1;
  end

  always @(posedge clk) if (f_past) begin
    // 1. O tick sai exatamente nos ciclos do modelo, sem perda nem duplicata.
    assert (tick == expect_tick);
    // 2. O tick dura um ciclo: com P >= 1 nunca há dois ticks seguidos.
    if (presc != 0 && expect_tick) assert (gap == 0);
  end

`ifdef COVER
  reg p_tick = 0;
  always @(posedge clk) begin
    p_tick <= tick;
    // O primeiro tick, e depois um segundo tick a P + 1 ciclos do primeiro.
    cover (f_past && tick && !p_tick && presc == 3);
    cover (f_past && tick && presc == 0);
  end
`endif
endmodule
