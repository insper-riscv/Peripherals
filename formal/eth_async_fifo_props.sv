// Propriedades da eth_async_fifo, verificadas na netlist Verilog que o GHDL sintetiza do VHDL, com clocks de
// escrita e de leitura livres (multiclock): cada clock sobe a qualquer momento, em qualquer razão. Os ponteiros
// binários de escrita e de leitura são expostos pelo script. Com ADDR_BITS = 2 a fila tem 4 palavras.
//   1. A ocupação (ponteiro de escrita menos o de leitura) nunca passa da profundidade nem fica negativa.
//   2. Sem o_full, ainda há espaço (uma escrita aceita nunca estoura); sem o_empty, há palavra a ler.
//   3. Os ponteiros em Gray são o código Gray dos binários, e cada um muda no máximo um bit por borda.
// Depois de um reset curto dos dois lados, os resets ficam em '0' para sempre (os dois lados são resetados
// juntos, como o projeto exige), e os testes de dados são os do cocotb.
`ifndef ADDR_BITS
`define ADDR_BITS 2
`endif
module props (input clk);
  localparam N = `ADDR_BITS;
  localparam DEPTH = 1 << N;
  (* anyseq *) wire wclk, rclk, wrst, rrst, wr_en, rd_en;
  (* anyseq *) wire [2:0] wdata;
  wire full, empty;
  wire [2:0] rdata;
  wire [N:0] dbg_wbin, dbg_rbin, dbg_wgray, dbg_rgray;

  eth_async_fifo dut (.i_wclk(wclk), .i_wrst(wrst), .i_wr_en(wr_en), .i_wdata(wdata), .o_full(full),
    .i_rclk(rclk), .i_rrst(rrst), .i_rd_en(rd_en), .o_rdata(rdata), .o_empty(empty),
    .dbg_wbin(dbg_wbin), .dbg_rbin(dbg_rbin), .dbg_wgray(dbg_wgray), .dbg_rgray(dbg_rgray));

  // Contagem das bordas de subida de cada clock durante o reset inicial.
  reg wclk_q = 0, rclk_q = 0;
  reg [2:0] wedges = 0, redges = 0;
  always @($global_clock) begin
    wclk_q <= wclk;
    rclk_q <= rclk;
    if (wclk && !wclk_q && wedges != 7) wedges <= wedges + 1;
    if (rclk && !rclk_q && redges != 7) redges <= redges + 1;
  end
  wire ready = wedges >= 4 && redges >= 4;
  always @* begin
    if (!ready) assume (wrst && rrst);
    else assume (!wrst && !rrst);
  end

  wire [N:0] occupancy = dbg_wbin - dbg_rbin;
  function [N:0] gray(input [N:0] b);
    gray = b ^ (b >> 1);
  endfunction

  // Gray anterior de cada ponteiro, atualizado na borda do seu clock.
  reg [N:0] wgray_prev = 0, rgray_prev = 0;
  always @(posedge wclk) wgray_prev <= dbg_wgray;
  always @(posedge rclk) rgray_prev <= dbg_rgray;
  function onebit(input [N:0] a, input [N:0] b);
    reg [N:0] d;
    begin
      d = a ^ b;
      onebit = (d & (d - 1)) == 0;
    end
  endfunction

  always @* if (ready) begin
    assert (occupancy <= DEPTH);
    assert (full || occupancy < DEPTH);
    assert (empty || occupancy > 0);
    assert (dbg_wgray == gray(dbg_wbin));
    assert (dbg_rgray == gray(dbg_rbin));
    assert (onebit(dbg_wgray, wgray_prev));
    assert (onebit(dbg_rgray, rgray_prev));
  end

`ifdef COVER
  always @* begin
    cover (ready && full && occupancy == DEPTH);
    cover (ready && !empty && occupancy == 1);
    cover (ready && empty && occupancy == 0 && dbg_wbin != 0);
  end
`endif
endmodule
