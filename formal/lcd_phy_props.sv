// Propriedades do lcd_phy, verificadas na netlist Verilog que o GHDL sintetiza do VHDL, com setup de 2 ciclos,
// pulso de 3, hold de 2 e tempo limite de 8 ciclos. O pedido, o dado, o atraso (de 0 a 3 ciclos) e o modo de
// espera são livres; o flag de ocupado é livre, constante em zero (BUSY0) ou constante em um (BUSY1). O primeiro
// clock é um reset, como na placa, e as propriedades valem a partir dele.
//   1. O barramento nunca tem conflito: o driver de dados só liga com RW baixo, e RW alto só vem com RS baixo e
//      driver solto. RS, RW, dado e habilitação ficam parados enquanto EN está alto.
//   2. Antes de EN subir, RS, RW e o dado estão estáveis há pelo menos o tempo de setup; depois de EN descer,
//      ficam estáveis pelo tempo de hold; EN fica alto exatamente o tempo do pulso.
//   3. Uma escrita apresenta o RS e o byte do pedido aceito, e uma operação sem leitura do ocupado devolve a
//      camada ao repouso depois de exatamente setup + pulso + hold + atraso ciclos.
//   4. Com o ocupado em zero a leitura é única e a operação dura o dobro da fase de escrita, sem tempo limite;
//      com o ocupado em um o tempo limite acende e a camada volta ao repouso. O tempo limite nunca acende sem
//      leitura do ocupado.
//   5. O reset leva a camada ao repouso com todos os pinos baixos e o driver solto.
`define S 2
`define P 3
`define H 2
module props (input clk);
  (* anyseq *) wire reset, start, rs, poll;
  (* anyseq *) wire [7:0] data;
  (* anyseq *) wire [23:0] dly;
  wire ready, timeout, o_rs, o_rw, o_en, oe;
  wire [7:0] o_data;
`ifdef BUSY0
  wire busy = 1'b0;
`elsif BUSY1
  wire busy = 1'b1;
`else
  (* anyseq *) wire busy;
`endif

  lcd_phy dut (.i_clk(clk), .i_rst(reset), .i_start(start), .i_rs(rs), .i_data(data), .i_poll(poll),
    .i_delay(dly), .i_busy_flag(busy), .o_ready(ready), .o_timeout(timeout), .o_lcd_rs(o_rs), .o_lcd_rw(o_rw),
    .o_lcd_en(o_en), .o_lcd_data(o_data), .o_lcd_data_oe(oe));

  reg f_hist = 0;
  reg f_past = 0;
  initial assume (reset);
  always @(posedge clk) begin
    f_past <= 1;
    f_hist <= f_past;
    if (f_past) assume (!reset);
  end
  always @(*) assume (dly <= 3);

  wire accept = start && ready && f_past;

  // Valores do pedido aceito e quantos ciclos se passaram desde ele.
  reg m_rs = 0, m_poll = 0, m_busy_op = 0;
  reg [7:0] m_data = 0;
  reg [23:0] m_dly = 0;
  reg [7:0] age = 0;
  reg seen_read = 0;
  always @(posedge clk) begin
    if (accept) begin
      m_rs <= rs; m_data <= data; m_poll <= poll; m_dly <= dly; m_busy_op <= 1; age <= 0; seen_read <= 0;
    end else begin
      if (ready) m_busy_op <= 0;
      if (!ready) age <= age + 1;
    end
    if (o_en && o_rw) seen_read <= 1;
  end

  // Histórico dos pinos de controle.
  reg p_en = 0, p_rs = 0, p_rw = 0, p_oe = 0;
  reg [7:0] p_data = 0;
  reg [3:0] stable = 0, since_fall = 15, high = 0;
  wire same = (o_rs == p_rs) && (o_rw == p_rw) && (oe == p_oe) && (o_data == p_data);
  always @(posedge clk) begin
    p_en <= o_en; p_rs <= o_rs; p_rw <= o_rw; p_oe <= oe; p_data <= o_data;
    stable <= same ? (stable == 15 ? 15 : stable + 1) : 0;
    if (f_hist && p_en && !o_en) since_fall <= 0; else if (since_fall != 15) since_fall <= since_fall + 1;
    high <= o_en ? high + 1 : 0;
  end

  always @(posedge clk) if (f_hist) begin
    assert (!(oe && o_rw));
    assert (!o_rw || (!o_rs && !oe));
    if (o_en && p_en) assert (same);
    // Setup: na subida de EN as linhas estão paradas há S ciclos (S - 1 comparações iguais seguidas).
    if (o_en && !p_en) assert (stable >= `S - 1);
    // Hold: depois da descida, as linhas ficam paradas por H ciclos.
    if (!o_en && p_en) assert (same);
    if (!o_en && since_fall < `H - 1 && !p_en) assert (same);
    if (!o_en && p_en) assert (high == `P);
    // A escrita apresenta o pedido aceito.
    if (o_en && !o_rw) begin
      assert (o_rs == m_rs);
      assert (o_data == m_data);
      assert (oe);
    end
    // Sem leitura do ocupado, a operação dura setup + pulso + hold + atraso ciclos.
    if (ready && m_busy_op && !m_poll && age != 0) assert (age == `S + `P + `H + m_dly[1:0]);
    if (timeout) assert (seen_read);
`ifdef BUSY1
    if (ready && m_busy_op && m_poll && age != 0) assert (age == 3 * (`S + `P + `H));
    assert (!(m_busy_op && m_poll && !ready && age > 3 * (`S + `P + `H)));
`endif
`ifdef BUSY0
    assert (!timeout);
    if (ready && m_busy_op && m_poll && age != 0) assert (age == 2 * (`S + `P + `H));
`endif
  end

  // Depois do reset a camada está em repouso.
  reg p_reset = 0;
  always @(posedge clk) begin
    p_reset <= reset;
    if (f_past && p_reset) begin
      assert (ready);
      assert (!o_en && !o_rw && !oe && !timeout);
    end
  end

`ifdef COVER
  always @(posedge clk) if (f_past) begin
    cover (o_en && !o_rw && m_rs && m_data == 8'hA5);
    cover (o_en && o_rw);
    cover (timeout);
    cover (ready && m_busy_op && !m_poll && age != 0 && m_dly == 3);
  end
`endif
endmodule
