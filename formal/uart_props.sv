// Propriedades do uart, verificadas na netlist Verilog que o GHDL sintetiza do VHDL, com a netlist expondo
// como saídas os registradores do invólucro, os níveis das filas e os sinais do PHY (os mesmos fios, só visíveis).
// A prova roda com baud_freq = 0 e baud_limit = 0, o que faz o gerador de baud emitir ce16 em todo ciclo: um bit
// dura 16 ciclos. As razões reais só mudam quanto tempo o ce16 leva para chegar, e não o formato do quadro. As
// filas têm DEPTH posições (3 na prova, o menor valor com ponteiros que dão a volta fora de uma potência de dois),
// o que deixa o enchimento ao alcance da indução e dos covers. A ordem dos bytes e o conteúdo das filas são
// propriedades do uart_fifo, provadas em uart_fifo_props.sv.
// Cada prova usa o uart sem controle de fluxo (has_flow_control = false, o padrão), com i_uart_cts em zero; o
// controle de fluxo tem as suas provas em uart_flow_props.sv.
// Três modos, escolhidos por define:
//   REGS  níveis das filas, flags, interrupção e leitura de cada registrador contra um modelo, com o PHY livre;
//   TXF   formato do quadro na transmissão: start, 8 dados do menos significativo ao mais, paridade opcional,
//         um ou dois stop (PEN, PODD e S2 escolhem o formato, e o ambiente o escreve em CONTROL no primeiro ciclo);
//   RXF   recepção de um quadro enviado pelo ambiente, com ruído nas bordas de cada bit de dado: a amostragem
//         tem de cair no meio do bit, nenhum byte se perde, e as flags de erro seguem o quadro (BADPAR inverte o
//         bit de paridade, BADSTOP envia o primeiro stop em zero).
`ifndef OFF
`define OFF 1
`endif
`ifndef PEN
`define PEN 0
`endif
`ifndef PODD
`define PODD 0
`endif
`ifndef S2
`define S2 0
`endif
`ifndef BADPAR
`define BADPAR 0
`endif
`ifndef BADSTOP
`define BADSTOP 0
`endif
`ifndef DEPTH
`define DEPTH 3
`endif
module props (input clk);
  (* anyseq *) wire reset, write, read;
  (* anyseq *) wire [1:0] addr;
  (* anyseq *) wire [31:0] wdata;
  wire [31:0] rdata;
  wire irq, tx;
  wire d_over, d_drop, d_ie, d_tie, d_eie, d_new_rx, d_busy, d_new_tx;
  wire d_ferr, d_perr, d_pen, d_podd, d_s2, d_lie, d_ferr_p, d_perr_p;
  wire [7:0] d_phy_rx, d_phy_tx, d_rx_head;
  wire [1:0] d_rxl, d_txl;
`ifdef RXF
  wire rx;
`else
  (* anyseq *) wire rx;
`endif

  uart dut (.i_clk(clk), .i_rst(reset), .i_data_in(wdata), .i_address(addr), .i_write(write), .i_read(read),
    .o_data_out(rdata), .o_irq(irq), .i_uart_rx(rx), .o_uart_tx(tx), .i_uart_cts(1'b0), .o_uart_rts(), .dbg_rx_overrun(d_over),
    .dbg_tx_dropped(d_drop), .dbg_rx_irq_enable(d_ie), .dbg_tx_irq_enable(d_tie), .dbg_err_irq_enable(d_eie), .dbg_phy_new_rx_data(d_new_rx), .dbg_phy_tx_busy(d_busy),
    .dbg_phy_new_tx_data(d_new_tx), .dbg_phy_rx_data(d_phy_rx), .dbg_phy_tx_data(d_phy_tx),
    .dbg_rx_fifo_data(d_rx_head), .dbg_rx_fifo_level(d_rxl), .dbg_tx_fifo_level(d_txl),
    .dbg_frame_error(d_ferr), .dbg_parity_error(d_perr), .dbg_parity_enable(d_pen), .dbg_parity_odd(d_podd),
    .dbg_stop_bits_2(d_s2), .dbg_line_irq_enable(d_lie), .dbg_phy_frame_error(d_ferr_p), .dbg_phy_parity_error(d_perr_p));

  // Os registradores não têm valor inicial: o primeiro clock é um reset, como na placa. O reset não volta
  // depois: as propriedades valem a partir dele.
  reg f_past = 0;
`ifndef ANYSTATE
  initial assume (reset);
`else
  // ANYSTATE: parte de um estado qualquer do PHY e do invólucro, com o modelo igual a ele, em vez do reset.
  initial assume (!reset);
`endif
  always @(posedge clk) if (f_past) assume (!reset);
  always @(posedge clk) f_past <= 1;

  wire wr_ctl  = write && addr == 2'd3;
  wire wr_stat = write && addr == 2'd2;
  wire wr_tx   = write && addr == 2'd0;
  wire rd_rx   = read && addr == 2'd1;

`ifdef REGS
  // Modelo das duas filas pelos níveis: a recepção insere com o byte do PHY e remove com a leitura de RX_DATA,
  // a transmissão insere com a escrita de TX_DATA e remove quando o PHY está livre. Uma inserção numa fila cheia
  // só é aceita junto de uma remoção aceita.
`ifdef ANYSTATE
  reg [1:0] m_rxl, m_txl;
  reg m_over, m_drop, m_ie, m_tie, m_eie, m_ferr, m_perr, m_pen, m_podd, m_s2, m_lie;
`else
  reg [1:0] m_rxl = 0, m_txl = 0;
  reg m_over = 0, m_drop = 0, m_ie = 0, m_tie = 0, m_eie = 0, m_ferr = 0, m_perr = 0, m_pen = 0, m_podd = 0, m_s2 = 0, m_lie = 0;
`endif
  wire rx_pop = rd_rx && m_rxl != 0;
  wire rx_acc = d_new_rx && (m_rxl != `DEPTH || rx_pop);
  wire tx_pop = !d_busy && m_txl != 0;
  wire tx_acc = wr_tx && (m_txl != `DEPTH || tx_pop);
`ifdef ANYSTATE
  initial begin
    assume (m_rxl == d_rxl); assume (m_txl == d_txl); assume (m_over == d_over); assume (m_drop == d_drop);
    assume (m_ie == d_ie); assume (m_tie == d_tie); assume (m_eie == d_eie);
    assume (m_ferr == d_ferr); assume (m_perr == d_perr); assume (m_pen == d_pen); assume (m_podd == d_podd);
    assume (m_s2 == d_s2); assume (m_lie == d_lie); assume (m_rxl <= `DEPTH); assume (m_txl <= `DEPTH);
  end
`endif

  always @(posedge clk) begin
    m_ie <= reset ? 1'b0 : (wr_ctl ? wdata[0] : m_ie);
    m_tie <= reset ? 1'b0 : (wr_ctl ? wdata[1] : m_tie);
    m_eie <= reset ? 1'b0 : (wr_ctl ? wdata[2] : m_eie);
    m_pen <= reset ? 1'b0 : (wr_ctl ? wdata[3] : m_pen);
    m_podd <= reset ? 1'b0 : (wr_ctl ? wdata[4] : m_podd);
    m_s2 <= reset ? 1'b0 : (wr_ctl ? wdata[5] : m_s2);
    m_lie <= reset ? 1'b0 : (wr_ctl ? wdata[6] : m_lie);
    m_ferr <= reset ? 1'b0 : (d_ferr_p ? 1'b1 : ((wr_stat && wdata[7]) ? 1'b0 : m_ferr));
    m_perr <= reset ? 1'b0 : (d_perr_p ? 1'b1 : ((wr_stat && wdata[24]) ? 1'b0 : m_perr));
    m_over <= reset ? 1'b0
      : ((d_new_rx && !rx_acc) ? 1'b1 : ((wr_stat && wdata[2]) ? 1'b0 : m_over));
    m_drop <= reset ? 1'b0
      : ((wr_tx && !tx_acc) ? 1'b1 : ((wr_stat && wdata[3]) ? 1'b0 : m_drop));
    m_rxl <= reset ? 2'd0 : m_rxl + rx_acc - rx_pop;
    m_txl <= reset ? 2'd0 : m_txl + tx_acc - tx_pop;
  end

  always @(posedge clk) if (f_past) begin
    // 1. Os níveis das filas e as flags seguem o modelo do contrato: overrun (byte novo com a fila de recepção
    //    cheia), descarte de transmissão (escrita com a fila cheia) e máscara de interrupção.
    assert (d_rxl == m_rxl);
    assert (d_txl == m_txl);
    assert (m_rxl <= `DEPTH && m_txl <= `DEPTH);
    assert (d_over == m_over);
    assert (d_drop == m_drop);
    assert (d_ie == m_ie && d_tie == m_tie && d_eie == m_eie);
    assert (d_ferr == m_ferr && d_perr == m_perr && d_pen == m_pen && d_podd == m_podd && d_s2 == m_s2 && d_lie == m_lie);
    // 2. Um byte da fila de transmissão só chega ao PHY com ele livre, e toda vez que ele está livre e há byte.
    assert (d_new_tx == (!d_busy && m_txl != 0));
    // 3. Leitura de cada endereço e interrupção. O byte lido de RX_DATA é o primeiro da fila, ou zero se vazia.
    case (addr)
      2'd0: assert (rdata == 32'h0);
      2'd1: assert (rdata == {24'b0, d_rx_head} && (m_rxl != 0 || d_rx_head == 8'h0));
      2'd2: assert (rdata == {7'b0, m_perr, 6'b0, m_txl, 6'b0, m_rxl, m_ferr, m_txl == 0 && !d_busy, m_txl == 0,
                              m_rxl == `DEPTH, m_drop, m_over, m_txl != `DEPTH, m_rxl != 0});
      2'd3: assert (rdata == {25'b0, m_lie, m_s2, m_podd, m_pen, m_eie, m_tie, m_ie});
    endcase
    // 4. A saída é a soma de quatro causas de nível, cada uma com a sua habilitação.
    assert (irq == ((m_rxl != 0 && m_ie) || (m_txl == 0 && m_tie) || ((m_over || m_drop) && m_eie)
                    || ((m_ferr || m_perr) && m_lie)));
  end

`ifdef COVER
  always @(posedge clk) if (f_past) begin
    cover (m_drop);
    cover (tx_acc && !d_busy && wdata[7:0] == 8'hA5);
    cover (m_txl == `DEPTH);
    cover (irq && m_txl == 0 && m_tie && m_rxl == 0 && !m_over && !m_drop);
`ifdef ANYSTATE
    cover (m_over);
    cover (m_ferr && !m_perr);
    cover (m_perr && !m_ferr);
    cover (d_new_rx && m_rxl == `DEPTH && rx_pop);
`endif
  end
`endif
`endif

`ifdef TXF
  // Formato. Sem CFGSET o ambiente nunca escreve paridade nem segundo stop em CONTROL (8N1). Com CFGSET, o
  // primeiro ciclo depois do reset escreve CONTROL com PEN, PODD e S2 e as escritas seguintes mantêm esses três
  // bits; a fila está vazia, então nenhum quadro começa antes da escrita.
  localparam [2:0] CFG = {`S2 == 1, `PODD == 1, `PEN == 1};
  reg cfg_done = 0;
  always @(posedge clk) begin
`ifdef CFGSET
    if (f_past && !cfg_done) assume (wr_ctl && wdata[5:3] == CFG);
    if (cfg_done && wr_ctl) assume (wdata[5:3] == CFG);
`else
    if (wr_ctl) assume (wdata[5:3] == 3'b000);
`endif
    if (f_past) cfg_done <= 1;
  end

  // Quadro de transmissão. Uma remoção da fila (PHY livre) com o byte D começa um quadro de NB bits de 16 ciclos:
  // start em zero, D[0] a D[7], a paridade (se PEN) e um ou dois stop em um. OFF é o atraso, em ciclos, do
  // primeiro bit depois da escrita.
  localparam NB = 10 + `PEN + `S2;
  reg got = 0;
  reg [7:0] byte_tx = 0;
  reg [8:0] c = 0;
  wire [8:0] kk = c - `OFF;
  wire [3:0] bit_idx = kk / 16;
  wire par = (^byte_tx) ^ (`PODD == 1);
  wire expected = (bit_idx == 0) ? 1'b0 : ((bit_idx <= 8) ? byte_tx[bit_idx - 1]
                  : ((`PEN == 1 && bit_idx == 9) ? par : 1'b1));

  always @(posedge clk) begin
    if (d_new_tx && f_past) begin
      got <= 1; byte_tx <= d_phy_tx; c <= 0;
    end else if (c != 9'd500) begin
      c <= c + 1;
    end
  end

  always @(posedge clk) if (f_past) begin
    // 1. Ocioso, a linha fica em um.
    if (!got) assert (tx);
    if (got && c < `OFF) assert (tx);
    // 2. No quadro: start em zero, os oito dados do menos significativo ao mais, a paridade que o byte pede, os
    //    stop em um, 16 ciclos cada.
    if (got && c >= `OFF && c < `OFF + 16 * NB) assert (tx == expected);
    // 3. O PHY fica ocupado até pelo menos o meio do último bit, o que faz uma escrita nesse tempo ser descartada.
    if (got && c < `OFF + 16 * NB - 8) assert (d_busy);
    // 4. Depois do quadro a linha volta a um.
    if (got && c >= `OFF + 16 * NB) assert (tx);
  end

`ifdef COVER
  always @(posedge clk) if (f_past) begin
    cover (got && c == `OFF + 24 && !tx && byte_tx == 8'h5A);
    cover (got && c == `OFF + 40 && tx && byte_tx == 8'h5A);
    cover (`PEN == 0 || (got && c == `OFF + 16 * 9 + 8 && byte_tx == 8'h5A && tx == par));
  end
`endif
`endif

`ifdef RXF
  // Sem leitura do dado, o byte recebido fica na fila até o fim da prova.
  always @(posedge clk) assume (!read);
  // Formato: o ambiente escreve CONTROL no primeiro ciclo (CFGSET) e depois só repete o formato.
  localparam [2:0] CFG = {`S2 == 1, `PODD == 1, `PEN == 1};
  reg cfg_done = 0;
  always @(posedge clk) begin
`ifdef CFGSET
    if (f_past && !cfg_done) assume (wr_ctl && wdata[5:3] == CFG);
    if (cfg_done && wr_ctl) assume (wdata[5:3] == CFG);
`else
    if (wr_ctl) assume (wdata[5:3] == 3'b000);
`endif
    if (f_past) cfg_done <= 1;
  end
  // O ambiente só inicia um quadro com o formato já escrito e sem nenhuma escrita em STATUS (que limparia flags).
  always @(posedge clk) assume (!wr_stat);
  // Ambiente: um quadro de NB bits de 16 ciclos (start, B[0] a B[7], paridade se PEN, stop). Nos bits de dado, os G
  // primeiros e os G últimos ciclos de cada bit podem ter qualquer valor (ruído); o meio do bit é limpo. BADPAR
  // inverte o bit de paridade e BADSTOP envia o primeiro stop em zero.
  localparam G = 3;
  localparam NB = 10 + `PEN + `S2;
  localparam [7:0] LASTRK = 16 * NB + 20;
  (* anyseq *) wire go, noise;
  (* anyseq *) wire [7:0] pick;
  reg running = 0;
  reg [7:0] B = 0;
  reg [7:0] rk = 0;
  reg [3:0] rcnt = 0;
  reg [3:0] fcnt = 0;
  reg [3:0] pcnt = 0;
  wire [3:0] ridx = rk / 16;
  wire [3:0] rsub = rk % 16;
  wire data_bit = (ridx >= 1 && ridx <= 8);
  wire edge_zone = data_bit && (rsub < G || rsub >= 16 - G);
  wire rpar = (^B) ^ (`PODD == 1) ^ (`BADPAR == 1);
  wire first_stop = (ridx == 9 + `PEN);
  wire level = (ridx == 0) ? 1'b0 : (data_bit ? B[ridx - 1]
               : ((`PEN == 1 && ridx == 9) ? rpar : ((`BADSTOP == 1 && first_stop) ? 1'b0 : 1'b1)));
  assign rx = running ? (edge_zone ? noise : level) : 1'b1;

  always @(posedge clk) begin
    if (!running) begin
      if (go && f_past && cfg_done) begin running <= 1; B <= pick; rk <= 0; rcnt <= 0; fcnt <= 0; pcnt <= 0; end
    end else begin
      rk <= rk + 1;
      if (rk == LASTRK) running <= 0;
      if (d_new_rx) rcnt <= rcnt + 1;
      if (d_ferr_p) fcnt <= fcnt + 1;
      if (d_perr_p) pcnt <= pcnt + 1;
    end
  end

  always @(posedge clk) if (f_past) begin
    // 1. Nenhum byte aparece sem um quadro, e um quadro dá um só byte.
    if (d_new_rx) assert (running);
    // 2. Passado o último stop, exatamente um byte chegou e é o enviado: a amostragem caiu no meio de cada bit.
    if (running && rk == LASTRK) assert (rcnt == 1 && d_rxl == 1 && d_rx_head == B);
    // 3. Os erros seguem o quadro: um pulso de quadro se o stop veio em zero, um de paridade se o bit veio
    //    trocado, e nenhum pulso fora de um quadro. Os pulsos ficam nas flags persistentes.
    if (running && rk == LASTRK) assert (fcnt == `BADSTOP && pcnt == ((`PEN == 1 && `BADPAR == 1) ? 1 : 0));
    if (running && rk == LASTRK) assert (d_ferr == (`BADSTOP == 1) && d_perr == (`PEN == 1 && `BADPAR == 1));
  end

`ifdef COVER
  always @(posedge clk) if (f_past) begin
    cover (running && rk == LASTRK && rcnt == 1 && B == 8'hA5);
    cover (running && rk == LASTRK && rcnt == 1 && B == 8'hA5 && d_perr == (`PEN == 1 && `BADPAR == 1)
           && d_ferr == (`BADSTOP == 1));
  end
`endif
`endif
endmodule
