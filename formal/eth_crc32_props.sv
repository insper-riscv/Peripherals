// Propriedades do eth_crc32, verificadas na netlist Verilog que o GHDL sintetiza do VHDL. O modelo de referência
// é outra formulação do mesmo CRC: o registrador não refletido, com o bit mais significativo primeiro e o
// polinômio 0x04C11DB7, que é o espelho bit a bit do registrador refletido do projeto.
//   1. O estado do projeto é o espelho do modelo depois de qualquer sequência de limpeza, absorção e reset.
//   2. o_residue_ok vale exatamente quando o estado é o resíduo 0xDEBB20E3.
//   3. Com i_wide em 1 o registrador absorve o byte {nibble_hi, nibble} (nibble baixo primeiro), e o modelo faz os
//      mesmos oito passos de um bit; com i_wide em 0 absorve só o nibble baixo.
//   4. Para qualquer estado, absorver os oito nibbles do complemento do estado, o menos significativo primeiro,
//      leva ao resíduo: é o que faz o FCS enviado ser aceito na recepção.
module props (input clk);
  (* anyseq *) wire reset, clear, enable, wide;
  (* anyseq *) wire [3:0] nibble, nibble_hi;
  (* anyconst *) wire [31:0] any_state;
  wire [31:0] crc;
  wire residue_ok;

  eth_crc32 dut (.i_clk(clk), .i_rst(reset), .i_clear(clear), .i_enable(enable), .i_nibble(nibble), .i_wide(wide), .i_nibble_hi(nibble_hi),
    .o_crc(crc), .o_residue_ok(residue_ok));

  // Os registradores têm o valor inicial do VHDL, o mesmo do modelo.
  function [31:0] mirror(input [31:0] x);
    integer i;
    begin
      for (i = 0; i < 32; i = i + 1) mirror[i] = x[31 - i];
    end
  endfunction

  // Quatro passos de um bit do CRC não refletido, o bit 0 do nibble primeiro.
  function [31:0] step(input [31:0] s, input [3:0] n);
    integer i;
    reg feedback;
    begin
      step = s;
      for (i = 0; i < 4; i = i + 1) begin
        feedback = step[31] ^ n[i];
        step = {step[30:0], 1'b0} ^ (feedback ? 32'h04C11DB7 : 32'h0);
      end
    end
  endfunction

  reg [31:0] m = 32'hFFFFFFFF;
  always @(posedge clk) m <= (reset || clear) ? 32'hFFFFFFFF : (enable ? (wide ? step(step(m, nibble), nibble_hi) : step(m, nibble)) : m);

  // Resíduo do modelo depois dos oito nibbles do complemento de um estado qualquer.
  reg [31:0] r;
  integer k;
  always @* begin
    r = mirror(any_state);
    for (k = 0; k < 8; k = k + 1) r = step(r, ~any_state[4 * k +: 4]);
  end

  always @(posedge clk) begin
    assert (mirror(crc) == m);
    assert (residue_ok == (crc == 32'hDEBB20E3));
  end

  always @* assert (r == mirror(32'hDEBB20E3));

`ifdef COVER
  always @(posedge clk) begin
    cover (residue_ok);
    cover ($past(enable) && $past(wide) && !$past(clear) && !$past(reset));
    cover ($past(enable) && !$past(clear) && !$past(reset));
  end
`endif
endmodule
