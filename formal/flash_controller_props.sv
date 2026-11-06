// Propriedades do flash_controller, verificadas na netlist Verilog que o GHDL sintetiza do VHDL, com uma página de
// 16 bytes (quatro palavras; a lógica é a mesma da página de 256 bytes). O barramento e o estado do chip são
// entradas livres. Um modelo de referência segue as escritas: o registrador de endereço, o índice do buffer e
// uma palavra vigiada do buffer (wi, constante mas qualquer). O primeiro clock é um reset.
module props (input clk);
  (* anyseq *) wire rst, wr, rd, busy, wel, refused;
  (* anyseq *) wire [2:0] adr;
  (* anyseq *) wire [31:0] din;
  (* anyseq *) wire [1:0] bidx;
  (* anyconst *) wire [1:0] wi;
  wire [31:0] dout, cmd_addr, buf_data;
  wire cmd_valid, irq;
  wire [2:0] cmd_op;

  flash_controller dut (.i_clk(clk), .i_rst(rst), .i_data_in(din), .i_address(adr), .i_write(wr), .i_read(rd),
    .o_data_out(dout), .o_irq(irq), .o_cmd_valid(cmd_valid), .o_cmd_op(cmd_op), .o_cmd_addr(cmd_addr), .i_busy(busy),
    .i_wel(wel), .i_refused(refused), .i_buf_idx(bidx), .o_buf_data(buf_data));

  reg f_past = 0;
  reg [31:0] m_addr = 0;
  reg [1:0] m_ptr = 0;
  reg [31:0] m_word = 0, p_word = 0;
  reg m_written = 0, p_written = 0;
  reg [1:0] p_idx = 0;
  // Interrupção: habilitação, eventos pendentes e o ocupado e a recusa da borda anterior.
  reg [1:0] m_en = 0, m_st = 0;
  reg m_busy_prev = 0, m_ref_prev = 0;
  wire ev_done = m_busy_prev && !busy;
  wire ev_ref = refused && !m_ref_prev;

  always @(posedge clk) begin
    f_past <= 1;
    m_busy_prev <= busy;
    m_ref_prev <= refused;
    if (rst) begin
      m_addr <= 0;
      m_ptr <= 0;
      m_en <= 0;
      m_st <= 0;
    end else begin
      if (wr && adr == 3'd5) m_en <= din[1:0];
      m_st <= {(m_st[1] && !(wr && adr == 3'd6 && din[1])) || ev_ref,
               (m_st[0] && !(wr && adr == 3'd6 && din[0])) || ev_done};
      if (wr && adr == 3'd1) m_addr <= din;
      if (wr && adr == 3'd3) m_ptr <= din[1:0];
      else if (wr && adr == 3'd4) m_ptr <= m_ptr + 2'd1;
    end
    // a palavra vigiada do buffer: o que o chip lê na borda é o valor anterior à escrita dessa borda
    p_idx <= bidx;
    p_word <= m_word;
    p_written <= m_written;
    if (wr && adr == 3'd4 && m_ptr == wi) begin
      m_word <= din;
      m_written <= 1;
    end
  end

  // ---- o ambiente ----
  always @* if (!f_past) assume (rst);
  always @* if (f_past) assume (!rst);

  always @(posedge clk) if (f_past) begin
    // 1. O comando é a escrita no registrador 0, com os três bits baixos do dado e o endereço guardado.
    assert (cmd_valid == (wr && adr == 3'd0));
    assert (cmd_op == din[2:0]);
    assert (cmd_addr == m_addr);
    // 2. A leitura devolve o registrador do endereço, o estado do chip ou o índice do buffer; sem leitura, e nos
    //    demais endereços, zero.
    if (!rd) assert (dout == 32'h0);
    else case (adr)
      3'd1: assert (dout == m_addr);
      3'd2: assert (dout == {29'h0, refused, wel, busy});
      3'd3: assert (dout == {30'h0, m_ptr});
      3'd5: assert (dout == {30'h0, m_en});
      3'd6: assert (dout == {30'h0, m_st});
      default: assert (dout == 32'h0);
    endcase
    // 3. A saída de interrupção é de nível: algum evento pendente e habilitado.
    assert (irq == ((m_st & m_en) != 2'b00));
    // 4. O chip lê do buffer a palavra que a escrita deixou no índice, uma borda depois.
    if (p_written && p_idx == wi) assert (buf_data == p_word);
  end

`ifdef COVER
  always @(posedge clk) if (f_past) begin
    cover (cmd_valid && cmd_op == 3'd3);
    cover (rd && adr == 3'd2 && busy && refused);
    cover (wr && adr == 3'd4 && m_ptr == 2'd3);
    cover (irq && m_st[0] && m_en[0]);
    cover (irq && m_st[1] && m_en[1]);
    cover (p_written && p_idx == wi && buf_data != 32'h0);
  end
`endif
endmodule
