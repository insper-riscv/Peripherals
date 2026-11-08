// Propriedades do clint, verificadas na netlist Verilog que o GHDL sintetiza do VHDL, com tick_cycles = TICK.
// Um modelo ideal guarda o mtime de 64 bits, o mtimecmp, o msip, a fase do divisor e o MTIP. Seja qual for a
// sequência de acessos no barramento, as saídas e a leitura de cada endereço são as do modelo. Com -DSEQ o
// barramento segue a escrita do porte do FreeRTOS (metade baixa em 0xFFFFFFFF, metade alta, metade baixa) e a
// prova afirma que o MTIP nunca sobe no meio da sequência sem que o valor antigo ou o final do mtimecmp o
// tenha feito subir.
`ifndef TICK
`define TICK 3
`endif
module props (input clk);
  localparam T = `TICK;
  localparam [13:0] A_MSIP = 14'h0000, A_CMP_LO = 14'h1000, A_CMP_HI = 14'h1001,
                    A_MT_LO = 14'h2FFE, A_MT_HI = 14'h2FFF;
  (* anyseq *) wire reset, write, read;
  (* anyseq *) wire [31:0] data;
  (* anyseq *) wire [13:0] addr;
  wire [31:0] dout;
  wire irq_timer, irq_software;
  wire [63:0] mtime_out;
  // Os registradores do CLINT, expostos pelo script (expose em formal/run.sh) para a invariante de indução.
  wire dbg_msip;
  wire [31:0] dbg_cmp_lo, dbg_cmp_hi, dbg_mtime_lo, dbg_mtime_hi;
  wire [1:0] dbg_gen_tick_divided_phase;

  clint dut (.i_clk(clk), .i_rst(reset), .i_data_in(data), .i_address(addr), .i_write(write), .i_read(read),
    .o_data_out(dout), .o_irq_timer(irq_timer), .o_irq_software(irq_software), .o_mtime(mtime_out),
    .dbg_msip(dbg_msip), .dbg_cmp_lo(dbg_cmp_lo), .dbg_cmp_hi(dbg_cmp_hi), .dbg_mtime_lo(dbg_mtime_lo),
    .dbg_mtime_hi(dbg_mtime_hi), .dbg_gen_tick_divided_phase(dbg_gen_tick_divided_phase));

  // Os registradores não têm valor inicial: o primeiro clock é um reset, como na placa.
  initial assume (reset);

  reg f_past = 0;
  reg [63:0] m_mtime = 64'h0;
  reg [63:0] m_cmp = {64{1'b1}};
  reg m_msip = 0, m_mtip = 0;
  reg [7:0] m_phase = 0;
  // O mtime e o mtimecmp do ciclo anterior e se aquele ciclo foi um reset: o MTIP registrado é a comparação deles.
  reg [63:0] p_mtime = 0, p_cmp = {64{1'b1}};
  reg p_rst = 1;

  wire wr_msip = write && addr == A_MSIP;
  wire wr_cmp_lo = write && addr == A_CMP_LO;
  wire wr_cmp_hi = write && addr == A_CMP_HI;
  wire wr_mt_lo = write && addr == A_MT_LO;
  wire wr_mt_hi = write && addr == A_MT_HI;
  wire tick = (m_phase == T - 1);
  wire carry_out = tick && !wr_mt_lo && m_mtime[31:0] == 32'hFFFFFFFF;
  wire [31:0] lo_next = wr_mt_lo ? data : (m_mtime[31:0] + {31'b0, tick});
  wire [31:0] hi_base = wr_mt_hi ? data : m_mtime[63:32];
  wire [31:0] hi_next = hi_base + {31'b0, carry_out};

  always @(posedge clk) begin
    f_past <= 1;
    m_mtime <= reset ? 64'h0 : {hi_next, lo_next};
    m_cmp[31:0] <= reset ? 32'hFFFFFFFF : (wr_cmp_lo ? data : m_cmp[31:0]);
    m_cmp[63:32] <= reset ? 32'hFFFFFFFF : (wr_cmp_hi ? data : m_cmp[63:32]);
    m_msip <= reset ? 1'b0 : (wr_msip ? data[0] : m_msip);
    m_mtip <= reset ? 1'b0 : (m_mtime >= m_cmp);
    m_phase <= (reset || tick) ? 8'h0 : m_phase + 8'h1;
    p_mtime <= m_mtime; p_cmp <= m_cmp; p_rst <= reset;
  end

  // O mtime não dá a volta em 2^64 ticks (mais de cinco mil anos a 100 MHz): o estado com todos os bits em '1' é
  // excluído, o que mantém o mtime monótono sem escrita.
  always @(*) assume (m_mtime != {64{1'b1}});

  // Invariante de indução: o modelo é o estado dos registradores do CLINT. O mtime mostrado tem a metade alta
  // com o vai-um pendente somado, como no valor ideal. Os registradores zeram no reset assíncrono, por isso a
  // invariante vale nos ciclos sem reset.
  always @(*) if (f_past && !reset) begin
    assert (dbg_msip == m_msip);
    // A saída o_mtime é o mtime ideal, o mesmo valor que a leitura em duas metades devolve.
    assert (mtime_out == m_mtime);
    assert ({dbg_cmp_hi, dbg_cmp_lo} == m_cmp);
    assert ({dbg_mtime_hi, dbg_mtime_lo} == m_mtime);
    assert (m_phase == {6'b0, dbg_gen_tick_divided_phase});
    assert (m_phase < T);
    // O MTIP registrado é a comparação do ciclo anterior.
    if (!p_rst) assert (m_mtip == (p_mtime >= p_cmp));
    if (p_rst) assert (!m_mtip);
  end

  reg [31:0] expect_dout;
  always @(*) begin
    case (addr)
      A_MSIP: expect_dout = {31'b0, m_msip};
      A_CMP_LO: expect_dout = m_cmp[31:0];
      A_CMP_HI: expect_dout = m_cmp[63:32];
      A_MT_LO: expect_dout = m_mtime[31:0];
      A_MT_HI: expect_dout = m_mtime[63:32];
      default: expect_dout = 32'h0;
    endcase
  end

  always @(posedge clk) if (f_past) assume (!reset);

`ifndef SEQ
  always @(*) if (f_past && !reset) begin
    // 1. MTIP é a comparação sem sinal de 64 bits do ciclo anterior, e MSIP é o bit 0 do msip.
    assert (irq_timer == m_mtip);
    assert (irq_software == m_msip);
    // 2. A leitura de cada endereço devolve o registrador do modelo; fora do mapa lê zero.
    assert (dout == expect_dout);
  end
`endif

`ifdef SEQ
  (* anyconst *) wire [31:0] fin_hi, fin_lo;
  reg [1:0] p = 0;
  reg [63:0] old = 64'h0;
  always @(posedge clk) if (reset) p <= 0; else case (p)
    0: if (wr_cmp_lo && data == 32'hFFFFFFFF) begin p <= 1; old <= m_cmp; end
    1: if (wr_cmp_hi) p <= 2;
    2: if (wr_cmp_lo) p <= 3;
    default: p <= 0;
  endcase
  always @(*) begin
    // O barramento não escreve o mtime e segue a ordem da sequência do porte.
    assume (!wr_mt_lo && !wr_mt_hi);
    if (p == 1) begin
      assume (!wr_cmp_lo);
      if (wr_cmp_hi) assume (data == fin_hi);
    end
    if (p == 2) begin
      assume (!wr_cmp_hi);
      if (wr_cmp_lo) assume (data == fin_lo);
    end
    if (p == 3) assume (!wr_cmp_lo && !wr_cmp_hi);
  end
  // Durante a sequência (e no ciclo seguinte ao último passo) o MTIP só vale se o valor antigo ou o final
  // do mtimecmp já tivesse feito o mtime alcançá-lo.
  // O mtimecmp em cada passo e o que o ciclo anterior comparou (invariantes da indução).
  always @(*) if (f_past && !reset && !p_rst) begin
    if (p == 1) assert (m_cmp == {old[63:32], 32'hFFFFFFFF} && (p_cmp == old || p_cmp == m_cmp));
    if (p == 2) assert (m_cmp == {fin_hi, 32'hFFFFFFFF} && (p_cmp == m_cmp || p_cmp == {old[63:32], 32'hFFFFFFFF}));
    if (p == 3) assert (m_cmp == {fin_hi, fin_lo} && (p_cmp == m_cmp || p_cmp == {fin_hi, 32'hFFFFFFFF}));
    if (p != 0) assert (m_mtime >= p_mtime);
  end
  always @(*) if (f_past && !reset && p != 0)
    assert (!irq_timer || m_mtime >= old || m_mtime >= {fin_hi, fin_lo});
  always @(*) if (f_past && !reset) assert (irq_timer == m_mtip);
`endif

`ifdef COVER
  reg p_tip = 0;
  always @(posedge clk) begin
    p_tip <= irq_timer;
    // Sobe e desce, vai-um da metade baixa, msip ligado, e uma escrita do mtimecmp com MTIP pendente.
    cover (f_past && !reset && irq_timer && !p_tip);
    cover (f_past && !reset && !irq_timer && p_tip);
    cover (f_past && !reset && irq_software);
`ifndef SEQ
    cover (f_past && !reset && m_mtime[31:0] == 32'h0 && m_mtime[63:32] != 32'h0 && tick);
`endif
  end
`ifdef SEQ
  always @(posedge clk) cover (f_past && !reset && p == 3 && m_mtime >= old);
`endif
`endif
endmodule
