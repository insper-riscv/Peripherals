// Propriedades do sequenciador do adxl345 (configuracao e leitura dos eixos por SPI), verificadas na netlist
// Verilog que o GHDL sintetiza do VHDL, com MISO, INT1 e o barramento livres, exceto que a unica escrita permitida
// e a de CONTROL no segundo ciclo (ENABLE e USE_INT1 ligados, o resto livre), para que as transacoes sigam uma
// configuracao fixa. O primeiro clock e um reset. Com divisor zero e intervalo de selecao de 3 ciclos, a
// configuracao e uma leitura dos eixos cabem em 380 ciclos.
//   SEQ  As transacoes saem na ordem (DEVID, BW_RATE, DATA_FORMAT, INT_ENABLE, POWER_CTL, leitura dos eixos), cada
//        uma entre uma queda e uma subida da selecao de chip, com SCLK em nivel alto no repouso (modo 3); os
//        comandos e os bytes escritos sao os do contrato (DATA_FORMAT com o bit SPI ligado so nos tres fios, o codigo
//        de taxa, a faixa e a resolucao plena do CONTROL); cada escrita tem 2 bytes e a leitura dos eixos tem 1
//        comando e 6 bytes, em rajada; o driver de MOSI fica ligado nos comandos e nos bytes escritos e solto nos
//        bytes lidos; a selecao de chip fica alta pelo menos 3 ciclos entre transacoes.
`ifndef THREE
`define THREE 1
`endif
module props (input clk);
  (* anyseq *) wire rst, we, miso, int1;
  (* anyseq *) wire [2:0] adr;
  (* anyseq *) wire [31:0] wdata;
  wire [31:0] rdata;
  wire irq, cs_n, sclk, mosi, oe;

  adxl345 dut (.i_clk(clk), .i_rst(rst), .i_data_in(wdata), .i_address(adr), .i_write(we), .o_data_out(rdata),
    .o_irq(irq), .o_adxl_cs_n(cs_n), .o_adxl_sclk(sclk), .o_adxl_mosi(mosi), .o_adxl_mosi_oe(oe),
    .i_adxl_miso(miso), .i_adxl_int1(int1));

  reg f_past = 0;
  reg [1:0] cyc = 0;
  reg p_cs = 1, p_sclk = 1, p_mosi = 1, p_oe = 1;
  reg [3:0] rate = 0;
  reg [1:0] range = 0;
  reg full = 0;
  reg [3:0] txn = 0;
  reg [6:0] rises = 0;
  reg [7:0] shift = 0;
  reg [7:0] b0 = 0, b1 = 0;
  reg [3:0] hi = 0;
  reg started = 0;

  always @* if (!f_past) assume (rst);
  always @* if (f_past) assume (!rst);
  // A unica escrita e a de CONTROL no segundo ciclo, com ENABLE e USE_INT1.
  always @* assume (!we || (cyc == 1 && adr == 3'd4 && wdata[0] && wdata[5]));

  wire rise = sclk && !p_sclk;
  wire cs_fall = !cs_n && p_cs;
  wire cs_rise = cs_n && !p_cs;
  wire [7:0] cur_byte = {shift[6:0], p_mosi};
  wire [2:0] byte_no = rises[5:3];
  wire last_rise_of_byte = rise && rises[2:0] == 3'd7;
  wire [7:0] want_cmd = (txn == 0) ? 8'h80 : (txn == 1) ? 8'h2C : (txn == 2) ? 8'h31 : (txn == 3) ? 8'h2E :
                        (txn == 4) ? 8'h2D : 8'hF2;
  wire [7:0] want_b1 = (txn == 1) ? {4'b0, rate} : (txn == 2) ? {1'b0, `THREE ? 1'b1 : 1'b0, 2'b00, full, 1'b0, range}
                       : (txn == 3) ? 8'h80 : 8'h08;

  always @(posedge clk) begin
    f_past <= 1;
    if (rst) begin
      cyc <= 0; p_cs <= 1; p_sclk <= 1; p_mosi <= 1; p_oe <= 1; txn <= 0; started <= 0; rises <= 0; shift <= 0; hi <= 0;
    end else begin
    if (cyc != 2'd3) cyc <= cyc + 1;
    p_cs <= cs_n; p_sclk <= sclk; p_mosi <= mosi; p_oe <= oe;
    if (we && cyc == 1) begin rate <= wdata[11:8]; range <= wdata[3:2]; full <= wdata[4]; end
    if (cs_n) begin if (hi != 4'd15) hi <= hi + 1; end else hi <= 0;
    if (cs_fall) begin
      if (started) txn <= (txn == 4'd5) ? 4'd5 : txn + 1;
      started <= 1; rises <= 0; shift <= 0;
    end
    if (!cs_n && rise) begin
      rises <= rises + 1; shift <= cur_byte;
      if (byte_no == 0 && rises[2:0] == 3'd7) b0 <= cur_byte;
      if (byte_no == 1 && rises[2:0] == 3'd7) b1 <= cur_byte;
    end
    end
  end

  always @(posedge clk) if (f_past) begin
    // 1. SCLK fica em nivel alto com a selecao de chip alta, e a selecao fica alta pelo menos 3 ciclos entre quadros.
    if (cs_n && p_cs) assert (sclk);
    if (cs_fall && started) assert (hi >= 4'd3);
    // 2. Cada transacao e a n-esima, com o comando e o byte escrito do contrato e o numero de bytes certo.
    if (cs_rise && started) begin
      assert (b0 == want_cmd);
      if (txn == 5) assert (rises == 7'd56);
      else assert (rises == 7'd16);
      if (txn >= 1 && txn <= 4) assert (b1 == want_b1);
    end
    // 3. O driver de MOSI: ligado no comando e nos bytes escritos, solto nos bytes lidos.
    if (!cs_n && rise && started) begin
      if (byte_no == 0) assert (p_oe);
      else if (txn >= 1 && txn <= 4) assert (p_oe);
      else assert (!p_oe);
    end
  end

`ifdef COVER
  always @(posedge clk) if (f_past) begin
    cover (cs_rise && txn == 1 && rises == 7'd16);
    cover (cs_rise && txn == 2);
  end
`endif
endmodule
