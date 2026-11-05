// Propriedades do alu_ge_unsigned, verificadas na netlist Verilog que o GHDL sintetiza do VHDL.
// O comparador é combinacional: para toda entrada, o_ge é exatamente "a >= b" sem sinal, inclusive na
// igualdade e nos extremos (b = 0 e a = 2^W - 1).
`ifndef WIDTH
`define WIDTH 8
`endif
module props (input clk);
  localparam W = `WIDTH;
  (* anyseq *) wire [W-1:0] a, b;
  wire ge;

  alu_ge_unsigned dut (.i_source_1(a), .i_source_2(b), .o_ge(ge));

  always @(*) begin
    // 1. O resultado é a comparação sem sinal, em toda entrada.
    assert (ge == (a >= b));
    // 2. A igualdade conta como maior ou igual.
    if (a == b) assert (ge);
    // 3. Todo valor é maior ou igual a zero, e só o zero é maior ou igual ao máximo quando é o máximo.
    if (b == 0) assert (ge);
    if (b == {W{1'b1}}) assert (ge == (a == {W{1'b1}}));
  end

`ifdef COVER
  always @(*) begin
    cover (a > b);
    cover (a == b);
    cover (a < b);
  end
`endif
endmodule
