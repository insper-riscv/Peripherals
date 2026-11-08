// Propriedades do plic_arbiter, verificadas na netlist Verilog que o GHDL sintetiza do VHDL.
// O árbitro é combinacional: para toda entrada, o_id é a fonte pendente e habilitada de maior prioridade
// estritamente acima do limiar, com desempate pelo menor identificador, e zero sem candidata.
`ifndef SOURCES
`define SOURCES 6
`endif
`ifndef PBITS
`define PBITS 3
`endif
`ifndef IDW
`define IDW 3
`endif
module props (input clk);
  localparam N = `SOURCES, P = `PBITS, W = `IDW;
  (* anyseq *) wire [N:1] pend, en;
  (* anyseq *) wire [N*P-1:0] pri;
  (* anyseq *) wire [P-1:0] thr;
  wire [W-1:0] id;
  wire valid;

  plic_arbiter dut (.i_pending(pend), .i_enable(en), .i_priorities(pri), .i_threshold(thr), .o_id(id), .o_valid(valid));

  // Candidata: pendente, habilitada e com prioridade estritamente acima do limiar.
  reg [N:1] cand;
  always @(*) begin : cand_block
    integer c;
    for (c = 1; c <= N; c = c + 1) cand[c] = pend[c] && en[c] && (pri[(c-1)*P +: P] > thr);
  end

  wire [P-1:0] win_pri = pri[(id == 0 ? 0 : id - 1) * P +: P];

  always @(*) begin
    // 1. Há saída válida exatamente quando existe uma candidata, e o identificador é zero sem candidata.
    assert (valid == (cand != 0));
    assert ((id == 0) == (cand == 0));
    // 2. A vencedora é uma candidata, estritamente maior que o limiar e que zero.
    if (valid) assert (id <= N && cand[id]);
    if (valid) assert (win_pri > thr && win_pri != 0);
  end
  // 3. Nenhuma candidata tem prioridade maior que a da vencedora, e na igualdade o identificador é maior.
  genvar g;
  generate for (g = 1; g <= N; g = g + 1) begin : per_candidate
    always @(*) if (valid && cand[g])
      assert (pri[(g-1)*P +: P] < win_pri || (pri[(g-1)*P +: P] == win_pri && g >= id));
  end endgenerate

`ifdef COVER
  always @(*) begin
    cover (valid && id == 1);
    cover (valid && id == N);
    cover (!valid && pend != 0);
    cover (valid && cand[1] && cand[2] && pri[0 +: P] == pri[P +: P] && id == 1);
  end
`endif
endmodule
