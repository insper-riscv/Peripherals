// Propriedades do sequenciador de inicialização do HDMI (hdmi_init_seq), verificadas na netlist Verilog que o
// GHDL sintetiza do VHDL, com a tabela de três entradas 9803, 0100 e AF16 (registrador e valor). O escritor
// I2C é livre: ele responde a cada pedido com um pulso de fim (e um bit de NACK) em qualquer ciclo depois do
// pedido, e nunca sem pedido pendente. O início (i_start) é livre.
//
// O modelo é uma lista ideal de três entradas: o índice avança a cada fim de escrita, o início só vale com a
// sequência parada, os contadores somam os fins e os NACK, e o estado concluído vale depois da última entrada.
//   -DAUTO    o sequenciador começa sozinho depois do reset (auto_start verdadeiro)
//   -DCOVER   alcança uma sequência completa com NACK e um reinício que a repete
module props (input clk);
  localparam N = 3;
  (* anyseq *) wire reset, start, wr_done, wr_nack;
  wire wr_start, busy, done, nack_seen;
  wire [7:0] wr_reg, wr_value, sent, nacks;

  hdmi_init_seq dut (.i_clk(clk), .i_rst(reset), .i_start(start), .o_wr_start(wr_start), .o_wr_reg(wr_reg),
                     .o_wr_value(wr_value), .i_wr_done(wr_done), .i_wr_nack(wr_nack), .o_busy(busy), .o_done(done),
                     .o_nack_seen(nack_seen), .o_sent(sent), .o_nacks(nacks));

  // Os registradores não têm valor inicial: o primeiro clock é um reset, como na placa. O reset não volta depois.
  reg f_past = 0;
  initial assume (reset);
  always @(posedge clk) if (f_past) assume (!reset);

  // A entrada de índice i da tabela.
  function [15:0] entry(input [7:0] i);
    case (i)
      0: entry = 16'h9803;
      1: entry = 16'h0100;
      default: entry = 16'hAF16;
    endcase
  endfunction

  // Escritor ideal: um pedido pendente desde o ciclo seguinte ao pedido, e o fim só com pedido pendente.
  reg pending = 0;
  always @(posedge clk) pending <= !reset && (wr_start || (pending && !wr_done));
  always @(posedge clk) assume (!wr_done || pending);

  // Modelo da sequência.
  reg m_active = 0, m_done = 0;
  reg [7:0] m_idx = 0, m_sent = 0, m_nacks = 0;
  reg wr_start_prev = 0;
  always @(posedge clk) begin
    f_past <= 1;
    wr_start_prev <= wr_start;
    if (reset) begin
      m_idx <= 0; m_sent <= 0; m_nacks <= 0;
`ifdef AUTO
      m_active <= 1; m_done <= 0;
`else
      m_active <= 0; m_done <= 0;
`endif
    end else if (!m_active) begin
      if (start) begin
        m_idx <= 0; m_sent <= 0; m_nacks <= 0; m_active <= 1; m_done <= 0;
      end
    end else if (wr_done) begin
      m_sent <= m_sent + 1;
      m_nacks <= m_nacks + wr_nack;
      if (m_idx == N - 1) begin
        m_active <= 0; m_done <= 1;
      end else begin
        m_idx <= m_idx + 1;
      end
    end
  end

  always @(posedge clk) if (f_past) begin
    // 1. O estado, os contadores e o aviso de NACK são os do modelo.
    assert (busy == m_active);
    assert (done == m_done);
    assert (sent == m_sent);
    assert (nacks == m_nacks);
    assert (nack_seen == (m_nacks != 0));
    // 2. Concluído e ocupado são exclusivos, e concluído só depois de todas as entradas.
    assert (!(busy && done));
    if (done) assert (sent == N);
    assert (sent <= N);
    // 3. Um pedido de escrita vem só com a sequência em andamento e sem outro pedido pendente, dura um ciclo
    //    e leva o registrador e o valor da entrada atual da tabela.
    if (wr_start) begin
      assert (busy);
      assert (!pending);
      assert (!wr_start_prev);
      assert ({wr_reg, wr_value} == entry(m_idx));
    end
    // 4. Com a sequência parada, nenhum pedido sai.
    if (!busy) assert (!wr_start);
  end

`ifdef COVER
  reg seen_done = 0, seen_nack_done = 0;
  always @(posedge clk) begin
    if (f_past && done) seen_done <= 1;
    if (f_past && done && nack_seen) seen_nack_done <= 1;
    // Uma sequência completa com NACK e, depois, uma segunda sequência completa.
    cover (f_past && seen_nack_done && busy && sent == 2);
    cover (f_past && seen_done && done && sent == N && nacks == 0);
  end
`endif
endmodule
