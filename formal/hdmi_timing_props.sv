// Propriedades do gerador de temporização do HDMI (video_timing), verificadas na netlist Verilog que o GHDL
// sintetiza do VHDL, com um modo pequeno que mantém todas as regiões (visível, pórtico frontal, sincronismo,
// pórtico traseiro, imagem ampliada centrada e faixas pretas) em ambas as direções.
//
// O modelo é um par de contadores de coluna e de linha independente do hardware, definido só pelos generics.
// Cada saída tem de ser igual à função do modelo (HS, VS, área visível, imagem, coordenadas do framebuffer e as
// saídas registradas de quadro). Um segundo grupo de propriedades mede o que o gerador entrega, sem usar o
// modelo: a distância entre inícios de pulso de HS é a linha inteira, a largura do pulso é a do generic, a
// distância entre inícios de pulso de VS é o quadro inteiro, a largura do pulso de VS é v_sync linhas e há
// v_visible linhas com DE por quadro.
//   -DINVARIANT  prova por indução, com os contadores do hardware expostos e ligados ao modelo
//   -DMEASURE    mede linha, quadro, larguras e linhas visíveis (limitado, mais de dois quadros)
//   -DCOVER      alcança o fim do quadro e o pulso de VS
`ifndef HPOS
`define HPOS 1
`endif
`ifndef VPOS
`define VPOS 1
`endif
module props (input clk);
  localparam HV = 6, HF = 2, HS = 3, HB = 4, VV = 5, VF = 1, VS = 2, VB = 3, FBW = 2, FBH = 2, SC = 2;
  localparam HT = HV + HF + HS + HB;
  localparam VT = VV + VF + VS + VB;
  localparam IW = FBW * SC, IH = FBH * SC;
  localparam XO = (HV - IW) / 2, YO = (VV - IH) / 2;
  localparam HBEG = HV + HF, VBEG = VV + VF;

  (* anyseq *) wire reset;
  wire o_hs, o_vs, o_vsync, o_vblank, o_visible, o_image;
  wire [1:0] o_fb_x, o_fb_y;
  // Contadores internos do hardware, expostos pela netlist: a lógica é a mesma, e a indução enuncia o estado.
  wire [3:0] d_h_cnt, d_v_cnt;
  wire [0:0] d_fb_x, d_x_sub, d_fb_y, d_y_sub;

  video_timing dut (.i_clk(clk), .i_rst(reset), .o_hs(o_hs), .o_vs(o_vs), .o_vsync(o_vsync), .o_vblank(o_vblank),
                    .o_visible(o_visible), .o_image(o_image), .o_fb_x(o_fb_x), .o_fb_y(o_fb_y),
                    .dbg_h_cnt(d_h_cnt), .dbg_v_cnt(d_v_cnt), .dbg_fb_x(d_fb_x), .dbg_x_sub(d_x_sub),
                    .dbg_fb_y(d_fb_y), .dbg_y_sub(d_y_sub));

  // Os registradores não têm valor inicial: o primeiro clock é um reset, como na placa. O reset não volta depois.
  reg f_past = 0;
  initial assume (reset);
  always @(posedge clk) if (f_past) assume (!reset);

  // Modelo: coluna e linha atuais, e as duas saídas registradas, que mostram a linha do ciclo anterior.
  reg [7:0] col = 0, line = 0;
  reg exp_vsync = 0, exp_vblank = 0;
  wire hs_pulse = col >= HBEG && col < HBEG + HS;
  wire vs_pulse = line >= VBEG && line < VBEG + VS;
  wire in_x = col >= XO && col < XO + IW;
  wire in_y = line >= YO && line < YO + IH;

  always @(posedge clk) begin
    f_past <= 1;
    col <= (reset || col == HT - 1) ? 0 : col + 1;
    line <= reset ? 0 : (col == HT - 1) ? ((line == VT - 1) ? 0 : line + 1) : line;
    exp_vsync <= !reset && vs_pulse;
    exp_vblank <= !reset && line >= VV;
  end

  always @(posedge clk) if (f_past) begin
    assert (o_hs == (`HPOS ? hs_pulse : !hs_pulse));
    assert (o_vs == (`VPOS ? vs_pulse : !vs_pulse));
    assert (o_visible == (col < HV && line < VV));
    assert (o_image == (in_x && in_y));
    assert (o_vsync == exp_vsync);
    assert (o_vblank == exp_vblank);
    // As coordenadas nunca saem do framebuffer e, dentro da imagem, são as do pixel ampliado.
    assert (o_fb_x < FBW);
    assert (o_fb_y < FBH);
    if (in_x && in_y) begin
      assert (o_fb_x == (col - XO) / SC);
      assert (o_fb_y == (line - YO) / SC);
    end
  end

`ifdef INVARIANT
  // Os contadores do hardware são o modelo, e as fases da ampliação seguem a posição dentro da imagem.
  always @(posedge clk) if (f_past) begin
    assert (col < HT && line < VT);
    assert (d_h_cnt == col);
    assert (d_v_cnt == line);
    assert (d_fb_x < FBW && d_fb_y < FBH && d_x_sub < SC && d_y_sub < SC);
    if (in_x) assert (d_fb_x == (col - XO) / SC && d_x_sub == (col - XO) % SC);
    if (in_y) assert (d_fb_y == (line - YO) / SC && d_y_sub == (line - YO) % SC);
  end
`endif

`ifdef MEASURE
  // Medidas feitas só sobre as saídas. Um pulso é o nível ativo da polaridade do generic.
  wire hs_act = (o_hs == `HPOS);
  wire vs_act = (o_vs == `VPOS);
  reg hs_prev = 0, vs_prev = 0, de_prev = 0;
  reg seen_hs = 0, seen_vs = 0;
  reg [15:0] since_hs = 0, since_vs = 0, run_hs = 0, run_vs = 0, run_de = 0, de_lines = 0;
  always @(posedge clk) if (f_past) begin
    hs_prev <= hs_act;
    vs_prev <= vs_act;
    de_prev <= o_visible;
    since_hs <= (hs_act && !hs_prev) ? 1 : since_hs + 1;
    since_vs <= (vs_act && !vs_prev) ? 1 : since_vs + 1;
    run_hs <= hs_act ? run_hs + 1 : 0;
    run_vs <= vs_act ? run_vs + 1 : 0;
    run_de <= o_visible ? run_de + 1 : 0;
    if (hs_act && !hs_prev) seen_hs <= 1;
    if (hs_act && !hs_prev && seen_hs) assert (since_hs == HT);
    if (!hs_act && hs_prev) assert (run_hs == HS);
    if (vs_act && !vs_prev) seen_vs <= 1;
    if (vs_act && !vs_prev && seen_vs) assert (since_vs == HT * VT);
    if (!vs_act && vs_prev) assert (run_vs == VS * HT);
    if (!o_visible && de_prev) assert (run_de == HV);
    // Linhas com DE entre dois inícios de pulso de VS: exatamente as visíveis.
    de_lines <= (vs_act && !vs_prev) ? 0 : de_lines + (o_visible && !de_prev);
    if (vs_act && !vs_prev && seen_vs) assert (de_lines == VV);
  end
`endif

`ifdef COVER
  always @(posedge clk) begin
    cover (f_past && vs_pulse && line == VBEG + VS - 1 && col == HT - 1);
    cover (f_past && o_image && o_fb_x == FBW - 1 && o_fb_y == FBH - 1);
  end
`endif
endmodule
