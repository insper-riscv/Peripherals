// Propriedades do ir_regs, verificadas na netlist Verilog que o GHDL sintetiza do VHDL, contra um modelo ideal dos
// registradores e da fila de quadros (3 posições na prova). A prova é limitada e cobre toda sequência de acessos
// ao barramento, de quadros do decodificador, de erros e de medidas, com dados quaisquer.
//   1. Depois do reset o controle lê 0x08 (só o NEC estendido ligado), a fila está vazia e nenhum bit pegajoso vale 1.
//   2. O controle guarda os cinco bits escritos e o bit de esvaziamento lê zero; as saídas de habilitação o seguem.
//   3. O status mostra a fila, a linha e os três bits pegajosos, que sobem pelo evento e só caem pela escrita de 1.
//   4. A fila perde o quadro que chega cheia e acende o estouro; a leitura do dado remove um quadro; o esvaziamento
//      zera a fila.
//   5. A interrupção é a soma das três condições, cada uma com a sua máscara.
//   6. Um endereço fora do mapa lê zero.
`ifndef DEPTH
`define DEPTH 3
`endif
module props (input clk);
  (* anyseq *) wire reset, write, read, frame_valid, repeat_f, ext_f, error_f, event_f, mark_f, line;
  (* anyseq *) wire [2:0] address;
  (* anyseq *) wire [31:0] data_in, width;
  (* anyseq *) wire [15:0] addr_f;
  (* anyseq *) wire [7:0] cmd_f;
  wire [31:0] data_out;
  wire irq, enable, ext_en;

  ir_regs dut (.i_clk(clk), .i_rst(reset), .i_data_in(data_in), .i_address(address), .i_write(write),
    .i_read(read), .o_data_out(data_out), .o_irq(irq), .o_enable(enable), .o_ext_en(ext_en),
    .i_frame_valid(frame_valid), .i_address_f(addr_f), .i_command_f(cmd_f), .i_repeat_f(repeat_f),
    .i_extended_f(ext_f), .i_error_f(error_f), .i_event(event_f), .i_event_mark(mark_f), .i_width(width),
    .i_line_active(line));

  // O primeiro clock é um reset, como na placa; as propriedades valem a partir dele.
  reg f_past = 0;
  initial assume (reset);
  always @(posedge clk) f_past <= 1;

  // Modelo ideal.
  reg en = 0, fie = 0, eie = 0, ext = 1, rie = 0, ferr = 0, ovf = 0, rawnew = 0;
  reg [1:0] n = 0;
  reg [31:0] rm = 0, rs = 0;
  wire wr_ctrl = write && address == 3'd0;
  wire wr_stat = write && address == 3'd1;
  wire flush = wr_ctrl && data_in[5];
  wire m_pop = read && address == 3'd2 && n != 0;
  wire m_push = frame_valid && n != `DEPTH;

  always @(posedge clk) begin
    if (reset) begin
      en <= 0; fie <= 0; eie <= 0; ext <= 1; rie <= 0; ferr <= 0; ovf <= 0; rawnew <= 0; n <= 0; rm <= 0; rs <= 0;
    end else begin
      if (wr_ctrl) begin
        en <= data_in[0]; fie <= data_in[1]; eie <= data_in[2]; ext <= data_in[3]; rie <= data_in[4];
      end
      ferr <= (ferr && !(wr_stat && data_in[2])) || error_f;
      ovf <= (ovf && !(wr_stat && data_in[3])) || (frame_valid && n == `DEPTH);
      rawnew <= (rawnew && !(wr_stat && data_in[5])) || event_f;
      n <= flush ? 2'd0 : n + m_push - m_pop;
      if (event_f && mark_f) rm <= width;
      if (event_f && !mark_f) rs <= width;
    end
  end

  always @(posedge clk) if (f_past) begin
    assert (enable == en);
    assert (ext_en == ext);
    assert (irq == ((fie && n != 0) || (eie && (ferr || ovf)) || (rie && rawnew)));
    if (address == 3'd0) assert (data_out == {27'd0, rie, ext, eie, fie, en});
    if (address == 3'd1)
      assert (data_out == {16'd0, 6'd0, n, 2'd0, rawnew, line, ovf, ferr, n == `DEPTH, n != 0});
    if (address == 3'd2 && n == 0) assert (data_out == 0);
    if (address == 3'd3) assert (data_out == rm);
    if (address == 3'd4) assert (data_out == rs);
    if (address > 3'd4) assert (data_out == 0);
  end

`ifdef COVER
  always @(posedge clk) if (f_past) begin
    cover (ovf && n == `DEPTH);
    cover (irq && eie && ferr);
    cover (irq && rie && rawnew);
    cover (irq && fie && n != 0);
    cover (flush && n == 2 && !reset);
    cover (m_pop && n == 1);
  end
`endif
endmodule
