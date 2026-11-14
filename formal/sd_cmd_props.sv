// Propriedades do controle de comando do cartão SD (sd_cmd), verificadas na netlist Verilog que o GHDL sintetiza do
// VHDL, com ncr_clocks = 4 e gap_clocks = 2. Os pulsos de borda de SD_CLK são livres, mas só alternam (subida com o
// clock em nível baixo, descida com ele em nível alto), como o gerador de clock os produz. O primeiro clock é um
// reset. Salvo com FAST, i_start é livre e cada propriedade vale para qualquer índice e argumento.
//   FRAME (padrão)  Os bits do cabeçalho lançados na linha CMD são os do comando aceito (início 0, transmissão 1, índice e
//                   argumento), as saídas só mudam numa borda de descida, um i_start com o controle ocupado não
//                   muda o quadro e os erros zeram a cada início. Com FAST o quadro inteiro tem exatamente 48 bits,
//                   com o CRC7 bit a bit (igual à divisão polinomial, provada em sd_crc_props.sv) e o bit de fim 1,
//                   e o controle solta a linha CMD ao fim.
//   TIMEOUT         Sem resposta (linha CMD parada em 1) o erro de prazo vem depois de exatamente ncr_clocks subidas, o
//                   fim de comando depois de mais gap_clocks, e não há outro erro nem resposta válida.
//   RESP            Com uma resposta feita por um cartão simples que obedece ao formato (RSP=1 curta, RSP=2 sem CRC,
//                   RSP=3 longa), a resposta é aceita sem erro, o corpo chega ao registrador e o fim de comando vem
//                   depois dela. As variantes BADCRC, BADIDX e BADEND estragam um campo, e o controle acusa
//                   exatamente o erro correspondente e nunca dá a resposta como válida. BUSY acrescenta a espera por
//                   DAT0 com prazo de 2 clocks.
//   ABORT           i_abort leva o controle ao repouso no ciclo seguinte, sem fim de comando.
`ifndef RSP
`define RSP 1
`endif
`ifdef BADIDX
`define IDX_RESP (c_idx ^ 6'h01)
`elsif NOCRC
`define IDX_RESP r_idx
`else
`define IDX_RESP c_idx
`endif
`ifdef BADCRC
`define CRC_SHORT (crc7_40(short_head) ^ (r_mask | 7'h01))
`define CRC_LONG (crc7_120(r_body) ^ (r_mask | 7'h01))
`elsif NOCRC
`define CRC_SHORT r_mask
`define CRC_LONG crc7_120(r_body)
`else
`define CRC_SHORT crc7_40(short_head)
`define CRC_LONG crc7_120(r_body)
`endif
`ifdef BADEND
`define END_BIT 1'b0
`else
`define END_BIT 1'b1
`endif
module props (input clk);
  (* anyseq *) wire rst_f, abort_f, start_f, rise_f, fall_f, cmd_in_f, dat0;
  (* anyseq *) wire [5:0] index_f;
  (* anyseq *) wire [31:0] arg_f;
  (* anyseq *) wire [1:0] rsp_f;
  (* anyseq *) wire wbusy_f;
  (* anyseq *) wire [23:0] tmo_f;
  (* anyconst *) reg [31:0] r_arg;
  (* anyconst *) reg [5:0] r_idx;
  (* anyconst *) reg [119:0] r_body;
  (* anyconst *) reg [6:0] r_mask;
  (* anyconst *) reg [1:0] r_dly;

  reg f_past = 0, f_past2 = 0;
  always @(posedge clk) begin f_past <= 1; f_past2 <= f_past; end

  wire rst = !f_past || rst_f;
`ifdef ABORT
  wire abort = abort_f;
`else
  wire abort = 1'b0;
  always @* if (f_past) assume (!rst_f);
`endif

  // Pulsos de borda alternados, como os do gerador de clock. Com FAST eles vêm em todo ciclo (divisor 0), o comando
  // começa no segundo ciclo e o índice e o argumento são constantes, o que reduz o espaço de busca das provas fundas.
  reg ph = 0;
`ifdef FAST
  wire rise = !ph;
  wire fall = ph;
  (* anyconst *) reg [5:0] k_idx;
  (* anyconst *) reg [31:0] k_arg;
  wire [5:0] index = k_idx;
  wire [31:0] arg = k_arg;
  wire start = f_past && !f_past2;
`else
  wire rise = rise_f && !ph;
  wire fall = fall_f && ph;
  wire [5:0] index = index_f;
  wire [31:0] arg = arg_f;
  wire start = start_f;
`endif
  always @(posedge clk) if (rst) ph <= 0; else if (rise) ph <= 1; else if (fall) ph <= 0;

  // Entradas de cada modo.
`ifdef RESP
  wire [1:0] rsp = `RSP;
`ifdef BUSY
  wire wbusy = 1'b1;
  wire [23:0] tmo = 24'd2;
`else
  wire wbusy = 1'b0;
  wire [23:0] tmo = tmo_f;
`endif
`elsif TIMEOUT
  wire [1:0] rsp = 2'd1;
  wire wbusy = 1'b0;
  wire [23:0] tmo = tmo_f;
`else
  wire [1:0] rsp = rsp_f;
  wire wbusy = wbusy_f;
  wire [23:0] tmo = tmo_f;
`endif

  wire o_cmd, oe, busy, done, resp_ok, e_t, e_c, e_i, e_f;
  wire [127:0] response;
  wire cmd_line;

  sd_cmd dut (.i_clk(clk), .i_rst(rst), .i_abort(abort), .i_start(start), .i_index(index), .i_argument(arg),
    .i_response(rsp), .i_wait_busy(wbusy), .i_timeout(tmo), .i_rise(rise), .i_fall(fall), .i_cmd(cmd_line),
    .i_dat0(dat0), .o_cmd(o_cmd), .o_cmd_oe(oe), .o_busy(busy), .o_done(done), .o_resp_ok(resp_ok),
    .o_response(response), .o_err_timeout(e_t), .o_err_crc(e_c), .o_err_index(e_i), .o_err_frame(e_f));

  // CRC7 (x^7 + x^3 + 1) de um vetor de 40 bits e de um de 120 bits, um bit por passo. A igualdade deste registrador com a
  // divisão polinomial é provada à parte, em sd_crc_props.sv.
  function [6:0] crc7_40(input [39:0] msg);
    reg [6:0] r;
    integer i;
    begin
      r = 7'b0;
      for (i = 39; i >= 0; i = i - 1) r = {r[5:0], 1'b0} ^ ((r[6] ^ msg[i]) ? 7'h09 : 7'h00);
      crc7_40 = r;
    end
  endfunction
  function [6:0] crc7_120(input [119:0] msg);
    reg [6:0] r;
    integer i;
    begin
      r = 7'b0;
      for (i = 119; i >= 0; i = i - 1) r = {r[5:0], 1'b0} ^ ((r[6] ^ msg[i]) ? 7'h09 : 7'h00);
      crc7_120 = r;
    end
  endfunction

  // Comando aceito: o que foi pedido no ciclo em que o controle estava livre.
  reg [5:0] c_idx = 0;
  reg [31:0] c_arg = 0;
  reg p_busy = 0, p_oe = 0, p_cmd = 1, p_acc = 0, fall_d = 0, p_abort = 0, p_rst = 0;
  wire accept = start && !busy;
  wire [39:0] c_head = {2'b01, c_idx, c_arg};
  wire [6:0] c_crc = crc7_40(c_head);
  always @(posedge clk) begin
    p_busy <= busy; p_oe <= oe; p_cmd <= o_cmd; fall_d <= fall; p_abort <= abort; p_rst <= rst;
    p_acc <= accept && !rst && !abort;
    if (accept) begin c_idx <= index; c_arg <= arg; end
  end

  // Subidas contadas desde que o controle soltou a linha CMD (a primeira pode vir no ciclo da detecção).
  wire rel_now = p_oe && !oe;
  reg sampling = 0;
  reg [8:0] n_samp = 0;
  wire [8:0] n_eff = rel_now ? 9'd0 : n_samp;
  wire samp_act = sampling || rel_now;
  always @(posedge clk) begin
    if (rst || abort || done) begin sampling <= 0; n_samp <= 0; end
    else if (rel_now) begin sampling <= 1; n_samp <= rise ? 9'd1 : 9'd0; end
    else if (sampling && rise) n_samp <= n_samp + 1;
  end

`ifdef RESP
  // Resposta curta: início 0, transmissão 0, índice, argumento, CRC7 e fim 1; R3 com campos livres; ou R2.
  wire [39:0] short_head = {2'b00, `IDX_RESP, r_arg};
  wire [47:0] short_frame = {short_head, `CRC_SHORT, `END_BIT};
  wire [135:0] long_frame = {2'b00, 6'b111111, r_body, `CRC_LONG, `END_BIT};
`ifdef LONG
  localparam LEN = 136;
  wire [LEN-1:0] frame = long_frame;
`else
  localparam LEN = 48;
  wire [LEN-1:0] frame = short_frame;
`endif
  always @* assume (r_dly < 4);
  wire [8:0] pos = n_eff - {7'b0, r_dly};
  assign cmd_line = !samp_act ? 1'b1 : (n_eff < r_dly) ? 1'b1 : (pos < LEN) ? frame[LEN-1-pos] : 1'b1;
`elsif TIMEOUT
  assign cmd_line = 1'b1;
`else
  assign cmd_line = cmd_in_f;
`endif

  reg [6:0] rcount = 0;
  reg [1:0] oks = 0;
  reg last_dat0 = 1;
  always @(posedge clk) begin
    if (rst || abort || done) rcount <= 0;
    else if (rel_now) rcount <= rise ? 7'd1 : 7'd0;
    else if (sampling && rise) rcount <= rcount + 1;
    if (accept) oks <= 0;
    else if (resp_ok) oks <= oks + 1;
    if (rise) last_dat0 <= dat0;
  end

`ifdef ABORT
  always @(posedge clk) if (f_past2 && p_abort && !p_rst) assert (!busy && !oe && !done && !resp_ok);
`elsif TIMEOUT
  always @(posedge clk) if (f_past) begin
    if (done) begin
      assert (e_t && !e_c && !e_i && !e_f && !resp_ok);
      assert (rcount == 6);
    end
    assert (!resp_ok);
  end
`elsif RESP
  always @(posedge clk) if (f_past) begin
    if (done) begin
`ifdef BADCRC
      assert (e_c && !e_t && !e_f && !e_i && oks == 0);
`elsif BADIDX
      assert (e_i && !e_t && !e_c && !e_f && oks == 0);
`elsif BADEND
      assert (e_f && !e_t && !e_c && !e_i && oks == 0);
`else
      assert (!e_c && !e_i && !e_f && oks == 1);
`ifdef BUSY
      assert (e_t || last_dat0);
`else
      assert (!e_t);
`endif
`ifdef LONG
      assert (response[119:0] == r_body);
`else
      assert (response[31:0] == r_arg);
`ifndef NOCRC
      assert (response[37:32] == c_idx);
`endif
`endif
`endif
    end
`ifdef BADCRC
    assert (!resp_ok);
`elsif BADIDX
    assert (!resp_ok);
`elsif BADEND
    assert (!resp_ok);
`endif
  end
`else
  // FRAME.
  reg [47:0] obs = 0;
  reg [6:0] ocnt = 0;
  always @(posedge clk) begin
    if (rst) ocnt <= 0;
    else if (fall_d && oe) begin obs <= {obs[46:0], o_cmd}; ocnt <= ocnt + 1; end
    else if (fall_d && !oe) ocnt <= 0;
  end
  always @(posedge clk) if (f_past2) begin
    // Cada saída só muda na borda de descida do ciclo anterior.
    if (oe != p_oe) assert (fall_d);
    if (o_cmd != p_cmd) assert (fall_d);
    // Fora do comando a linha está solta e em nível alto.
    if (!busy) assert (!oe && o_cmd);
    // O fim de comando só vem com o controle livre, depois de ter estado ocupado.
    if (done) assert (!busy && p_busy);
    // Cada bit do cabeçalho lançado é o do comando aceito, mesmo com i_start livre durante o comando.
    if (fall_d && oe && ocnt < 40) assert (o_cmd == c_head[39 - ocnt]);
`ifdef FAST
    // O comando acaba com a linha solta depois de exatamente 48 bits.
    if (fall_d && !oe && ocnt != 0) assert (ocnt == 48 && obs == {c_head, c_crc, 1'b1});
`endif
    // Os erros zeram quando o comando começa.
    if (p_acc) assert (!e_t && !e_c && !e_i && !e_f);
  end
`endif

`ifdef COVER
  always @(posedge clk) if (f_past) begin
`ifdef ABORT
    cover (p_abort && !busy);
`elsif TIMEOUT
    cover (done && e_t);
`elsif RESP
    cover (resp_ok);
    cover (done);
`else
    cover (fall_d && !oe && ocnt == 48);
    cover (done);
`endif
  end
`endif
endmodule
