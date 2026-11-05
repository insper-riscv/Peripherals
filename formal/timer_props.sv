// Propriedades do timer, verificadas na netlist Verilog que o GHDL sintetiza do VHDL. A netlist expõe como
// saídas os registradores internos (contador, topo, ciclo de trabalho, prescaler, configuração, status e
// borda de overflow, e o tick do prescaler), cuja lógica é a mesma: eles deixam a indução enunciar o estado.
// O barramento é livre. O modelo guarda cada registrador como o contrato da documentação o descreve.
//
// Mapa de endereços: 0 configuração (start, mode, pwm, irq_mask), 1 carga do contador, 2 zera o contador,
// 3 topo, 4 ciclo de trabalho, 5 status de overflow (a leitura limpa), 6 PWM, 7 prescaler.
module props (input clk);
  (* anyseq *) wire reset, write, read;
  (* anyseq *) wire [2:0] addr;
  (* anyseq *) wire [31:0] wdata;
  wire [31:0] rdata;
  wire irq, pwm;
  wire [31:0] d_counter, d_top, d_duty, d_presc;
  wire [3:0] d_config;
  wire d_status, d_prev, d_tick, d_pwm_inv;

  timer dut (.i_clk(clk), .i_rst(reset), .i_data_in(wdata), .i_address(addr), .i_write(write), .i_read(read),
    .o_data_out(rdata), .o_irq(irq), .o_pwm(pwm), .dbg_counter(d_counter), .dbg_top_reg(d_top), .dbg_duty_reg(d_duty),
    .dbg_prescaler_reg(d_presc), .dbg_config_reg(d_config), .dbg_overflow_status(d_status), .dbg_overflow_prev(d_prev), .dbg_tick(d_tick),
    .dbg_pwm_inverted(d_pwm_inv));

  // Os registradores não têm valor inicial: o primeiro clock é um reset, como na placa.
  initial assume (reset);

  reg f_past = 0;
  reg [31:0] m_cnt = 0, m_top = 32'hFFFFFFFF, m_duty = 0, m_presc = 0;
  reg [3:0] m_config = 0;
  reg m_status = 0, m_prev = 0;

  wire wr_cfg  = write && addr == 3'd0;
  wire wr_load = write && addr == 3'd1;
  wire wr_zero = write && addr == 3'd2;
  wire wr_top  = write && addr == 3'd3;
  wire wr_duty = write && addr == 3'd4;
  wire wr_pres = write && addr == 3'd7;
  wire rd_ovf  = read && addr == 3'd5;

  wire start = m_config[0], mode = m_config[1], pwm_en = m_config[2], irq_mask = m_config[3];
  wire ovf = m_cnt >= m_top;
  wire clear = reset || wr_zero || (ovf && !mode);
  wire count = wr_load || (start && d_tick && !(ovf && mode));

  always @(posedge clk) begin
    f_past <= 1;
    m_config <= reset ? 4'h0 : (wr_cfg ? wdata[3:0] : m_config);
    m_top    <= reset ? 32'hFFFFFFFF : (wr_top ? wdata : m_top);
    m_duty   <= reset ? 32'h0 : (wr_duty ? wdata : m_duty);
    m_presc  <= reset ? 32'h0 : (wr_pres ? wdata : m_presc);
    m_cnt    <= clear ? 32'h0 : (count ? (wr_load ? wdata : m_cnt + 32'd1) : m_cnt);
    m_prev   <= reset ? 1'b0 : ovf;
    m_status <= (reset || rd_ovf) ? 1'b0 : ((ovf && !m_prev) ? 1'b1 : m_status);
  end

  always @(posedge clk) if (f_past) begin
    // 1. Os registradores só mudam por escrita do barramento (ou pelo contador), e o reset os leva ao valor inicial.
    assert (d_config == m_config);
    assert (d_top == m_top);
    assert (d_duty == m_duty);
    assert (d_presc == m_presc);
    // 2. O contador só zera, carrega ou avança um por tick com a partida ligada; no modo de parada ele
    //    não passa do topo, e no de reinício zera ao alcançá-lo.
    assert (d_counter == m_cnt);
    // 3. A interrupção sobe uma vez por estouro (borda de subida do alcance do topo), nenhum se perde, e a
    //    leitura do status a limpa; a máscara decide se o status chega a o_irq.
    assert (d_status == m_status);
    assert (d_prev == (reset ? 1'b0 : m_prev));
    assert (irq == (irq_mask && m_status));
    // 4. O PWM é alto enquanto o contador está abaixo do ciclo de trabalho.
    assert (d_pwm_inv == !(m_cnt >= m_duty));
    // 5. A leitura pelo barramento devolve o registrador do endereço (config, contador, topo, ciclo de
    //    trabalho, status, prescaler), e nenhum outro dado escapa.
    case (addr)
      3'd0: assert (rdata == {28'b0, m_config});
      3'd1, 3'd2: assert (rdata == m_cnt);
      3'd3: assert (rdata == m_top);
      3'd4: assert (rdata == m_duty);
      3'd5: assert (rdata == {31'b0, m_status});
      3'd7: assert (rdata == m_presc);
      default: ;
    endcase
  end

`ifdef COVER
  reg p_irq = 0;
  always @(posedge clk) begin
    p_irq <= irq;
    // Um estouro sobe a interrupção, e a leitura do status a limpa.
    cover (f_past && irq && !p_irq);
    cover (f_past && p_irq && !irq && !reset);
    // O contador avança um por tick.
    cover (f_past && start && d_tick && !clear && m_cnt != 0);
  end
`endif
endmodule
