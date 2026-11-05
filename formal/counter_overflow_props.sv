// Propriedades do counter_overflow, verificadas na netlist Verilog que o GHDL sintetiza do VHDL.
// O estouro vale exatamente quando o contador alcançou o topo (contador >= topo, sem sinal): nem antes
// (contador menor que o topo) nem depois (igual ou maior).
`ifndef WIDTH
`define WIDTH 8
`endif
module props (input clk);
  localparam W = `WIDTH;
  (* anyseq *) wire [W-1:0] cnt, top;
  wire ovf;

  counter_overflow dut (.i_counter_value(cnt), .i_top_value(top), .o_overflow(ovf));

  always @(*) begin
    // 1. Estouro se e só se o contador alcançou o topo.
    assert (ovf == (cnt >= top));
    // 2. No topo exato há estouro, e um valor abaixo dele não estoura.
    if (cnt == top) assert (ovf);
    if (cnt < top) assert (!ovf);
    // 3. O topo máximo só estoura no valor máximo.
    if (top == {W{1'b1}}) assert (ovf == (cnt == {W{1'b1}}));
  end

`ifdef COVER
  always @(*) begin
    cover (ovf && cnt == top);
    cover (ovf && cnt > top);
    cover (!ovf);
  end
`endif
endmodule
