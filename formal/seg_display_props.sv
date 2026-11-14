// Propriedades do seg_display com grupos de dígitos, verificadas na netlist Verilog que o GHDL sintetiza do VHDL,
// com a cadeia JTAG parada. Um modelo ideal guarda o valor de 4 bits por dígito. Seja qual for a sequência de
// escritas do core, a leitura de cada endereço, o valor guardado e os segmentos de cada dígito são os do modelo:
// o dígito k de um grupo ocupa os bits 4k+3 a 4k da palavra 0 do grupo, os outros endereços e os grupos que não
// existem leem zero e ignoram a escrita, e um dígito fora de todos os grupos fica apagado. Duas partições:
// A (-DPART_A) e B (-DPART_B). Com -DDP o módulo roda com has_dp verdadeiro: o modelo guarda também o ponto de
// cada dígito (bit k da palavra 1 do grupo), e o_dp, a leitura da palavra 1 e o bit 7 de cada dígito de o_hex o seguem.
`ifdef DP
`define DW 8
`else
`define DW 7
`endif
`ifdef PART_A
// 8 dígitos; grupos [[0,1,2,3],[5,6]]; os dígitos 4 e 7 ficam apagados.
`define DIGITS 8
`define GROUPS 2
`else
// 6 dígitos; um só grupo [[1]]; os outros cinco dígitos ficam apagados.
`define DIGITS 6
`define GROUPS 1
`endif
module props (input clk);
  localparam N = `DIGITS, G = `GROUPS;

  // Dígitos do grupo g.
  function integer size(input integer g);
`ifdef PART_A
    size = (g == 0) ? 4 : 2;
`else
    size = 1;
`endif
  endfunction

  // Dígito do k-ésimo membro do grupo g.
  function integer member(input integer g, input integer k);
`ifdef PART_A
    member = (g == 0) ? k : (5 + k);
`else
    member = 1;
`endif
  endfunction

  // O dígito n está em algum grupo.
  function integer listed(input integer n);
    integer g, k;
    begin
      listed = 0;
      for (g = 0; g < G; g = g + 1)
        for (k = 0; k < size(g); k = k + 1)
          if (member(g, k) == n) listed = 1;
    end
  endfunction

  // Segmentos em nível baixo de um dígito hexadecimal.
  function [6:0] seg(input [3:0] v);
    case (v)
      4'h0: seg = 7'b1000000;
      4'h1: seg = 7'b1111001;
      4'h2: seg = 7'b0100100;
      4'h3: seg = 7'b0110000;
      4'h4: seg = 7'b0011001;
      4'h5: seg = 7'b0010010;
      4'h6: seg = 7'b0000010;
      4'h7: seg = 7'b1111000;
      4'h8: seg = 7'b0000000;
      4'h9: seg = 7'b0010000;
      4'hA: seg = 7'b0001000;
      4'hB: seg = 7'b0000011;
      4'hC: seg = 7'b1000110;
      4'hD: seg = 7'b0100001;
      4'hE: seg = 7'b0000110;
      default: seg = 7'b0001110;
    endcase
  endfunction

  (* anyseq *) wire reset, write;
  (* anyseq *) wire [31:0] d;
  (* anyseq *) wire [7:0] addr;
  wire [31:0] q;
  wire [4*N-1:0] value;
  wire [`DW*N-1:0] hex;
  wire [N-1:0] dpo;
  wire fail, tdo;

  seg_display dut (.i_clk(clk), .i_rst(reset), .i_address(addr), .i_data_in(d), .i_write(write), .o_rdata(q),
    .i_tck(1'b0), .i_tdi(1'b0), .o_tdo(tdo), .i_ir_in(2'b00), .i_state_cdr(1'b0), .i_state_sdr(1'b0),
    .i_state_udr(1'b0), .i_state_uir(1'b0), .o_value(value), .o_fail(fail), .o_hex(hex), .o_dp(dpo));

  // Os registradores não têm valor inicial: o primeiro clock é um reset, como na placa.
  initial assume (reset);

  reg f_past = 0;
  reg [4*N-1:0] m_val;
  reg [N-1:0] m_dp;

  wire [3:0] gsel = addr[7:4];
  wire [3:0] reg_no = addr[3:0];

  integer gi, k, gj, kj, gp, kp;
  reg [31:0] want;
  always @(posedge clk) begin
    f_past <= 1;
    if (reset) begin
      m_val <= 0;
      m_dp <= 0;
    end else if (write && reg_no == 0) begin
      for (gi = 0; gi < G; gi = gi + 1)
        if (gsel == gi)
          for (k = 0; k < size(gi); k = k + 1)
            m_val[4*member(gi, k) +: 4] <= d[4*k +: 4];
    end
`ifdef DP
    else if (write && reg_no == 1) begin
      for (gi = 0; gi < G; gi = gi + 1)
        if (gsel == gi)
          for (k = 0; k < size(gi); k = k + 1)
            m_dp[member(gi, k)] <= d[k];
    end
`endif
  end

  // A palavra que o core lê: os dígitos do grupo endereçado na palavra 0, e zero no resto.
  always @* begin
    want = 0;
    if (reg_no == 0)
      for (gj = 0; gj < G; gj = gj + 1)
        if (gsel == gj)
          for (kj = 0; kj < size(gj); kj = kj + 1)
            want[4*kj +: 4] = m_val[4*member(gj, kj) +: 4];
`ifdef DP
    if (reg_no == 1)
      for (gp = 0; gp < G; gp = gp + 1)
        if (gsel == gp)
          for (kp = 0; kp < size(gp); kp = kp + 1)
            want[kp] = m_dp[member(gp, kp)];
`endif
  end

  always @(posedge clk) if (f_past) begin
    assert (value == m_val);
    assert (q == want);
`ifdef DP
    assert (dpo == m_dp);
`else
    assert (dpo == 0);
`endif
  end

  // Segmentos: o valor do modelo nos dígitos listados, apagado nos outros (nível baixo da placa).
  genvar gn;
  generate for (gn = 0; gn < N; gn = gn + 1) begin : g_digit
    localparam LST = listed(gn);
    always @(posedge clk) if (f_past)
      assert (hex[`DW*gn +: 7] == (LST ? seg(m_val[4*gn +: 4]) : 7'b1111111));
`ifdef DP
    always @(posedge clk) if (f_past)
      assert (hex[8*gn+7] == (LST ? !m_dp[gn] : 1'b1));
`endif
  end endgenerate

`ifdef COVER
  always @(posedge clk) if (f_past && !reset) begin
    cover (write && reg_no == 0 && gsel < G && d[3:0] == 4'h9);
    cover (reg_no == 0 && gsel < G && q != 0);
`ifdef PART_A
    cover (m_val[23:20] != 0);
    cover (write && gsel == 1 && reg_no == 0);
`endif
`ifdef DP
    cover (write && reg_no == 1 && gsel < G && d[0]);
    cover (reg_no == 1 && gsel < G && q != 0);
    cover (m_dp != 0 && m_val != 0);
`endif
  end
`endif
endmodule
