// Propriedades do audio_frame_clocks, verificadas na netlist Verilog que o GHDL sintetiza do VHDL. O divisor do
// BCLK e o número de ciclos por canal são constantes quaisquer pequenas e as inversões do clock mestre chegam em
// qualquer ordem. Com xc inversões do mestre contadas desde que a geração foi habilitada:
//   1. O BCLK inverteu floor(xc / divisor) vezes, e seu nível é a paridade dessa conta.
//   2. O LRCK inverteu floor(floor(xc / divisor) / 2 / ciclos por canal) vezes, uma a cada ciclos por canal
//      bordas de descida do BCLK, e seu nível é a paridade dessa conta.
//   3. Com a geração desabilitada, BCLK e LRCK ficam em '0'.
module props (input clk);
  (* anyseq *) wire reset, enable, xck_edge;
  (* anyconst *) wire [2:0] div, slot;
  wire bclk, lrck;

  audio_frame_clocks dut (.i_clk(clk), .i_rst(reset), .i_enable(enable), .i_xck_edge(xck_edge),
    .i_bclk_div({13'd0, div}), .i_slot_bits({13'd0, slot}), .o_bclk(bclk), .o_lrck(lrck));

  reg f_past = 0;
  initial assume (reset);
  always @(posedge clk) if (f_past) assume (!reset);
  always @* assume (div != 0 && div <= 3'd3 && slot != 0 && slot <= 3'd2);

  // Inversões do mestre desde que a geração foi habilitada.
  reg [7:0] xc = 0;
  always @(posedge clk) begin
    f_past <= 1;
    xc <= (reset || !enable) ? 8'd0 : xc + xck_edge;
  end

  wire [7:0] bclk_flips = xc / div;
  wire [7:0] falls = bclk_flips / 2;
  wire [7:0] lrck_flips = falls / slot;

  reg en_prev = 0;
  always @(posedge clk) en_prev <= enable;

  always @(posedge clk) if (f_past && en_prev) begin
    assert (bclk == bclk_flips[0]);
    assert (lrck == lrck_flips[0]);
  end

  always @(posedge clk) if (f_past && !en_prev) begin
    assert (!bclk && !lrck);
  end

`ifdef COVER
  always @(posedge clk) if (f_past) begin
    cover (lrck_flips == 2 && div == 1 && slot == 1);
    cover (bclk_flips == 3);
  end
`endif
endmodule
