// Propriedades do i2c_core, verificadas na netlist Verilog que o GHDL sintetiza do VHDL, com o divisor fixo em 2
// (um passo a cada três ciclos). O ambiente é benigno: as linhas voltam ao núcleo como o que ele mesmo puxa, depois
// do atraso de dois ciclos do sincronizador, e os comandos obedecem ao contrato do topo (um comando só com o núcleo
// livre, sem envio e recepção juntos, e sem início próprio só depois de um início). O primeiro clock é um reset.
module props (input clk);
  (* anyseq *) wire rst, enable, abort, cmd_valid, c_start, c_stop, c_read, c_write, c_nack;
  (* anyseq *) wire [7:0] tx;
  wire busy, active, done, nack, arb, scl_low, sda_low;
  wire [7:0] rx;
  reg r1_scl = 1, r2_scl = 1, r1_sda = 1, r2_sda = 1;

  i2c_core dut (.i_clk(clk), .i_rst(rst), .i_enable(enable), .i_abort(abort), .i_divider(16'd2),
    .i_cmd_valid(cmd_valid), .i_cmd_start(c_start), .i_cmd_stop(c_stop), .i_cmd_read(c_read),
    .i_cmd_write(c_write), .i_cmd_nack(c_nack), .i_tx_data(tx), .i_scl(r2_scl), .i_sda(r2_sda), .o_busy(busy),
    .o_bus_active(active), .o_done(done), .o_nack(nack), .o_arb_lost(arb), .o_rx_data(rx), .o_scl_low(scl_low),
    .o_sda_low(sda_low));

  reg f_past = 0, p_busy = 0, p_done = 0, p_rst = 0, saw_active = 0;
  reg [2:0] p_off = 0;

  always @(posedge clk) begin
    f_past <= 1;
    p_busy <= busy;
    p_done <= done;
    p_rst <= rst;
    p_off <= {p_off[1:0], abort || !enable};
    r1_scl <= !scl_low; r2_scl <= r1_scl;
    r1_sda <= !sda_low; r2_sda <= r1_sda;
    if (active) saw_active <= 1;
  end

  always @* begin
    if (!f_past) assume (rst);
    if (cmd_valid) assume (!busy && (c_start || c_stop || c_read || c_write) && !(c_read && c_write)
                           && (c_start || active));
  end

  always @(posedge clk) if (f_past) begin
    // 1. Um comando só termina com um pulso de fim, que cai no ciclo em que o ocupado cai, e dura um ciclo.
    assert (!(done && p_done));
    if (done) assert (!busy && (p_busy || p_rst));
    // 2. Com o reset, o aborto ou o núcleo desligado na borda anterior, as linhas estão soltas e nada em curso.
    if (p_rst || p_off[0]) assert (!scl_low && !sda_low && !busy && !active);
    // 3. Entre dois comandos de um início já dado o núcleo segura SCL baixo; fora de uma transação solta as duas.
    if (!busy && active) assert (scl_low);
    if (!busy && !active) assert (!scl_low && !sda_low);
    // 4. Nas linhas que ele mesmo conduz, o núcleo nunca perde a arbitragem.
    assert (!arb);
    // 5. Um NACK só aparece com um comando de envio em curso.
    if (nack) assert (busy);
  end

`ifdef COVER
  always @(posedge clk) if (f_past) begin
    cover (done && !active && saw_active);
    cover (nack);
    cover (done && active);
  end
`endif
endmodule
