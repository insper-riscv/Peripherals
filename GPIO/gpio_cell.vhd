-- =============================================================================
-- Célula de E/S de uso geral de um bit
--
-- Liga o processador a um pino bidirecional, com controle de direção, operações
-- de saída (carregar, ligar, limpar e inverter) e configuração de interrupção
-- (máscaras, detecção de borda e limpeza escrevendo 1). Oferece ao processador um
-- multiplexador de leitura do estado interno.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

library work;

entity gpio_cell is
  port (
    -- Clock do módulo.
    i_clk : in  std_logic;
    -- Reset, ativo em '1'.
    i_rst : in  std_logic;

    -- Dado de 1 bit vindo do processador.
    i_data_in  : in  std_logic;
    -- Estado interno lido pelo processador, um bit por registrador.
    o_data_out : out std_logic_vector (6 downto 0);

    -- Habilitações de escrita dos registradores, na ordem do mapa de bits do decodificador.
    i_wr_signals : in std_logic_vector(6 downto 0);
    -- Operação de saída: 00 carrega, 01 liga, 10 limpa, 11 inverte.
    i_wr_op  : in std_logic_vector(1 downto 0);

    -- Pino de E/S físico (bidirecional).
    io_gpio_pin : inout std_logic
  );
end entity;

architecture rtl of gpio_cell is
  
  -- Registrador de direção (0 = entrada, 1 = saída).
  signal dir_reg : std_logic;
  -- Registrador de saída, o valor enviado ao pino.
  signal out_reg : std_logic;
  -- Entrada do pino sincronizada com o clock.
  signal pin_input : std_logic;
  -- Resultado do multiplexador das operações de escrita.
  signal mux_write : std_logic;
  -- Máscara global de interrupção da célula.
  signal irq_mask : std_logic;
  -- Máscara de interrupção por borda de subida.
  signal irq_rise_mask : std_logic;
  -- Máscara de interrupção por borda de descida.
  signal irq_fall_mask : std_logic;
  -- Registrador de status de interrupção.
  signal irq_status : std_logic;
  -- Valor anterior do pino, para detectar bordas.
  signal prev_pin_input : std_logic;
  -- Uma borda habilitada foi detectada neste ciclo.
  signal interrupt_logic : std_logic;
  -- Resultado do multiplexador de escrita em formato de vetor de 1 bit.
  signal mux_write_vector : std_logic_vector(0 downto 0);
  -- Dado de carga em formato de vetor de 1 bit.
  signal load_vector   : std_logic_vector(0 downto 0);
  -- Valor invertido da saída em formato de vetor de 1 bit.
  signal toggle_vector : std_logic_vector(0 downto 0);
  -- Habilita a escrita do registrador de saída.
  signal out_enable    : std_logic;
  -- Limpa o status de interrupção (reset ou escrita de 1).
  signal irq_clear     : std_logic;
  -- Liga o status de interrupção (borda detectada com a máscara ligada).
  signal irq_set       : std_logic;
  -- Operando que liga o bit, em formato de vetor de 1 bit.
  constant SET_VECTOR   : std_logic_vector(0 downto 0) := "1";
  -- Operando que limpa o bit, em formato de vetor de 1 bit.
  constant CLEAR_VECTOR : std_logic_vector(0 downto 0) := "0";
  -- Saída de 1 bit do registrador de status, em formato de vetor.
  signal irq_status_q : std_logic_vector(0 downto 0);
  -- Dado de 1 bit com valor '1', entrada do registrador de status.
  constant ONE_BIT : std_logic_vector(0 downto 0) := "1";

begin
  load_vector   <= (0 => i_data_in);
  toggle_vector <= (0 => not out_reg);
  out_enable    <= i_wr_signals(1) or (i_wr_signals(2) and i_data_in);
  irq_clear     <= i_rst or i_wr_signals(6);
  irq_set       <= interrupt_logic and irq_mask;

  -----------------------------------------------------------------------------
  -- Registrador de direção: controla se o pino é entrada ou saída.
  -- 0 = entrada, 1 = saída
  -----------------------------------------------------------------------------
  u_reg_dir : entity work.flip_flop
    port map (
        i_clk    => i_clk,
        i_rst    => i_rst,
        i_enable => i_wr_signals(0), -- Habilita a escrita do registrador de direção
        i_d      => i_data_in, -- Dado a escrever no registrador de direção
        o_d      => dir_reg  -- Direção do pino (entrada ou saída)
    );

  -----------------------------------------------------------------------------
  -- Multiplexador das operações de escrita.
  -- Seletor 00 = carrega, 01 = liga, 10 = limpa, 11 = inverte
  -----------------------------------------------------------------------------
  u_mux_write : entity work.mux_4x1
    generic map (
      data_width => 1
    )
    port map (
      i_d0  => load_vector,
      i_d1  => SET_VECTOR,
      i_d2  => CLEAR_VECTOR,
      i_d3  => toggle_vector,
      i_sel => i_wr_op,
      o_d   => mux_write_vector
    );

  -- Desempacota o resultado do multiplexador (mux_write é std_logic)
  mux_write <= mux_write_vector(0); -- Converte o vetor de 1 bit em std_logic

  
  -----------------------------------------------------------------------------
  -- Registrador de saída: guarda o valor enviado ao pino.
  -- Habilitado nas cargas e quando o bit é selecionado (dado de entrada = 1) em ligar, limpar e inverter.
  -----------------------------------------------------------------------------
  u_reg_out : entity work.flip_flop
    port map (
        i_clk    => i_clk,
        i_rst    => i_rst,
        i_enable => out_enable, -- Carga ou ligar, limpar e inverter
        i_d      => mux_write, -- Dado a escrever no registrador de saída
        o_d      => out_reg -- Dado enviado ao pino
    );

  -----------------------------------------------------------------------------
  -- Buffer tristate: liga o registrador de saída ao pino conforme a direção.
  -- Com dir_reg = '1', o buffer está habilitado e out_reg vai ao pino.
  -- Com dir_reg = '0', o buffer está desabilitado e o pino fica em alta impedância.
  -----------------------------------------------------------------------------
  u_gpio_buffer : entity work.tristate_buffer_1bit
    port map (
      i_d      => out_reg,
      i_enable => dir_reg,
      o_d      => io_gpio_pin
    );

  -----------------------------------------------------------------------------
  -- Sincronizador: leva a entrada assíncrona do pino ao domínio do clock.
  -- Evita metaestabilidade na leitura do pino.
  -----------------------------------------------------------------------------      
  u_sync : entity work.synchronizer
    generic map (stages => 2, data_width => 1)
    port map (
        i_clk  => i_clk,
        i_d(0) => io_gpio_pin, -- Entrada assíncrona vinda do pino
        o_d(0) => pin_input    -- Saída sincronizada para o processador
    );

  -----------------------------------------------------------------------------
  -- Registrador do valor anterior do pino.
  -- Usado na detecção de bordas da lógica de interrupção.
  -----------------------------------------------------------------------------
  u_reg_prev : entity work.flip_flop
    port map (
        i_clk    => i_clk,
        i_rst    => '0', -- Sem reset
        i_enable => '1', -- Sempre habilitado
        i_d      => pin_input, -- Entrada sincronizada do pino
        o_d      => prev_pin_input -- Valor anterior do pino
    );

  -----------------------------------------------------------------------------
  -- Registrador de máscara de interrupção: habilita ou desabilita as interrupções desta célula.
  -- Com irq_mask = '1' as interrupções estão habilitadas; com '0', desabilitadas.
  -----------------------------------------------------------------------------
  u_irq_mask : entity work.flip_flop
    port map (
        i_clk    => i_clk,
        i_rst    => i_rst,
        i_enable => i_wr_signals(3), -- Habilita a escrita da máscara de interrupção
        i_d      => i_data_in, -- Dado a escrever na máscara de interrupção
        o_d      => irq_mask -- Registrador de máscara de interrupção
    );
  
  -----------------------------------------------------------------------------
  -- Registrador de máscara de borda de subida: controla a detecção de interrupção por borda de subida.
  -- Com irq_rise_mask = '1' as interrupções por borda de subida estão habilitadas; com '0', desabilitadas.
  -----------------------------------------------------------------------------
  u_irq_rise : entity work.flip_flop
    port map (
        i_clk    => i_clk,
        i_rst    => i_rst,
        i_enable => i_wr_signals(4), -- Habilita a escrita da máscara de borda de subida
        i_d      => i_data_in, -- Dado a escrever na máscara de borda de subida
        o_d      => irq_rise_mask -- Registrador de máscara de borda de subida
    );
  
  --------------------------------------------------------------------------
  -- Registrador de máscara de borda de descida: controla a detecção de interrupção por borda de descida.
  -- Com irq_fall_mask = '1' as interrupções por borda de descida estão habilitadas; com '0', desabilitadas.
  --------------------------------------------------------------------------
  u_irq_fall : entity work.flip_flop
    port map (
        i_clk    => i_clk,
        i_rst    => i_rst,
        i_enable => i_wr_signals(5), -- Habilita a escrita da máscara de borda de descida
        i_d      => i_data_in, -- Dado a escrever na máscara de borda de descida
        o_d      => irq_fall_mask -- Registrador de máscara de borda de descida
    );
  
  -----------------------------------------------------------------------------
  -- Lógica de interrupção: detecta bordas de subida e de descida no pino.
  -- Gera o sinal de interrupção se a máscara correspondente estiver ligada.
  -- Borda de subida: pin_input passa de 0 a 1 (prev_pin_input = 0, pin_input = 1)
  -- Borda de descida: pin_input passa de 1 a 0 (prev_pin_input = 1, pin_input = 0)
  -----------------------------------------------------------------------------
  interrupt_logic <= (irq_rise_mask and (pin_input and not prev_pin_input)) or
                     (irq_fall_mask and (not pin_input and prev_pin_input)); -- Detecção de borda

  ----------------------------------------------------------------------------
  -- Registrador de status de interrupção desta célula.
  -- Com irq_status = '1' houve uma interrupção; com '0', nenhuma.
  -- O status é limpo quando o processador escreve '1' no registrador (W1C).
  -- O status liga quando a lógica de interrupção está em '1' e a máscara está habilitada.
  ----------------------------------------------------------------------------
  u_irq_status : entity work.clearable_register
    generic map (
      data_width => 1
    )
    port map (
      i_clk    => i_clk,
      i_clear  => irq_clear,
      i_enable => irq_set,
      i_d      => ONE_BIT,
      o_d      => irq_status_q
    );
  irq_status <= irq_status_q(0);
  

  o_data_out(0) <= dir_reg; -- Lê o registrador de direção
  o_data_out(1) <= out_reg; -- Lê o registrador de saída
  o_data_out(2) <= pin_input; -- Lê a entrada do pino
  o_data_out(3) <= irq_mask; -- Lê a máscara de interrupção
  o_data_out(4) <= irq_rise_mask; -- Lê a máscara de borda de subida
  o_data_out(5) <= irq_fall_mask; -- Lê a máscara de borda de descida
  o_data_out(6) <= irq_status; -- Lê o status de interrupção
end architecture;
