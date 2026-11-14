// Propriedades do controle de fluxo do uart (has_flow_control = true), verificadas na netlist Verilog que o GHDL
// sintetiza do VHDL, com a netlist expondo como saídas os registradores do fluxo e os sinais do PHY. Como em
// uart_props.sv, baud_freq = 0 e baud_limit = 0 fazem o ce16 pulsar em todo ciclo (um bit dura 16 ciclos) e as
// filas têm DEPTH posições. O barramento e o pino i_uart_cts são livres. As linhas são de nível baixo ativo.
// As regras do fluxo (verificação limitada a partir do reset):
//         1. nunca se inicia um quadro com CTS inativo e o fluxo ligado: nenhum byte sai da fila de transmissão
//            para o PHY (o quadro em curso termina). Que a linha só desce dentro de um quadro iniciado por um byte
//            entregue ao PHY é a prova de formato de uart_props.sv, no mesmo netlist;
//         2. o_uart_rts é o registro, no ciclo seguinte, de "fluxo ligado e nível da fila de recepção maior ou
//            igual ao limiar": RTS acompanha a fila;
//         3. com o fluxo desligado, CTS é ignorado e RTS fica ativo;
//         4. FLOW_ENABLE e RTS_THRESHOLD leem o que foi escrito (o limiar do reset é metade da fila, no mínimo 1),
//            e CTS_ACTIVE e RTS_ACTIVE leem o nível dos pinos;
`ifndef DEPTH
`define DEPTH 3
`endif
module props (input clk);
  (* anyseq *) wire reset, write, read, cts;
  (* anyseq *) wire [1:0] addr;
  (* anyseq *) wire [31:0] wdata;
  (* anyseq *) wire rx;
  wire [31:0] rdata;
  wire irq, tx, rts;
  wire d_fe, d_rts_n, d_ok, d_new_tx, d_busy, d_new_rx;
  wire [7:0] d_thr;
  wire [1:0] d_sync, d_rxl, d_txl;

  uart dut (.i_clk(clk), .i_rst(reset), .i_data_in(wdata), .i_address(addr), .i_write(write), .i_read(read),
    .o_data_out(rdata), .o_irq(irq), .i_uart_rx(rx), .o_uart_tx(tx), .i_uart_cts(cts), .o_uart_rts(rts),
    .dbg_flow_enable(d_fe), .dbg_rts_inactive(d_rts_n), .dbg_cts_ok(d_ok), .dbg_phy_new_tx_data(d_new_tx),
    .dbg_phy_tx_busy(d_busy), .dbg_phy_new_rx_data(d_new_rx), .dbg_rts_threshold(d_thr), .dbg_cts_sync(d_sync),
    .dbg_rx_fifo_level(d_rxl), .dbg_tx_fifo_level(d_txl));

  // O primeiro clock é um reset, como na placa; o reset não volta depois.
  reg f_past = 0;
  initial assume (reset);
  always @(posedge clk) if (f_past) assume (!reset);
  always @(posedge clk) f_past <= 1;

  wire wr_ctl = write && addr == 2'd3;

  // Estado do ciclo anterior, para as relações entre um ciclo e o seguinte.
  reg p_fe = 0;
  reg [7:0] p_thr = 0;
  reg [1:0] p_rxl = 0;
  always @(posedge clk) begin
    p_fe <= d_fe; p_thr <= d_thr; p_rxl <= d_rxl;
  end

  // Modelo dos registradores de configuração.
  reg m_fe = 0;
  reg [7:0] m_thr = 0;
  always @(posedge clk) begin
    m_fe <= reset ? 1'b0 : (wr_ctl ? wdata[7] : m_fe);
    m_thr <= reset ? ((`DEPTH / 2 < 1) ? 8'd1 : `DEPTH / 2) : (wr_ctl ? wdata[15:8] : m_thr);
  end

  always @(posedge clk) if (f_past) begin
    // 1. O PHY só recebe um byte com o fluxo desligado ou com CTS ativo (já sincronizado).
    assert (d_ok == (!d_fe || !d_sync[1]));
    if (d_new_tx) assert (!d_fe || !d_sync[1]);
    // 2. O pino de RTS é o registro da condição de fila, um ciclo depois.
    assert (rts == (p_fe && p_rxl >= p_thr));
    assert (rts == d_rts_n);
    // 3. Sem o fluxo ligado, RTS fica ativo (baixo) a partir do ciclo seguinte e o byte sai sempre que o PHY
    //    está livre, qualquer que seja o CTS.
    if (!p_fe) assert (!rts);
    if (!d_fe) assert (d_new_tx == (!d_busy && d_txl != 0));
    // 4. Leitura dos registradores de fluxo.
    assert (d_fe == m_fe && d_thr == m_thr);
    if (addr == 2'd3) assert (rdata[7] == m_fe && rdata[15:8] == m_thr);
    if (addr == 2'd2) assert (rdata[25] == !d_sync[1] && rdata[26] == !d_rts_n);
  end

`ifdef COVER
  always @(posedge clk) if (f_past) begin
    cover (d_fe && d_sync[1] && d_txl != 0 && !d_busy);
    cover (d_new_tx && d_fe && p_fe);
    cover (rts && d_fe);
    cover (d_fe && d_thr == 0 && rts);
  end
`endif
endmodule
