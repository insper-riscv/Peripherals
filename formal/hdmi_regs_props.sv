// Propriedades dos registradores do HDMI (hdmi_regs), verificadas na netlist Verilog que o GHDL sintetiza do
// VHDL. A netlist expõe como saídas os registradores internos (máscara e pendências das interrupções, valores
// anteriores das bordas e o pulso de reinício), cuja lógica é a mesma: eles deixam a indução enunciar o
// estado. O barramento e as entradas de estado (apagamento vertical, pino de interrupção e sequenciador) são
// livres, com addr_width 11 (o espaço de registradores é a metade baixa da janela).
//
// O modelo guarda cada registrador como o contrato da documentação o descreve:
//   - a máscara (palavra 10) muda só por escrita e vale zero depois do reset;
//   - a pendência (palavra 11) soma os eventos (borda de subida do apagamento e borda de ativação do pino),
//     um bit escrito em 1 a limpa, e um evento no mesmo ciclo da limpeza vence a limpeza;
//   - o_irq é o OU das pendências habilitadas, em nível;
//   - o pulso de reinício sai só de uma escrita do bit 0 na palavra 12 com o sequenciador presente;
//   - cada palavra de 8 a 14 lê o que a documentação diz e as outras leem zero, qualquer que seja o dado.
//   -DINITOFF  sem sequenciador (init_enable falso): o reinício nunca sai
//   -DCOVER    alcança a interrupção de fim de quadro, a limpeza, o evento do pino e o reinício
module props (input clk);
  (* anyseq *) wire reset, write, vblank, int_active, busy, done, nack;
  (* anyseq *) wire [10:0] addr;
  (* anyseq *) wire [31:0] wdata;
  (* anyseq *) wire [7:0] sent, nacks;
  wire [31:0] rdata;
  wire seq_start, irq;
  wire [1:0] d_en, d_pend;
  wire d_vprev, d_iprev, d_start;

  hdmi_regs dut (.i_clk(clk), .i_rst(reset), .i_data_in(wdata), .i_address(addr), .i_write(write),
                 .o_data_out(rdata), .i_vblank(vblank), .i_int_active(int_active), .i_seq_busy(busy),
                 .i_seq_done(done), .i_seq_nack(nack), .i_seq_sent(sent), .i_seq_nacks(nacks),
                 .o_seq_start(seq_start), .o_irq(irq), .dbg_irq_en(d_en), .dbg_irq_pend(d_pend),
                 .dbg_vblank_prev(d_vprev), .dbg_int_prev(d_iprev), .dbg_seq_start_q(d_start));

`ifdef INITOFF
  localparam [0:0] INIT = 1'b0;
`else
  localparam [0:0] INIT = 1'b1;
`endif

  // Os registradores não têm valor inicial: o primeiro clock é um reset, como na placa.
  initial assume (reset);

  reg f_past = 0;
  reg [1:0] m_en = 0, m_pend = 0;
  reg m_vprev = 0, m_iprev = 0, m_start = 0;

  wire hit = !addr[10] && !addr[9];
  wire [8:0] idx = addr[8:0];
  wire wr_en = write && hit && idx == 10;
  wire wr_pend = write && hit && idx == 11;
  wire wr_ctrl = write && hit && idx == 12;
  wire [1:0] events = {int_active && !m_iprev, vblank && !m_vprev};
  wire [1:0] clear = wr_pend ? wdata[1:0] : 2'b00;

  always @(posedge clk) begin
    f_past <= 1;
    m_vprev <= reset ? 1'b0 : vblank;
    m_iprev <= reset ? 1'b0 : int_active;
    m_en <= reset ? 2'b00 : (wr_en ? wdata[1:0] : m_en);
    m_pend <= reset ? 2'b00 : ((m_pend & ~clear) | events);
    m_start <= !reset && wr_ctrl && wdata[0] && INIT;
  end

  // A palavra que o contrato diz que cada endereço lê.
  reg [31:0] want;
  always @* begin
    want = 32'h0;
    if (hit) case (idx)
      8: want = {22'h0, 1'b1, 1'b1, 8'd4};
      9: want = {27'h0, INIT, nack, done, busy, int_active};
      10: want = {30'h0, m_en};
      11: want = {30'h0, m_pend};
      13: want = {8'h0, 8'd4, nacks, sent};
      14: want = 32'd74250;
      default: want = 32'h0;
    endcase
  end

  always @(posedge clk) if (f_past) begin
    // 1. Os registradores são os do modelo.
    assert (d_en == m_en);
    assert (d_pend == m_pend);
    assert (d_vprev == m_vprev);
    assert (d_iprev == m_iprev);
    assert (d_start == m_start && seq_start == m_start);
    // 2. A interrupção é o OU das pendências habilitadas.
    assert (irq == |(m_pend & m_en));
    // 3. A leitura é a do contrato, e fora das palavras 8 a 14 vale zero.
    assert (rdata == want);
    if (!hit) assert (rdata == 0);
    // 4. Sem sequenciador o reinício nunca sai.
    if (!INIT) assert (!seq_start);
  end

`ifdef COVER
  always @(posedge clk) begin
    cover (f_past && irq && m_pend[0]);
    cover (f_past && irq && m_pend[1]);
    cover (f_past && wr_pend && wdata[0] && m_pend[0] && !events[0]);
    cover (f_past && m_en == 2'b11 && m_pend == 2'b11);
    cover (f_past && seq_start);
  end
`endif
endmodule
