// Propriedades do uart, verificadas na netlist Verilog que o GHDL sintetiza do VHDL, com a netlist expondo
// como saídas os registradores do invólucro e os sinais do PHY (os mesmos fios, só visíveis). A prova roda
// com baud_freq = 0 e baud_limit = 0, o que faz o gerador de baud emitir ce16 em todo ciclo: um bit dura
// 16 ciclos. As razões reais só mudam quanto tempo o ce16 leva para chegar, e não o formato do quadro.
// Três modos, escolhidos por define:
//   REGS  registradores e flags do invólucro contra um modelo, com o PHY livre;
//   TXF   formato do quadro na transmissão: start, 8 dados do menos significativo ao mais, stop;
//   RXF   recepção de um quadro enviado pelo ambiente, com ruído nas bordas de cada bit de dado:
//         a amostragem tem de cair no meio do bit, e nenhum byte se perde.
`ifndef OFF
`define OFF 1
`endif
module props (input clk);
  (* anyseq *) wire reset, write, read;
  (* anyseq *) wire [1:0] addr;
  (* anyseq *) wire [31:0] wdata;
  wire [31:0] rdata;
  wire irq, tx;
  wire d_valid, d_over, d_drop, d_ie, d_new_rx, d_busy, d_new_tx;
  wire [7:0] d_data, d_phy_rx;
`ifdef RXF
  wire rx;
`else
  (* anyseq *) wire rx;
`endif

  uart dut (.i_clk(clk), .i_rst(reset), .i_data_in(wdata), .i_address(addr), .i_write(write), .i_read(read),
    .o_data_out(rdata), .o_irq(irq), .i_uart_rx(rx), .o_uart_tx(tx), .dbg_rx_valid(d_valid), .dbg_rx_overrun(d_over),
    .dbg_tx_dropped(d_drop), .dbg_rx_irq_enable(d_ie), .dbg_phy_new_rx_data(d_new_rx), .dbg_phy_tx_busy(d_busy), .dbg_phy_new_tx_data(d_new_tx),
    .dbg_rx_data_reg(d_data), .dbg_phy_rx_data(d_phy_rx));

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
  reg m_valid = 0, m_over = 0, m_drop = 0, m_ie = 0;
  reg [7:0] m_data = 0;
  reg p_new_rx = 0, p_valid = 0, p_rd = 0;
  reg [7:0] p_phy = 0;
`ifdef ANYSTATE
  initial begin
    assume (m_valid == d_valid); assume (m_over == d_over); assume (m_drop == d_drop);
    assume (m_ie == d_ie); assume (m_data == d_data);
  end
`endif

  always @(posedge clk) begin
    p_new_rx <= d_new_rx; p_valid <= m_valid; p_rd <= rd_rx; p_phy <= d_phy_rx;
    m_ie <= reset ? 1'b0 : (wr_ctl ? wdata[0] : m_ie);
    m_over <= reset ? 1'b0
      : ((d_new_rx && m_valid && !rd_rx) ? 1'b1 : ((wr_stat && wdata[2]) ? 1'b0 : m_over));
    m_drop <= reset ? 1'b0
      : ((wr_tx && d_busy) ? 1'b1 : ((wr_stat && wdata[3]) ? 1'b0 : m_drop));
    m_data <= reset ? 8'h0 : (d_new_rx ? d_phy_rx : m_data);
    m_valid <= reset ? 1'b0 : (d_new_rx ? 1'b1 : (rd_rx ? 1'b0 : m_valid));
  end

  always @(posedge clk) if (f_past) begin
    // 1. Os registradores seguem o modelo do contrato: valido, overrun (byte novo com o anterior ainda não lido),
    //    descarte de transmissão (escrita com o PHY ocupado) e máscara de interrupção.
    assert (d_valid == m_valid);
    assert (d_over == m_over);
    assert (d_drop == m_drop);
    assert (d_ie == m_ie);
    assert (d_data == m_data);
    // 2. Nenhum byte se perde com o buffer livre: o byte do PHY fica no registrador e o overrun não sobe.
    if (p_new_rx && !p_valid) assert (d_data == p_phy && d_valid && d_over == (m_over));
    // 3. A leitura do dado limpa o válido, e um byte novo no mesmo ciclo da leitura não é overrun.
    if (p_rd && !p_new_rx) assert (!d_valid);
    // 4. A escrita de transmissão só chega ao PHY com ele livre; ocupado, é descartada.
    assert (d_new_tx == (wr_tx && !d_busy));
    // 5. Leitura de cada endereço e interrupção.
    case (addr)
      2'd0: assert (rdata == 32'h0);
      2'd1: assert (rdata == {24'b0, m_data});
      2'd2: assert (rdata == {28'b0, m_drop, m_over, !d_busy, m_valid});
      2'd3: assert (rdata == {31'b0, m_ie});
    endcase
    assert (irq == (m_valid && m_ie));
  end

`ifdef COVER
  always @(posedge clk) if (f_past) begin
    cover (wr_tx && d_busy);
    cover (wr_tx && !d_busy && wdata[7:0] == 8'hA5);
  end
`endif
`endif

`ifdef TXF
  // Quadro de transmissão. Uma escrita aceita (PHY livre) com o byte D começa um quadro de 10 bits de 16 ciclos:
  // start em zero, D[0] a D[7], stop em um. OFF é o atraso, em ciclos, do primeiro bit depois da escrita.
  reg got = 0;
  reg [7:0] byte_tx = 0;
  reg [8:0] c = 0;
  wire [8:0] kk = c - `OFF;
  wire [3:0] bit_idx = kk / 16;
  wire expected = (bit_idx == 0) ? 1'b0 : ((bit_idx <= 8) ? byte_tx[bit_idx - 1] : 1'b1);

  always @(posedge clk) begin
    if (d_new_tx && f_past) begin
      got <= 1; byte_tx <= wdata[7:0]; c <= 0;
    end else if (c != 9'd500) begin
      c <= c + 1;
    end
  end

  always @(posedge clk) if (f_past) begin
    // 1. Ocioso, a linha fica em um.
    if (!got) assert (tx);
    if (got && c < `OFF) assert (tx);
    // 2. No quadro: start em zero, os oito dados do menos significativo ao mais, stop em um, 16 ciclos cada.
    if (got && c >= `OFF && c < `OFF + 160) assert (tx == expected);
    // 3. O PHY fica ocupado até pelo menos o meio do bit de stop, o que faz uma escrita nesse tempo ser descartada.
    if (got && c < `OFF + 152) assert (d_busy);
    // 4. Depois do quadro a linha volta a um.
    if (got && c >= `OFF + 160) assert (tx);
  end

`ifdef COVER
  always @(posedge clk) if (f_past) begin
    cover (got && c == `OFF + 24 && !tx && byte_tx == 8'h5A);
    cover (got && c == `OFF + 40 && tx && byte_tx == 8'h5A);
  end
`endif
`endif

`ifdef RXF
  // Sem leitura do dado, o byte recebido fica no registrador até o fim da prova.
  always @(posedge clk) assume (!read);
  // Ambiente: um quadro de 10 bits de 16 ciclos (start, B[0] a B[7], stop). Nos bits de dado, os G primeiros e os
  // G últimos ciclos de cada bit podem ter qualquer valor (ruído); o meio do bit é limpo.
  localparam G = 3;
  (* anyseq *) wire go, noise;
  (* anyseq *) wire [7:0] pick;
  reg running = 0;
  reg [7:0] B = 0;
  reg [7:0] rk = 0;
  reg [3:0] rcnt = 0;
  wire [3:0] ridx = rk / 16;
  wire [3:0] rsub = rk % 16;
  wire data_bit = (ridx >= 1 && ridx <= 8);
  wire edge_zone = data_bit && (rsub < G || rsub >= 16 - G);
  wire level = (ridx == 0) ? 1'b0 : (data_bit ? B[ridx - 1] : 1'b1);
  assign rx = running ? (edge_zone ? noise : level) : 1'b1;

  always @(posedge clk) begin
    if (!running) begin
      if (go && f_past) begin running <= 1; B <= pick; rk <= 0; rcnt <= 0; end
    end else begin
      rk <= rk + 1;
      if (rk == 8'd180) running <= 0;
      if (d_new_rx) rcnt <= rcnt + 1;
    end
  end

  always @(posedge clk) if (f_past) begin
    // 1. Nenhum byte aparece sem um quadro, e um quadro dá um só byte.
    if (d_new_rx) assert (running);
    // 2. Passado o stop, exatamente um byte chegou e é o enviado: a amostragem caiu no meio de cada bit.
    if (running && rk == 8'd180) assert (rcnt == 1 && d_data == B && d_valid);
  end

`ifdef COVER
  always @(posedge clk) if (f_past) begin
    cover (running && rk == 8'd180 && rcnt == 1 && B == 8'hA5);
  end
`endif
`endif
endmodule
