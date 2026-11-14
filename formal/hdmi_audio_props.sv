// Propriedades do hdmi_audio, verificadas na netlist Verilog que o GHDL sintetiza do VHDL. A instância tem o clock do
// sistema com o dobro da frequência do MCLK, de modo que o clock mestre inverte a cada ciclo e a conta é exata em
// ciclos: o MCLK tem período de 2 ciclos, e o início automático liga clocks, reprodução e tom sem escrita no
// barramento (as entradas do barramento valem zero). RATIO é a razão MCLK/LRCLK da instância (128 ou 256). Todas as
// medidas são feitas só nas saídas o_mclk, o_sclk, o_lrclk e o_i2s0, entre duas trocas consecutivas do LRCLK:
//   1. O MCLK sobe RATIO / 2 vezes, uma por canal de LRCLK que dura RATIO / 2 períodos de MCLK.
//   2. O SCLK sobe 32 vezes, os 32 ciclos de SCLK do slot de cada canal.
//   3. O semiciclo do LRCLK dura RATIO ciclos do sistema.
//   4. Entre duas subidas consecutivas do SCLK, o MCLK sobe RATIO / 64 vezes.
//   5. O dado serial só muda no ciclo seguinte a uma descida do SCLK, nunca na subida, onde o receptor amostra.
//   6. A primeira troca do LRCLK leva o nível do canal esquerdo ('0') ao do direito, e duas trocas ocorrem até o limite.
// -DCOVER alcança três trocas do LRCLK com a subida do SCLK e a mudança do dado.
module props (input clk);
  localparam RATIO = `RATIO;
  localparam SLOT = 32;
  (* anyseq *) wire reset;
  wire mclk, sclk, lrclk, i2s0, irq;
  wire [31:0] data_out;

  hdmi_audio dut (.i_clk(clk), .i_rst(reset), .i_write(1'b0), .i_read(1'b0), .i_address(4'd0), .i_data_in(32'd0),
                  .o_data_out(data_out), .o_irq(irq), .o_mclk(mclk), .o_sclk(sclk), .o_lrclk(lrclk), .o_i2s0(i2s0));

  // O primeiro clock é um reset, como na placa; as propriedades valem a partir dele.
  reg f_past = 0, f_ready = 0;
  initial assume (reset);
  always @(posedge clk) if (f_past) assume (!reset);

  // Valores dos ciclos anteriores (o segundo atraso do SCLK serve à propriedade 5).
  reg mclk_p = 0, sclk_p = 0, sclk_pp = 0, lrclk_p = 0, i2s0_p = 0;
  // Subidas de MCLK e de SCLK e ciclos desde a última troca do LRCLK; trocas vistas; subidas de MCLK desde o SCLK.
  reg [15:0] m_rise = 0, s_rise = 0, cyc = 0, m_since_s = 0, total = 0;
  reg [3:0] toggles = 0;
  reg s_seen = 0;

  wire m_up = f_ready && mclk && !mclk_p;
  wire s_up = f_ready && sclk && !sclk_p;
  wire l_toggle = f_ready && (lrclk != lrclk_p);

  always @(posedge clk) begin
    f_past <= 1;
    f_ready <= f_past;
    mclk_p <= mclk; sclk_p <= sclk; sclk_pp <= sclk_p; lrclk_p <= lrclk; i2s0_p <= i2s0;
    total <= total + 1;
    if (l_toggle) begin
      toggles <= toggles + 1;
      m_rise <= m_up; s_rise <= s_up; cyc <= 1;
    end else begin
      m_rise <= m_rise + m_up; s_rise <= s_rise + s_up; cyc <= cyc + 1;
    end
    if (s_up) begin
      m_since_s <= m_up; s_seen <= 1;
    end else begin
      m_since_s <= m_since_s + m_up;
    end
  end

  always @(posedge clk) if (f_ready) begin
    // 1 a 3: a janela entre duas trocas, que só existe a partir da segunda.
    if (l_toggle && toggles >= 1) begin
      assert (m_rise == RATIO / 2);
      assert (s_rise == SLOT);
      assert (cyc == RATIO);
    end
    // 4: o SCLK sobe a cada RATIO / 64 períodos de MCLK, desde a segunda subida.
    if (s_up && s_seen) assert (m_since_s == RATIO / 64);
    // 5: o dado muda só um ciclo depois de uma descida do SCLK e nunca em uma subida.
    if (i2s0 != i2s0_p) assert (!sclk && !sclk_p && sclk_pp);
    // 6: a primeira troca é a do fim do canal esquerdo, do nível baixo para o alto.
    if (l_toggle && toggles == 0) assert (lrclk);
    // Vivacidade limitada: com o tempo de três semiciclos e o atraso de partida, já ocorreram duas trocas.
    if (total == 4 * RATIO) assert (toggles >= 2);
  end

`ifdef COVER
  always @(posedge clk) if (f_past) begin
    cover (toggles == 3 && s_up);
    cover (toggles == 3 && i2s0 != i2s0_p);
  end
`endif
endmodule
