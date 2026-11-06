// Propriedades do console, verificadas na netlist Verilog que o GHDL sintetiza do miter console_equiv: o console
// e o bloco que ele escolhe (uart para "pinos", jtag_uart para "jtag"), ligados às mesmas entradas livres, têm
// saídas iguais em todo ciclo: dado lido, interrupção, linha de transmissão e saída da cadeia JTAG. A polaridade
// dos pinos, escrita à parte na referência como inversão explícita, também tem de coincidir. O primeiro clock é
// um reset, como na placa; o reset não volta depois. Com o define COVER, mostra que o miter não é vazio: o
// console devolve um dado não nulo e levanta a interrupção.
module props (input clk);
  (* anyseq *) wire rst, we, re, rx;
  (* anyseq *) wire [7:0] adr;
  (* anyseq *) wire [31:0] wdata;
  wire [31:0] rdata_dut, rdata_ref;
  wire irq_dut, irq_ref, tx_dut, tx_ref, tdo_dut, tdo_ref;

  console_equiv dut (.i_clk(clk), .i_rst(rst), .i_addr(adr), .i_wdata(wdata), .i_we(we), .i_re(re), .i_rx(rx),
    .o_rdata_dut(rdata_dut), .o_rdata_ref(rdata_ref), .o_irq_dut(irq_dut), .o_irq_ref(irq_ref),
    .o_tx_dut(tx_dut), .o_tx_ref(tx_ref), .o_tdo_dut(tdo_dut), .o_tdo_ref(tdo_ref));

  reg f_past = 0;
  always @(posedge clk) f_past <= 1;
  always @* if (!f_past) assume (rst);
  always @* if (f_past) assume (!rst);

`ifndef COVER
  always @* if (f_past) begin
    assert (rdata_dut == rdata_ref);
    assert (irq_dut == irq_ref);
    assert (tx_dut == tx_ref);
    assert (tdo_dut == tdo_ref);
  end
`else
  always @* cover (f_past && re && rdata_dut != 0);
  always @* cover (f_past && irq_dut);
`endif
endmodule
