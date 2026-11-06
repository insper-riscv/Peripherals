// Propriedades do clint_mtime, verificadas na netlist Verilog que o GHDL sintetiza do VHDL.
// Um modelo guarda o valor ideal do contador de 64 bits. Seja qual for a entrada, o valor que o contador
// mostra (a metade alta com o vai-um pendente somado) é o do modelo: soma um por incremento, a escrita vence
// o incremento do próprio ciclo e o vai-um entre as metades nunca se perde.
module props (input clk);
  (* anyseq *) wire reset, inc, we_lo, we_hi;
  (* anyseq *) wire [31:0] wdata;
  wire [31:0] lo, hi;
  // Os registradores do contador (metade baixa, metade alta sem o vai-um e o vai-um pendente), expostos pelo
  // script (expose em formal/run.sh) para a invariante de indução.
  wire [31:0] dbg_lo, dbg_hi;
  wire dbg_carry;

  clint_mtime dut (.i_clk(clk), .i_rst(reset), .i_inc(inc), .i_we_lo(we_lo), .i_we_hi(we_hi),
    .i_wdata(wdata), .o_lo(lo), .o_hi(hi), .dbg_lo(dbg_lo), .dbg_hi(dbg_hi), .dbg_carry(dbg_carry));

  // Os registradores não têm valor inicial: o primeiro clock é um reset, como na placa.
  initial assume (reset);

  reg f_past = 0;
  reg [63:0] model = 64'h0;
  reg [31:0] p_lo = 0, p_hi = 0;
  reg p_reset = 0, p_we_lo = 0, p_we_hi = 0;

  wire        carry_out = inc && !we_lo && model[31:0] == 32'hFFFFFFFF;
  wire [31:0] lo_next   = we_lo ? wdata : (model[31:0] + {31'b0, inc});
  wire [31:0] hi_base   = we_hi ? wdata : model[63:32];
  wire [31:0] hi_next   = hi_base + {31'b0, carry_out};

  always @(posedge clk) begin
    f_past <= 1;
    p_lo <= lo; p_hi <= hi;
    p_reset <= reset; p_we_lo <= we_lo; p_we_hi <= we_hi;
    model <= reset ? 64'h0 : {hi_next, lo_next};
  end

  always @(posedge clk) if (f_past && !reset) begin
    // 0. Invariante de indução: o modelo é o estado dos registradores, com o vai-um pendente somado à metade alta.
    assert (model == {dbg_hi + {31'b0, dbg_carry}, dbg_lo});
    // 1. O valor mostrado é o valor ideal de 64 bits, em todo ciclo.
    assert ({hi, lo} == model);
  end

`ifdef COVER
  // O vai-um entre as metades é alcançável, e uma escrita da metade alta junto da volta da baixa.
  always @(posedge clk) if (f_past && !reset) begin
    cover (p_lo == 32'hFFFFFFFF && lo == 32'h0 && hi == p_hi + 1);
    cover (p_we_hi && p_lo == 32'hFFFFFFFF && inc);
  end
`endif
endmodule
