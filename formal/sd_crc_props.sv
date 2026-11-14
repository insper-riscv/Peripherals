// Propriedades do CRC7 (sd_crc7) e do CRC16 (sd_crc16) serial do cartão SD, verificadas na netlist Verilog que o
// GHDL sintetiza do VHDL. O CRC16 é escolhido por -DCRC16 e o CRC7 é o padrão. O primeiro clock é um reset.
//   REF      (padrão)  O registrador é o resto da divisão polinomial da mensagem já alimentada por x^W, calculado
//                      aqui por divisão longa de um vetor, sem registrador de deslocamento. A mensagem vale desde o
//                      último reset ou limpeza, com até 48 bits.
//   RESIDUE            Depois de uma mensagem qualquer, alimentar o próprio CRC (o bit mais significativo primeiro)
//                      deixa o registrador em zero.
//   VEC                Valor conhecido: o CRC7 de CMD0 (40 4A em 40 bits) é 0x4A e o CRC16 de "123456789" é 0x31C3.
`ifdef CRC16
`define W 16
`define POLY 16'h1021
`define DUT sd_crc16
`define VECLEN 72
`define VECDATA 72'h313233343536373839
`define VECEXP 16'h31C3
`else
`define W 7
`define POLY 7'h09
`define DUT sd_crc7
`define VECLEN 40
`define VECDATA 40'h4000000000
`define VECEXP 7'h4A
`endif
module props (input clk);
  (* anyseq *) wire rst_f, clear_f, en_f, bit_f, go;
  reg f_past = 0;
  always @(posedge clk) f_past <= 1;

  // Estado dos modos RESIDUE e VEC.
  reg tail = 0, tail_done = 0;
  reg [4:0] tcnt = 0;
  reg [`W-1:0] tcrc = 0;
  reg [6:0] vcnt = 0;

  wire [`W-1:0] crc;
  wire capture = go && f_past && !tail && !tail_done;

`ifdef RESIDUE
  wire rst   = !f_past || (!tail && !capture && rst_f);
  wire clear = tail ? 1'b0 : (capture ? 1'b0 : clear_f);
  wire en    = tail ? 1'b1 : (capture ? 1'b0 : en_f);
  wire b     = tail ? tcrc[`W-1-tcnt] : bit_f;
`elsif VEC
  wire rst   = !f_past;
  wire clear = 1'b0;
  wire en    = f_past && vcnt < `VECLEN;
  wire [`VECLEN-1:0] vec = `VECDATA;
  wire b     = en ? vec[`VECLEN-1-vcnt] : 1'b0;
`else
  wire rst   = !f_past || rst_f;
  wire clear = clear_f;
  wire en    = en_f;
  wire b     = bit_f;
`endif

  `DUT dut (.i_clk(clk), .i_rst(rst), .i_clear(clear), .i_enable(en), .i_bit(b), .o_crc(crc));

`ifdef RESIDUE
  always @(posedge clk) begin
    if (capture) begin tail <= 1; tcrc <= crc; tcnt <= 0; end
    else if (tail) begin
      tcnt <= tcnt + 1;
      if (tcnt == `W - 1) begin tail <= 0; tail_done <= 1; end
    end
  end
  // No ciclo seguinte ao último bit do CRC o registrador está em zero.
  reg chk = 0;
  always @(posedge clk) begin
    chk <= tail && tcnt == `W - 1;
    if (f_past && chk) assert (crc == 0);
  end
`elsif VEC
  always @(posedge clk) begin
    if (f_past && vcnt < `VECLEN) vcnt <= vcnt + 1;
    if (f_past && vcnt == `VECLEN) assert (crc == `VECEXP);
  end
`else
  // Mensagem já alimentada, alinhada à direita, e quantidade de bits.
  reg [47:0] m_msg = 0;
  reg [6:0] m_len = 0;
  always @(posedge clk) begin
    if (rst || clear) begin m_msg <= 0; m_len <= 0; end
    else if (en) begin m_msg <= {m_msg[46:0], b}; m_len <= m_len + 1; end
  end
  always @* if (en) assume (m_len < 48);

  // Divisão longa de M(x) * x^W pelo gerador, da maior potência para a menor.
  function [`W-1:0] crc_ref(input [47:0] msg, input [6:0] len);
    reg [47+`W:0] r;
    integer i;
    begin
      r = {msg, {`W{1'b0}}};
      for (i = 47; i >= 0; i = i - 1)
        if (i < len && r[i + `W]) r = r ^ ({1'b1, `POLY} << i);
      crc_ref = r[`W-1:0];
    end
  endfunction

  always @(posedge clk) if (f_past) assert (crc == crc_ref(m_msg, m_len));
`endif

`ifdef COVER
  always @(posedge clk) if (f_past) begin
`ifdef RESIDUE
    cover (chk);
`elsif VEC
    cover (vcnt == `VECLEN);
`else
    cover (m_len == 5 && crc != 0);
    cover (m_len == 5 && crc == 0);
`endif
  end
`endif
endmodule
