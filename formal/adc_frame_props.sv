// Propriedades do quadro dos controladores de conversor A/D (adc128s022 e, com -DLTC, ltc2308), verificadas na
// netlist Verilog que o GHDL sintetiza do VHDL, com o barramento e o dado do chip livres. O primeiro clock e um
// reset. O pedido do quadro, o canal e a conclusao sao lidos de sinais expostos do controlador (dbg_*); o quadro e o
// intervalo entre o pedido e o pulso de conclusao.
//   ADC128S022  A selecao de chip fica em nivel baixo no quadro todo e alta fora dele, SCLK fica em nivel alto no
//               repouso (modo 3), o quadro tem 16 bordas de descida e de subida, e o endereco do canal sai em
//               ADC_SADDR nos bits 13:11 da palavra de 16 bits amostrada nas bordas de subida.
//   LTC2308     CONVST fica alto exatamente CONVST ciclos, SCK so sobe depois de CONV ciclos da queda de CONVST, e
//               fica em nivel baixo no repouso (modo 0), o quadro tem 12 bordas de subida e de descida, e a
//               configuracao S/D, O/S, S1, S0, UNI e SLP do canal sai em ADC_SDI nos 6 primeiros bits.
//   Nos dois a conclusao do quadro e um pulso unico, depois do ultimo clock.
`ifndef CONVST
`define CONVST 3
`endif
`ifndef CONV
`define CONV 5
`endif
module props (input clk);
  (* anyseq *) wire rst, we, miso;
  (* anyseq *) wire [3:0] adr;
  (* anyseq *) wire [31:0] wdata;
  wire [31:0] rdata;
  wire irq, sclk, mosi, line;
  wire dbg_frame_start, dbg_frame_done;
  wire [2:0] dbg_frame_ch;

`ifdef LTC
  ltc2308 dut (.i_clk(clk), .i_rst(rst), .i_data_in(wdata), .i_address(adr), .i_write(we), .o_data_out(rdata),
    .o_irq(irq), .o_adc_convst(line), .o_adc_sck(sclk), .o_adc_sdi(mosi), .i_adc_sdo(miso),
    .dbg_frame_start(dbg_frame_start), .dbg_frame_done(dbg_frame_done), .dbg_frame_ch(dbg_frame_ch));
  localparam NBITS = 12;
  localparam IDLE_SCLK = 0;
  localparam IDLE_LINE = 0;
`else
  adc128s022 dut (.i_clk(clk), .i_rst(rst), .i_data_in(wdata), .i_address(adr), .i_write(we), .o_data_out(rdata),
    .o_irq(irq), .o_adc_cs_n(line), .o_adc_sclk(sclk), .o_adc_saddr(mosi), .i_adc_sdat(miso),
    .dbg_frame_start(dbg_frame_start), .dbg_frame_done(dbg_frame_done), .dbg_frame_ch(dbg_frame_ch));
  localparam NBITS = 16;
  localparam IDLE_SCLK = 1;
  localparam IDLE_LINE = 1;
`endif

  reg f_past = 0, in_frame = 0;
  reg p_line = IDLE_LINE, p_sclk = IDLE_SCLK, p_mosi = 0, p_done = 0;
  reg [2:0] ch = 0;
  reg [5:0] rises = 0, falls = 0, hi_cycles = 0, since_fall = 0;
  reg [15:0] word = 0;

  always @* if (!f_past) assume (rst);

  wire rise = sclk && !p_sclk;
  wire fall = !sclk && p_sclk;

`ifdef LTC
  wire [5:0] cfg = {1'b1, ch[0], ch[2], ch[1], 1'b1, 1'b0};
  wire [15:0] want_word = {4'b0, cfg, 6'b0};
`else
  wire [15:0] want_word = {2'b00, ch, 11'b0};
`endif

  always @(posedge clk) begin
    f_past <= 1;
    p_line <= line; p_sclk <= sclk; p_mosi <= mosi; p_done <= dbg_frame_done;
    if (rst) begin
      in_frame <= 0; p_line <= IDLE_LINE; p_sclk <= IDLE_SCLK; p_done <= 0; rises <= 0; falls <= 0; hi_cycles <= 0;
      since_fall <= 6'd63;
    end else if (dbg_frame_start) begin
      in_frame <= 1; ch <= dbg_frame_ch; rises <= 0; falls <= 0; word <= 0; hi_cycles <= 0; since_fall <= 0;
    end else begin
      if (dbg_frame_done) in_frame <= 0;
      if (in_frame && rise) begin rises <= rises + 1; word <= {word[14:0], p_mosi}; end
      if (in_frame && fall) falls <= falls + 1;
      if (line) hi_cycles <= hi_cycles + 1;
      if (!line && p_line) since_fall <= 0; else if (since_fall != 6'd63) since_fall <= since_fall + 1;
    end
  end

  always @(posedge clk) if (f_past) begin
    // 1. O clock fica em repouso fora do quadro e a conclusao e um pulso unico.
    if (!in_frame && !dbg_frame_start) assert (sclk == IDLE_SCLK);
    if (dbg_frame_done) assert (!p_done && in_frame);
    // 2. O quadro tem NBITS bordas de subida e de descida, e o canal sai nos bits do endereco ou da configuracao.
    if (dbg_frame_done) begin
      assert (rises == NBITS && falls == NBITS);
      assert (word[NBITS-1:0] == want_word[NBITS-1:0]);
    end
`ifdef LTC
    // 3. CONVST sobe so no quadro e fica alto exatamente CONVST ciclos; SCK so sobe CONV ciclos depois da queda.
    if (!in_frame && !dbg_frame_start) assert (!line);
    if (!line && p_line) assert (hi_cycles == `CONVST);
    if (rise && rises == 0) assert (!line && since_fall >= `CONV);
`else
    // 3. A selecao de chip fica baixa durante o quadro e alta fora dele.
    if (!in_frame) assert (line);
    if (in_frame && !dbg_frame_done) assert (!line);
    if (dbg_frame_done) assert (line);
`endif
  end

`ifdef COVER
  always @(posedge clk) if (f_past) cover (dbg_frame_done && rises == NBITS);
`endif
endmodule
