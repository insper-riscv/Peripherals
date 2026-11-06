// Propriedades do plic, verificadas na netlist Verilog que o GHDL sintetiza do VHDL, com N fontes, P bits de
// prioridade e endereço de 20 bits de palavra. Um modelo guarda prioridades, habilitação, limiar, pendentes e
// as fontes em atendimento. Seja qual for a sequência de acessos e de linhas, a saída e a leitura de cada
// endereço são as do modelo, e o claim obedece à especificação: a fonte pendente e habilitada de maior
// prioridade acima do limiar, com desempate pelo menor id, ou zero. O complete só desmascara a fonte escrita.
`ifndef SOURCES
`define SOURCES 4
`endif
`ifndef PBITS
`define PBITS 2
`endif
`ifndef IDW
`define IDW 3
`endif
module props (input clk);
  localparam N = `SOURCES, P = `PBITS, W = `IDW;
  localparam [19:0] A_PEND = 20'h00400, A_EN = 20'h00800, A_THR = 20'h80000, A_CLAIM = 20'h80001;
  (* anyseq *) wire reset, write, read;
  (* anyseq *) wire [31:0] data;
  (* anyseq *) wire [19:0] addr;
  (* anyseq *) wire [N:1] lines;
  wire [31:0] dout;
  wire meip;
  wire [N-1:0] dbg_pending, dbg_enable_reg;
  wire [N*P-1:0] dbg_priorities;
  wire [P-1:0] dbg_threshold;

  plic dut (.i_clk(clk), .i_rst(reset), .i_sources(lines), .i_data_in(data), .i_address(addr), .i_write(write),
    .i_read(read), .o_data_out(dout), .o_meip(meip), .dbg_pending(dbg_pending), .dbg_enable_reg(dbg_enable_reg),
    .dbg_priorities(dbg_priorities), .dbg_threshold(dbg_threshold));

  // Os registradores não têm valor inicial: o primeiro clock é um reset, como na placa.
  initial assume (reset);

  reg f_past = 0;
  reg [N*P-1:0] m_pri = 0;
  reg [N:1] m_en = 0, m_pend = 0, m_fly = 0;
  reg [P-1:0] m_thr = 0;

  wire is_claim_rd = read && addr == A_CLAIM;
  wire [N:1] done_hit;
  wire [N:1] claim_hit;
  genvar g;
  generate for (g = 1; g <= N; g = g + 1) begin : per_source
    assign claim_hit[g] = is_claim_rd && dout == g;
    assign done_hit[g] = write && addr == A_CLAIM && data == g && m_en[g];
  end endgenerate

  integer k;
  always @(posedge clk) begin
    f_past <= 1;
    if (reset) begin
      m_pri <= 0; m_en <= 0; m_thr <= 0; m_pend <= 0; m_fly <= 0;
    end else begin
      if (write && addr == A_THR) m_thr <= data[P-1:0];
      for (k = 1; k <= N; k = k + 1) begin
        if (write && addr == k) m_pri[(k-1)*P +: P] <= data[P-1:0];
        if (write && addr == A_EN) m_en[k] <= data[k];
        if (claim_hit[k]) m_pend[k] <= 1'b0;
        if (done_hit[k]) m_fly[k] <= 1'b0;
        if (lines[k] && !m_fly[k]) begin m_pend[k] <= 1'b1; m_fly[k] <= 1'b1; end
      end
    end
  end

  // Candidatas do estado do modelo, escritas direto da definição da especificação.
  reg [N:1] cand;
  always @(*) begin : cand_block
    integer c;
    for (c = 1; c <= N; c = c + 1) cand[c] = m_pend[c] && m_en[c] && (m_pri[(c-1)*P +: P] > m_thr);
  end

  // Leitura esperada de cada endereço, exceto o claim.
  reg [31:0] expect_dout;
  always @(*) begin
    expect_dout = 32'h0;
    if (addr == A_PEND) expect_dout = {{(31-N){1'b0}}, m_pend, 1'b0};
    else if (addr == A_EN) expect_dout = {{(31-N){1'b0}}, m_en, 1'b0};
    else if (addr == A_THR) expect_dout = {30'b0, m_thr};
    else if (addr >= 1 && addr <= N) expect_dout = {30'b0, m_pri[(addr-1)*P +: P]};
  end

  wire [P-1:0] win_pri = m_pri[(dout == 0 ? 0 : dout - 1) * P +: P];
  reg [N:1] m_pend_prev = 0, m_fly_prev = 0, complete_prev = 0, arm = 0;
  reg reset_prev = 1;
  always @(posedge clk) begin
    m_pend_prev <= m_pend; m_fly_prev <= m_fly; reset_prev <= reset;
    complete_prev <= done_hit;
    // Fonte livre (não mascarada) com a linha em 1 e sem reset: o pedido aparece no ciclo seguinte.
    arm <= ~m_fly & lines & {N{~reset}};
  end

  // O estado visível do PLIC é o do modelo.
  always @(*) if (f_past) begin
    assert (dbg_pending == m_pend);
    assert (dbg_enable_reg == m_en);
    assert (dbg_priorities == m_pri);
    assert (dbg_threshold == m_thr);
  end

  // O pedido ao núcleo existe exatamente quando há uma candidata.
  always @(*) if (f_past) assert (meip == (cand != 0));

  // A leitura de cada endereço, exceto o claim, devolve o registrador do modelo; fora do mapa lê zero.
  always @(*) if (f_past && addr != A_CLAIM) assert (dout == expect_dout);

  // Claim: zero sem candidata; senão a candidata de maior prioridade, com desempate pelo menor id.
  always @(*) if (f_past && addr == A_CLAIM) begin
    assert (dout[31:W] == 0);
    assert ((dout == 0) == (cand == 0));
    if (cand != 0) assert (dout <= N && cand[dout]);
  end
  generate for (g = 1; g <= N; g = g + 1) begin : per_candidate
    always @(*) if (f_past && addr == A_CLAIM && cand[g])
      assert (m_pri[(g-1)*P +: P] < win_pri || (m_pri[(g-1)*P +: P] == win_pri && g >= dout));
  end endgenerate

  // Complete: uma fonte em atendimento só deixa de estar mascarada se foi escrita no claim/complete com o id dela
  // (e habilitada); sem isso, nenhum pendente novo nasce nela. Com a linha em 1 numa fonte livre, o pedido nasce.
  generate for (g = 1; g <= N; g = g + 1) begin : per_gateway
    always @(*) if (f_past && !reset_prev) begin
      if (m_fly_prev[g] && !complete_prev[g]) assert (!(dbg_pending[g-1] && !m_pend_prev[g]));
      if (arm[g]) assert (dbg_pending[g-1]);
    end
  end endgenerate

`ifdef COVER
  always @(posedge clk) if (f_past && !reset) begin
    cover (meip);
    cover (is_claim_rd && dout == N && cand == {N{1'b1}});
    cover (|(m_fly & lines) && (cand == 0) && m_pend == 0);
    cover (|(m_fly_prev & complete_prev) && |arm);
    cover (m_pend != 0 && m_en == 0);
    cover (m_pend != 0 && m_thr != 0 && cand == 0);
  end
`endif
endmodule
