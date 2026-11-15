// Propriedades do tmds_encoder, verificadas na netlist Verilog que o GHDL sintetiza do VHDL. O codificador TMDS de
// um canal é registrado: o símbolo de cada ciclo vem da entrada do ciclo anterior, guardada aqui em f_*.
//   1. Depois de um reset o símbolo é o de controle 00 e a disparidade acumulada é zero.
//   2. Sem habilitação de dados o símbolo é o de controle de C1 C0 e a disparidade volta a zero.
//   3. Com dados, o símbolo decodificado pelo caminho inverso do DVI é o byte de entrada.
//   4. A disparidade acumulada do codificador é a soma, desde o último apagamento, dos bits em 1 menos os bits em 0
//      dos símbolos que de fato saíram, e o seu módulo nunca passa de 8.
`ifndef MAXDIS
`define MAXDIS 8
`endif
module props (input clk);
  (* anyseq *) wire reset, de, c0, c1;
  (* anyseq *) wire [7:0] d;
  wire [9:0] q;
  wire [5:0] dbg_disparity;

  tmds_encoder dut (.i_clk(clk), .i_rst(reset), .i_de(de), .i_c0(c0), .i_c1(c1), .i_d(d), .o_q(q),
    .dbg_disparity(dbg_disparity));

  // O primeiro clock é um reset, como na placa; as propriedades valem a partir dele.
  reg f_past = 0;
  initial assume (reset);
  reg f_reset = 0, f_de = 0, f_c0 = 0, f_c1 = 0;
  reg [7:0] f_d = 0;
  reg signed [5:0] f_dis = 0;
  always @(posedge clk) begin
    f_past <= 1;
    f_reset <= reset; f_de <= de; f_c0 <= c0; f_c1 <= c1; f_d <= d;
    f_dis <= dbg_disparity;
  end

  // Decodificação do DVI: desfaz a inversão do bit 9 e depois o XOR ou XNOR em cadeia do bit 8.
  function [7:0] decode(input [9:0] t);
    reg [7:0] b;
    integer i;
    begin
      b = t[9] ? ~t[7:0] : t[7:0];
      decode[0] = b[0];
      for (i = 1; i < 8; i = i + 1)
        decode[i] = t[8] ? (b[i] ^ b[i-1]) : ~(b[i] ^ b[i-1]);
    end
  endfunction

  function integer ones(input [9:0] t);
    integer i;
    begin
      ones = 0;
      for (i = 0; i < 10; i = i + 1) ones = ones + t[i];
    end
  endfunction

  function [9:0] control(input c1_in, input c0_in);
    case ({c1_in, c0_in})
      2'b00: control = 10'b1101010100;
      2'b01: control = 10'b0010101011;
      2'b10: control = 10'b0101010100;
      default: control = 10'b1010101011;
    endcase
  endfunction

  wire signed [5:0] dis = dbg_disparity;

  // Invariante de estado, que a indução usa: a disparidade fica limitada. O reset do primeiro ciclo leva o estado a
  // zero, então supor o estado inicial em zero não restringe nenhum estado alcançável.
  initial assume (dis == 0);
  // A disparidade é sempre par, porque cada símbolo tem 10 bits.
  always @(posedge clk) assert (dis >= -`MAXDIS && dis <= `MAXDIS);
  always @(posedge clk) assert (!dis[0]);

  always @(posedge clk) if (f_past) begin
    if (f_reset) begin
      assert (q == 10'b1101010100);
      assert (dis == 0);
    end else if (!f_de) begin
      assert (q == control(f_c1, f_c0));
      assert (dis == 0);
    end else begin
      assert (decode(q) == f_d);
      assert (dis == f_dis + 2 * ones(q) - 10);
    end
  end

`ifdef COVER
  always @(posedge clk) if (f_past) begin
    cover (!f_reset && f_de && q[9] && dis != 0);
    cover (!f_reset && f_de && !q[9] && dis != 0);
    cover (!f_reset && !f_de && q == 10'b1010101011);
    cover (!f_reset && f_de && f_dis != 0 && dis == 0);
  end
`endif
endmodule
