// Propriedades do bloco gpio com partição, verificadas na netlist Verilog que o GHDL sintetiza do VHDL. O pino
// bidirecional da netlist é aberto em uma entrada (i_pins, o que o pino vale) e uma saída (o_pins_drv, o que o bloco
// dirige, zero quando solta o pino). Um modelo ideal guarda, por grupo, a direção escrita e o registrador de saída.
// Seja qual for a sequência de acessos no barramento, a leitura de DIR e de OUT, a leitura dos endereços sem
// registrador e o valor dirigido a cada pino são os do modelo: o bit k de um grupo é o k-ésimo pino da lista, a
// direção fixa vale o valor fixo, a polaridade inverte o que é dirigido, e um pino fora de todos os grupos fica
// no nível inativo se é só saída e solto nos outros casos. Duas partições: A (-DPART_A) e B (-DPART_B).
`ifdef PART_A
// 9 pinos; grupos [[0,1,2,3],[5,6],[7]]; o pino 4 (só saída, ativo em nível baixo) e o pino 8 (livre) ficam desligados.
// Direções: 0 livre, 1 só saída em 1, 3 só entrada, 6 só entrada, 4 só saída, 2 só saída e o resto livre (ver dirc).
`define PINS 9
`define GROUPS 3
`define ADDR_BITS 6
`else
// 6 pinos; grupos [[3,2,1,0],[4,5]] (ordem invertida), todos livres, ativos em nível alto.
`define PINS 6
`define GROUPS 2
`define ADDR_BITS 5
`endif
module props (input clk);
  localparam P = `PINS, G = `GROUPS, AW = `ADDR_BITS;

  // Tamanho do grupo g.
  function integer size(input integer g);
`ifdef PART_A
    size = (g == 0) ? 4 : ((g == 1) ? 2 : 1);
`else
    size = (g == 0) ? 4 : 2;
`endif
  endfunction

  // Pino do k-ésimo membro do grupo g.
  function integer member(input integer g, input integer k);
`ifdef PART_A
    member = (g == 0) ? k : ((g == 1) ? (5 + k) : 7);
`else
    member = (g == 0) ? (3 - k) : (4 + k);
`endif
  endfunction

  // Direção fixa do pino p: 0 livre, 1 só entrada, 2 só saída.
  function integer dirc(input integer p);
`ifdef PART_A
    case (p)
      1: dirc = 2;
      3: dirc = 1;
      4: dirc = 2;
      6: dirc = 1;
      default: dirc = 0;
    endcase
`else
    dirc = 0;
`endif
  endfunction

  // Polaridade do pino p: 1 é ativo em nível baixo.
  function integer low(input integer p);
`ifdef PART_A
    low = (p == 1 || p == 4 || p == 5) ? 1 : 0;
`else
    low = 0;
`endif
  endfunction

  // Grupo e posição do pino p; grupo G quando está desligado.
  function integer grp(input integer p);
    integer g, k;
    begin
      grp = G;
      for (g = 0; g < G; g = g + 1)
        for (k = 0; k < size(g); k = k + 1)
          if (member(g, k) == p) grp = g;
    end
  endfunction

  function integer pos(input integer p);
    integer g, k;
    begin
      pos = 0;
      for (g = 0; g < G; g = g + 1)
        for (k = 0; k < size(g); k = k + 1)
          if (member(g, k) == p) pos = k;
    end
  endfunction
  // Direção que o grupo g lê: o valor escrito, com os pinos de direção fixa no valor fixo.
  function [31:0] eff_dir(input integer g, input [31:0] written);
    integer k;
    begin
      eff_dir = 0;
      for (k = 0; k < size(g); k = k + 1)
        eff_dir[k] = (dirc(member(g, k)) == 1) ? 1'b0 : ((dirc(member(g, k)) == 2) ? 1'b1 : written[k]);
    end
  endfunction

  (* anyseq *) wire reset, write, read;
  (* anyseq *) wire [31:0] d;
  (* anyseq *) wire [AW-1:0] addr;
  (* anyseq *) wire [P-1:0] ext;
  wire [31:0] q;
  wire irq;
  wire [P-1:0] drv;

  gpio dut (.i_clk(clk), .i_rst(reset), .i_data_in(d), .i_address(addr), .i_write(write), .i_read(read),
    .o_data_out(q), .o_irq(irq), .i_pins(ext), .o_pins_drv(drv));

  // Os registradores não têm valor inicial: o primeiro clock é um reset, como na placa.
  initial assume (reset);

  reg f_past = 0;
  // Direção escrita e registrador de saída de cada grupo, 32 bits por grupo.
  reg [32*G-1:0] m_dir, m_out;
  // A direção que cada grupo lê.
  wire [32*G-1:0] edir;
  genvar ge;
  generate for (ge = 0; ge < G; ge = ge + 1) begin : g_edir
    assign edir[32*ge +: 32] = eff_dir(ge, m_dir[32*ge +: 32]);
  end endgenerate

  wire [AW-5:0] gsel = addr[AW-1:4];
  wire [3:0] reg_no = addr[3:0];
  wire in_range = gsel < G;
  integer gi;

  always @(posedge clk) begin
    f_past <= 1;
    for (gi = 0; gi < G; gi = gi + 1) begin
      if (reset) begin
        m_dir[32*gi +: 32] <= 0;
        m_out[32*gi +: 32] <= 0;
      end else if (write && gsel == gi) begin
        case (reg_no)
          4'd0: m_dir[32*gi +: 32] <= d & ((32'd1 << size(gi)) - 32'd1);
          4'd1: m_out[32*gi +: 32] <= d & ((32'd1 << size(gi)) - 32'd1);
          4'd2: m_out[32*gi +: 32] <= m_out[32*gi +: 32] | (d & ((32'd1 << size(gi)) - 32'd1));
          4'd3: m_out[32*gi +: 32] <= m_out[32*gi +: 32] & ~d;
          4'd4: m_out[32*gi +: 32] <= m_out[32*gi +: 32] ^ (d & ((32'd1 << size(gi)) - 32'd1));
          default: ;
        endcase
      end
    end
  end

  // 1. Leitura: DIR e OUT dos grupos que existem, zero nos outros grupos e nos endereços sem registrador.
  always @(posedge clk) if (f_past && !reset) begin
    if (!in_range) assert (q == 0);
    else if (reg_no == 4'd0) assert (q == edir[32*gsel +: 32]);
    else if (reg_no >= 4'd1 && reg_no <= 4'd4) assert (q == m_out[32*gsel +: 32]);
    else if (reg_no >= 4'd11) assert (q == 0);
  end

  // 2. O valor dirigido a cada pino é o do modelo.
  genvar gp;
  generate for (gp = 0; gp < P; gp = gp + 1) begin : g_pin
    localparam GG = grp(gp);
    localparam PP = pos(gp);
    localparam GI = (GG == G) ? 0 : GG;
    wire dvr = (GG == G) ? ((dirc(gp) == 2) ? low(gp) : 1'b0)
                         : (edir[32*GI+PP] ? (m_out[32*GI+PP] ^ low(gp)) : 1'b0);
    always @(posedge clk) if (f_past && !reset) assert (drv[gp] == dvr);
  end endgenerate

`ifdef COVER
  always @(posedge clk) if (f_past && !reset) begin
    cover (drv[0] && !drv[1]);
`ifdef PART_A
    cover (drv[4] && drv[5]);
    cover (drv[1] && m_out[1] == 0);
    cover (reg_no == 4'd0 && gsel == 1 && q[0]);
    cover (in_range && gsel == 2 && drv[7]);
`else
    cover (drv[0] && drv[1] && drv[2] && drv[3]);
    cover (drv[4] && !drv[5]);
`endif
  end
`endif
endmodule
