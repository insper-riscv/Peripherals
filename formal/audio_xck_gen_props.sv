// Propriedades do audio_xck_gen, verificadas na netlist Verilog que o GHDL sintetiza do VHDL. O passo e o módulo
// são constantes quaisquer pequenas (0 < passo <= módulo <= 9). O acumulador do módulo é exposto como saída.
//   1. O acumulador é sempre menor que o módulo.
//   2. Depois de k atualizações, o clock mestre inverteu exatamente floor(k * passo / módulo) vezes, sem perder nem
//      duplicar inversão, e o nível de o_xck é a paridade dessa conta.
module props (input clk);
  (* anyseq *) wire reset;
  (* anyconst *) wire [3:0] step, modulus;
  wire xck, edge_pulse, armed;
  wire [31:0] acc;

  audio_xck_gen dut (.i_clk(clk), .i_rst(reset), .i_enable(1'b1), .i_step({28'd0, step}), .i_mod({28'd0, modulus}),
    .o_xck(xck), .o_edge(edge_pulse), .dbg_acc(acc), .dbg_armed(armed));

  // O primeiro clock é um reset, como na placa; as propriedades valem a partir dele.
  reg f_past = 0;
  initial assume (reset);
  always @(posedge clk) if (f_past) assume (!reset);
  always @* assume (step != 0 && step <= modulus && modulus <= 4'd9);

  // k conta as atualizações do acumulador e e conta as inversões já anunciadas por o_edge.
  reg [7:0] k = 0, e = 0;
  always @(posedge clk) begin
    f_past <= 1;
    if (f_past && armed) k <= k + 1;
    if (f_past && edge_pulse) e <= e + 1;
  end

  // O primeiro ciclo, de reset, não conta: os registradores ainda não têm valor.
  wire [7:0] flips = e + (f_past ? edge_pulse : 1'b0);
  wire [15:0] done = k * step;
  wire [15:0] lower = flips * modulus;
  wire [15:0] upper = (flips + 1) * modulus;

  always @(posedge clk) if (f_past) begin
    assert (acc < modulus);
    assert (lower <= done);
    assert (done < upper);
    assert (xck == flips[0]);
  end

`ifdef COVER
  always @(posedge clk) if (f_past) begin
    cover (flips == 3);
    cover (step == modulus && flips == 4);
  end
`endif
endmodule
