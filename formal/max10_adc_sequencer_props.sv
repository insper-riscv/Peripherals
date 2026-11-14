// Propriedades do max10_adc_sequencer, verificadas na netlist Verilog que o GHDL sintetiza do VHDL. O pedido de
// início, a máscara (que muda a cada ciclo), o ready do núcleo e a resposta inteira (valid, canal e dado) são
// entradas livres, de modo que a prova cobre qualquer comportamento do núcleo, inclusive resposta antes do ready,
// de outro canal ou sem comando. Um modelo de referência guarda a máscara travada no início, os canais ainda sem
// amostra, o primeiro comando e se há um comando aceito à espera da resposta; a prova exige que as saídas sejam as
// do modelo.
module props (input clk);
  (* anyseq *) wire rst, start, ready, rvalid;
  (* anyseq *) wire [17:0] mask;
  (* anyseq *) wire [4:0] rchan;
  (* anyseq *) wire [11:0] rdata;
  wire cmd_valid, sop, eop, busy, done, svalid;
  wire [4:0] cmd_channel, schan;
  wire [11:0] sdata;

  max10_adc_sequencer dut (.i_clk(clk), .i_rst(rst), .i_start(start), .i_mask(mask), .o_cmd_valid(cmd_valid),
    .o_cmd_channel(cmd_channel), .o_cmd_sop(sop), .o_cmd_eop(eop), .i_cmd_ready(ready), .i_rsp_valid(rvalid),
    .i_rsp_channel(rchan), .i_rsp_data(rdata), .o_busy(busy), .o_done(done), .o_sample_valid(svalid),
    .o_sample_channel(schan), .o_sample_data(sdata));

  reg f_past = 0;
  // O modelo: varredura em curso, canais sem amostra, primeiro comando, comando aceito sem resposta e o último
  // canal que o sequenciador pediu.
  reg m_act = 0, m_first = 0, m_taken = 0;
  reg [17:0] m_pend = 0;
  reg [4:0] m_cur = 0;
  reg [4:0] m_n = 0;
  // Os valores da borda anterior.
  reg p_rst = 0, p_valid = 0, p_ready = 0, p_sop = 0, p_eop = 0;
  reg [4:0] p_chan = 0;

  wire [4:0] cur = cmd_valid ? cmd_channel : m_cur;
  wire taken_now = (cmd_valid && ready) || m_taken;
  wire in_range = cmd_channel < 5'd18;
  wire [17:0] below = (18'd1 << cmd_channel) - 18'd1;
  wire [17:0] others = m_pend & ~(18'd1 << cmd_channel);

  always @(posedge clk) begin
    f_past <= 1;
    p_rst <= rst;
    p_valid <= cmd_valid;
    p_ready <= ready;
    p_sop <= sop;
    p_eop <= eop;
    p_chan <= cmd_channel;
    if (cmd_valid) m_cur <= cmd_channel;
    if (rst) begin
      m_act <= 0; m_first <= 0; m_taken <= 0; m_pend <= 0; m_n <= 0;
    end else begin
      if (!m_act && start) begin
        m_act <= 1; m_first <= 1; m_pend <= mask; m_n <= 0;
      end
      if (m_act && done) m_act <= 0;
      if (svalid) begin
        m_pend[schan] <= 0; m_first <= 0; m_taken <= 0; m_n <= m_n + 5'd1;
      end else if (cmd_valid && ready) begin
        m_taken <= 1;
      end
    end
  end

  always @* if (!f_past) assume (rst);
`ifdef COVER
  // Para o cover, uma varredura de três canais e sem reset depois do primeiro.
  always @* if (f_past) assume (!rst && (m_act || mask == 18'h20021));
`endif

  always @(posedge clk) if (f_past) begin
    // 1. O ocupado é o da varredura do modelo, e depois de um reset o sequenciador está livre e calado.
    assert (busy == m_act);
    if (p_rst) assert (!busy && !cmd_valid && !done && !svalid);
    // 2. Um comando só existe numa varredura, para o menor canal ainda sem amostra, que está na máscara travada, e
    //    nunca com outro comando aceito à espera da resposta.
    if (cmd_valid) begin
      assert (m_act && in_range && m_pend[cmd_channel] && (m_pend & below) == 0 && !m_taken);
      // 3. O startofpacket marca o primeiro comando da varredura e o endofpacket o último canal pendente.
      assert (sop == m_first);
      assert (eop == (others == 0));
    end
    // 4. O comando fica válido, com o mesmo canal e os mesmos marcadores, até o ready.
    if (p_valid && !p_ready && !p_rst) assert (cmd_valid && cmd_channel == p_chan && sop == p_sop && eop == p_eop);
    // 5. Uma amostra só sai de uma resposta do canal pedido, com o comando já aceito (no ciclo do ready ou depois),
    //    e leva o canal e o dado da resposta.
    if (svalid) begin
      assert (rvalid && schan == rchan && sdata == rdata);
      assert (taken_now && schan == cur && schan < 5'd18 && m_pend[schan]);
    end
    // 6. E toda resposta do canal pedido a um comando aceito é tomada.
    if (m_act && taken_now && rvalid && rchan == cur) assert (svalid);
    // 7. O fim da varredura vem com todos os canais da máscara amostrados e nada em andamento.
    if (done) assert (m_act && m_pend == 0 && !taken_now && !cmd_valid && !svalid);
    if (m_taken) assert (m_act);
`ifdef COVER
    // Uma varredura de três canais termina; uma resposta chega depois do ready; uma resposta errada é ignorada.
    cover (done && m_n == 5'd3);
    cover (m_taken && svalid);
    cover (taken_now && rvalid && rchan != cur && !svalid);
    cover (cmd_valid && !ready && !rst);
`endif
  end
endmodule
