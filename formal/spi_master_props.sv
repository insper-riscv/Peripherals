// Propriedades do spi_master (mestre SPI de uma palavra, quatro modos), verificadas na netlist Verilog que o GHDL
// sintetiza do VHDL, com palavras de ate 4 bits e divisor de 2 bits. Todas as entradas sao livres (modo, largura,
// ordem, divisor, dado, MISO e pedido de inicio). O primeiro clock e um reset, como na placa.
//   MASTER  Em repouso SCLK segue CPOL e MOSI fica em nivel alto; o fim da palavra e um pulso unico no ciclo em que
//           o mestre desocupa; a palavra tem exatamente 2 * n bordas de SCLK, separadas por divisor + 1 ciclos, e
//           termina com SCLK em CPOL; o bit de MOSI na borda de amostra e o bit k da palavra na ordem pedida (CPHA
//           0 e 1); a palavra recebida e a amostra de MISO nas bordas de amostra, na ordem pedida; o driver de MOSI
//           segue o pedido de escuta capturado no inicio.
`ifndef WBITS
`define WBITS 4
`endif
module props (input clk);
  (* anyseq *) wire rst, cpol, cpha, lsb, drive_in, start, miso;
  (* anyseq *) wire [5:0] wbits;
  (* anyseq *) wire [1:0] div;
  (* anyseq *) wire [`WBITS-1:0] txd;
  wire busy, done, sclk, mosi, oe;
  wire [`WBITS-1:0] rxd;

  spi_master dut (.i_clk(clk), .i_rst(rst), .i_cpol(cpol), .i_cpha(cpha), .i_lsb_first(lsb), .i_word_bits(wbits),
    .i_divider(div), .i_tx_drive(drive_in), .i_start(start), .i_tx_data(txd), .o_busy(busy), .o_done(done),
    .o_rx_data(rxd), .o_sclk(sclk), .o_mosi(mosi), .o_mosi_oe(oe), .i_miso(miso));

  reg f_past = 0;
  // Entradas e saidas do ciclo anterior.
  reg p_rst = 0, p_cpol = 0, p_start = 0, p_miso = 0, p_busy = 0, p_sclk = 0, p_mosi = 1, p_done = 0;
  reg [5:0] p_wbits = 0;
  reg [1:0] p_div = 0;
  reg [`WBITS-1:0] p_txd = 0;
  reg p_cpha = 0, p_lsb = 0, p_drive = 0;
  // Configuracao capturada no inicio da palavra, contagens e amostras.
  reg c_cpol = 0, c_cpha = 0, c_lsb = 0, c_drive = 1;
  reg [2:0] c_n = 1;
  reg [1:0] c_div = 0;
  reg [`WBITS-1:0] c_tx = 0;
  reg [4:0] edges = 0;
  reg [3:0] trails = 0;
  reg [3:0] since = 0;
  reg [`WBITS-1:0] rxbits = 0;

  function [2:0] clamp (input [5:0] w);
    clamp = (w == 0) ? 3'd1 : (w > `WBITS) ? `WBITS : w[2:0];
  endfunction

  wire rise_busy = !p_busy && busy;
  wire toggled = p_busy && (sclk != p_sclk);
  wire trail = toggled && (sclk == c_cpol);
  wire [4:0] edges_now = edges + toggled;
  wire [3:0] trails_now = trails + trail;
  // Bit k da palavra na ordem de transmissao.
  wire [3:0] k = trails;
  wire [3:0] pos = c_lsb ? k : ({1'b0, c_n} - 4'd1 - k);
  wire exp_bit = c_tx[pos];
  // Palavra recebida esperada: o bit amostrado k vai para a posicao k (LSB primeiro) ou n-1-k (MSB primeiro).
  reg [`WBITS-1:0] rx_want;
  reg [`WBITS-1:0] rx_samples;
  integer i;
  always @* begin
    rx_samples = rxbits;
    if (trail) rx_samples[k] = p_miso;
    rx_want = 0;
    for (i = 0; i < `WBITS; i = i + 1)
      if (i < c_n) rx_want[c_lsb ? i : (c_n - 1 - i)] = rx_samples[i];
  end

  always @* if (!f_past) assume (rst);

  always @(posedge clk) begin
    f_past <= 1;
    p_rst <= rst; p_cpol <= cpol; p_start <= start; p_miso <= miso; p_busy <= busy; p_sclk <= sclk;
    p_mosi <= mosi; p_done <= done; p_wbits <= wbits; p_div <= div; p_txd <= txd; p_cpha <= cpha; p_lsb <= lsb;
    p_drive <= drive_in;
    if (p_rst) begin
      c_drive <= 1; edges <= 0; trails <= 0; since <= 0; rxbits <= 0;
    end else if (rise_busy) begin
      c_cpol <= p_cpol; c_cpha <= p_cpha; c_lsb <= p_lsb; c_drive <= p_drive; c_n <= clamp(p_wbits);
      c_div <= p_div; c_tx <= p_txd; edges <= 0; trails <= 0; since <= 0; rxbits <= 0;
    end else begin
      edges <= edges_now; trails <= trails_now;
      if (toggled) since <= 0; else if (p_busy) since <= since + 1;
      if (trail) rxbits[k] <= p_miso;
    end
  end

  always @(posedge clk) if (f_past) begin
    // 1. Em repouso SCLK segue a entrada CPOL do ciclo anterior, e depois do reset tambem.
    if (!p_busy || p_rst) assert (sclk == p_cpol);
    // 2. O mestre so ocupa por pedido de inicio, e o pulso de fim e exatamente a queda de busy.
    if (rise_busy) assert (p_start && !p_rst);
    if (!p_rst) assert (done == (p_busy && !busy));
    if (done) assert (!p_done);
    if (p_rst) assert (!busy && !done);
    // 3. MOSI fica em nivel alto fora da palavra (um ciclo depois do fim).
    if (!busy && !p_busy) assert (mosi);
    if (!p_rst && p_busy && busy) begin
      // 4. SCLK so se move a cada divisor + 1 ciclos, e a primeira borda e a leading.
      if (toggled) assert (since == {2'b0, c_div});
      if (toggled && edges == 0) assert (sclk != c_cpol);
      // 5. O bit de MOSI na borda de amostra e o bit k da palavra, nos dois modos de fase.
      if (trail) assert (p_mosi == exp_bit);
    end
    if (!p_rst && p_busy && !busy) begin
      // O ultimo ciclo da palavra: borda de amostra do ultimo bit, 2 * n bordas, SCLK em repouso, dado recebido.
      assert (trail && trails == {1'b0, c_n} - 4'd1 && edges_now == {c_n, 1'b0});
      assert (sclk == c_cpol);
      assert (p_mosi == exp_bit);
      assert (rxd == rx_want);
      assert (since == {2'b0, c_div});
    end
    if (!p_rst && p_busy && busy) assert (edges_now <= {c_n, 1'b0});
    // 6. O driver de MOSI segue o pedido capturado e fica onde esta depois da palavra.
    if (!p_rst && p_busy) assert (oe == c_drive);
    if (!p_rst && !p_busy && !busy) assert (oe == c_drive);
  end

`ifdef COVER
  always @(posedge clk) if (f_past) begin
    cover (done && !c_cpha && !c_cpol && !c_lsb && c_n == 3'd4);
    cover (done && c_cpha && c_cpol && c_lsb && c_n == 3'd3);
    cover (done && c_cpha && !c_cpol && !c_lsb && !c_drive);
    cover (done && !c_cpha && c_cpol && c_n == 3'd1);
  end
`endif
endmodule
