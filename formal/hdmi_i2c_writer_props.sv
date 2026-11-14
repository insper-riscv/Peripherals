// Propriedades do escritor I2C do HDMI (hdmi_i2c_writer), verificadas na netlist Verilog que o GHDL sintetiza
// do VHDL, com um quarto de bit de dois ciclos (clk_freq 8, i2c_freq 1) para a transação inteira caber no
// limite da prova. A entrada SDA, o registrador, o valor e o pedido de início são livres.
//
// Uma transação de escrita tem 27 pulsos de SCL (três bytes e três confirmações) mais o pulso da condição de
// parada. A prova mede, sobre os pinos de dreno aberto, que:
//   - as saídas de valor são sempre zero e o barramento fica livre com o escritor parado;
//   - SDA só muda com SCL alta na condição de partida (antes do primeiro pulso) e na de parada (depois do
//     pulso 27), e nunca durante um bit de dado;
//   - nas confirmações (pulsos 9, 18 e 27) o escritor mantém SDA liberada com SCL alta;
//   - o fim da transação sai depois do pulso da parada, dura um ciclo e deixa o escritor livre.
//   -DCOVER  alcança o fim de uma transação, com e sem NACK
module props (input clk);
  (* anyseq *) wire reset, start, sda_in;
  (* anyseq *) wire [7:0] reg_in, val_in;
  wire busy, done, nack, sda_out, sda_oe, scl_out, scl_oe;

  hdmi_i2c_writer dut (.i_clk(clk), .i_rst(reset), .i_start(start), .i_reg(reg_in), .i_value(val_in), .o_busy(busy),
                       .o_done(done), .o_nack(nack), .i_sda(sda_in), .o_sda_out(sda_out), .o_sda_oe(sda_oe),
                       .o_scl_out(scl_out), .o_scl_oe(scl_oe));

  // Os registradores não têm valor inicial: o primeiro clock é um reset, como na placa. O reset não volta depois.
  reg f_past = 0;
  initial assume (reset);
  always @(posedge clk) if (f_past) assume (!reset);

  // Pulsos de SCL liberada vistos na transação atual, e os valores do ciclo anterior.
  reg [7:0] pulses = 0;
  reg scl_prev = 1, sda_prev = 0, busy_prev = 0, done_prev = 0;
  wire scl_rise = scl_prev && !scl_oe;
  always @(posedge clk) begin
    f_past <= 1;
    scl_prev <= scl_oe;
    sda_prev <= sda_oe;
    busy_prev <= busy;
    done_prev <= done;
    if (busy && !busy_prev) pulses <= 0;
    else if (scl_rise) pulses <= pulses + 1;
  end

  always @(posedge clk) if (f_past) begin
    // 1. O escritor só solta ou puxa a linha para zero.
    assert (!sda_out && !scl_out);
    // 2. Parado, o barramento fica livre.
    if (!busy) assert (!sda_oe && !scl_oe);
    // 3. SDA muda com SCL alta (estável) só na partida e na parada.
    if (!scl_oe && !scl_prev && sda_oe != sda_prev) begin
      assert ((sda_oe && pulses == 0) || (!sda_oe && pulses == 28));
    end
    // 4. Nas confirmações o escritor não puxa SDA enquanto SCL está alta.
    if (!scl_oe && !scl_prev && busy && (pulses == 9 || pulses == 18 || pulses == 27)) assert (!sda_oe);
    // 5. O fim vem depois do pulso da parada, dura um ciclo e deixa o escritor livre.
    if (done) begin
      assert (pulses == 28);
      assert (!busy);
      assert (!done_prev);
    end
    // 6. O pulso de fim só vem de uma transação em andamento.
    if (done) assert (busy_prev);
  end

`ifdef COVER
  always @(posedge clk) begin
    cover (f_past && done && !nack);
    cover (f_past && done && nack);
  end
`endif
endmodule
