// Propriedades do plic_gateway, verificadas na netlist Verilog que o GHDL sintetiza do VHDL.
// O gateway tem no máximo um pedido por atendimento: com a linha em 1 e a fonte livre o pedido fica pendente e a
// fonte passa a ser mascarada; o claim limpa o pendente; só o complete desmascara; o pendente não cai com a linha.
module props (input clk);
  (* anyseq *) wire reset, source, claim, complete;
  wire pending;

  plic_gateway dut (.i_clk(clk), .i_rst(reset), .i_source(source), .i_claim(claim), .i_complete(complete),
    .o_pending(pending));

  // Os registradores não têm valor inicial: o primeiro clock é um reset, como na placa.
  initial assume (reset);
  reg f_past = 0;
  reg m_pending = 0, m_fly = 0;
  always @(posedge clk) begin
    f_past <= 1;
    m_pending <= reset ? 1'b0 : ((source && !m_fly) ? 1'b1 : (claim ? 1'b0 : m_pending));
    m_fly <= reset ? 1'b0 : ((source && !m_fly) ? 1'b1 : (complete ? 1'b0 : m_fly));
  end

  // Valores do ciclo anterior para enunciar as propriedades de transição.
  reg p_pending = 0, p_source = 0, p_claim = 0, p_complete = 0, p_reset = 1;
  always @(posedge clk) begin
    p_pending <= pending; p_source <= source; p_claim <= claim; p_complete <= complete; p_reset <= reset;
  end

  // 1. O pendente é o do modelo, também depois de um reset no meio da execução.
  always @(*) if (f_past) assert (pending == m_pending);
  always @(*) if (f_past && !p_reset) begin
    // 2. Um pendente novo só nasce de uma linha em 1 no ciclo anterior (nunca de um complete nem de um claim).
    if (pending && !p_pending) assert (p_source);
    // 3. Sem claim e sem reset, o pendente não cai: a linha baixa não o retira.
    if (p_pending && !p_claim) assert (pending);
    // 4. Um claim sem nova linha limpa o pendente.
    if (p_claim && !p_source) assert (!pending);
  end

`ifdef COVER
  always @(posedge clk) begin
    cover (f_past && !reset && pending && !p_pending);
    cover (f_past && !reset && !pending && p_pending && p_claim);
    // Complete com a linha ainda em 1: novo pedido no ciclo seguinte.
    cover (f_past && !reset && pending && !p_pending && p_complete == 0 && source);
  end
`endif
endmodule
