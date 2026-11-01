-- =============================================================================
-- Temporizador com PWM e registrador de configuração
--
-- Contador com prescaler, valor de topo, ciclo de trabalho de PWM e uma máscara
-- de interrupção por overflow, acessado como periférico mapeado em memória. O
-- registrador de configuração tem quatro bits (partida, modo, PWM habilitado e
-- máscara de IRQ). O decodificador timer_operation_decoder gera as habilitações
-- de escrita e os seletores de leitura.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;

entity timer is
    generic (
        -- Largura do barramento de dados em bits.
        data_width : integer := 32
    );
    port (
        -- Clock do módulo.
        i_clk       : in  std_logic;
        -- Reset, ativo em '1'.
        i_rst       : in  std_logic; 
        -- Dado de escrita vindo do processador.
        i_data_in     : in  std_logic_vector(data_width-1 downto 0);
        -- Endereço de palavra de 3 bits vindo do processador.
        i_address     : in  std_logic_vector(2 downto 0);
        -- Pulso de escrita do processador ('1' = escreve).
        i_write       : in  std_logic; 
        -- Pulso de leitura do processador ('1' = lê).
        i_read        : in  std_logic; 
        -- Dado de leitura para o processador.
        o_data_out    : out std_logic_vector(data_width-1 downto 0);
        -- Requisição de interrupção, ativa em '1'.
        o_irq         : out std_logic;
        -- Saída PWM.
        o_pwm        : out std_logic
    );
end entity;

architecture rtl of timer is
    -- Habilitações de escrita dos registradores.
    signal wr_en   : std_logic_vector(6 downto 0);
    -- Seletor da entrada do contador.
    signal cnt_sel : std_logic;
    -- Seletor do multiplexador de leitura.
    signal rd_sel  : std_logic_vector(2 downto 0);

    -- Registrador do valor de topo.
    signal top_reg  : std_logic_vector(data_width-1 downto 0);
    -- Registrador do ciclo de trabalho.
    signal duty_reg : std_logic_vector(data_width-1 downto 0);
    -- Registrador do prescaler.
    signal prescaler_reg : std_logic_vector(data_width-1 downto 0);
    -- Registrador de configuração de 4 bits.
    signal config_reg : std_logic_vector(3 downto 0);

    -- Liga e desliga a contagem.
    signal start_signal : std_logic;
    -- Modo do temporizador.
    signal mode_signal  : std_logic;
    -- Habilita a saída PWM.
    signal pwm_en       : std_logic;
    -- O contador alcançou o topo ('1').
    signal overflow      : std_logic;
    -- Valor anterior de overflow, para detectar a borda.
    signal overflow_prev   : std_logic;
    -- Pulso de um ciclo na borda de subida de overflow.
    signal overflow_pulse  : std_logic;
    -- Máscara de interrupção do overflow.
    signal irq_mask  : std_logic;
    -- Status de overflow, limpo ao ler o registrador.
    signal overflow_status : std_logic;
    -- Saída PWM antes do buffer de saída.
    signal pwm_out       : std_logic;
    -- Resultado da comparação do PWM (contador contra ciclo de trabalho).
    signal pwm_alu      : std_logic;
    -- Requisição de interrupção em formato de vetor de 1 bit.
    signal irq_vec       : std_logic_vector(0 downto 0);
    -- Tick do prescaler que avança o contador.
    signal tick : std_logic;

    -- Entrada do contador escolhida por cnt_sel.
    signal mux_cnt : std_logic_vector(data_width-1 downto 0);
    -- Dado de leitura escolhido por rd_sel.
    signal mux_out : std_logic_vector(data_width-1 downto 0);
    -- Leitura do registrador de configuração.
    signal configs_readback : std_logic_vector(data_width-1 downto 0);
    -- Leitura do estado do PWM.
    signal pwm_readback : std_logic_vector(data_width-1 downto 0);
    -- Leitura do status de overflow.
    signal overflow_readback : std_logic_vector(data_width-1 downto 0);

    -- Valor do contador.
    signal counter : std_logic_vector(data_width-1 downto 0);
    -- Valor seguinte do contador.
    signal next_counter : std_logic_vector(data_width-1 downto 0);

    -- Zera o contador.
    signal counter_clear  : std_logic;
    -- Habilita o contador a contar.
    signal counter_enable : std_logic;
    -- Limpa o status de overflow.
    signal ovf_clear      : std_logic;
    -- Operando de 1 bit que desliga a interrupção.
    signal irq_disabled   : std_logic_vector(0 downto 0);
    -- Operando de 1 bit que liga a interrupção.
    signal irq_enabled    : std_logic_vector(0 downto 0);
    -- Saída do comparador invertida.
    signal pwm_inverted   : std_logic;
  -- Constante 1, segundo operando do somador do contador.
  constant ADDER_ONE : std_logic_vector(data_width - 1 downto 0) := std_logic_vector(to_unsigned(1, data_width));
  -- Saída de 1 bit do registrador de status, em formato de vetor.
  signal irq_status_reg_q : std_logic_vector(0 downto 0);
  -- Dado de 1 bit com valor '1'.
  constant ONE_BIT : std_logic_vector(0 downto 0) := "1";

  -- Palavra de zeros.
  constant ZERO_WORD : std_logic_vector(data_width - 1 downto 0) := (others => '0');

begin
    counter_clear  <= i_rst or wr_en(2) or (overflow and not mode_signal);
    counter_enable <= wr_en(1) or (start_signal and tick and not (overflow and mode_signal));
    ovf_clear      <= i_rst or wr_en(5);
    irq_disabled   <= (0 => '0');
    irq_enabled    <= (0 => overflow_status);
    pwm_inverted   <= not pwm_alu;

    -------------------------------------------------------------------------------
    -- Decodificador de operações do temporizador
    -------------------------------------------------------------------------------
    u_timer_operation_decoder : entity work.timer_operation_decoder
        port map (
            i_address => i_address,
            i_write   => i_write,
            i_read    => i_read,
            o_wr_en   => wr_en,
            o_cnt_sel => cnt_sel,
            o_rd_sel  => rd_sel
        );

    -------------------------------------------------------------------------------
    -- Registrador do prescaler
    -- Guarda o valor do prescaler do temporizador.
    -- É carregado com i_data_in quando wr_en(6) está em '1'.
    -- O valor do prescaler divide a frequência do clock do temporizador.
    -- O registrador tem 32 bits.
    -- É zerado no reset do sistema.
    -------------------------------------------------------------------------------
    u_prescaler_reg : entity work.clearable_register
      generic map (
        data_width => 32
      )
      port map (
        i_clk    => i_clk,
        i_clear  => i_rst,
        i_enable => wr_en(6),
        i_d      => i_data_in,
        o_d      => prescaler_reg
      );
    -------------------------------------------------------------------------------
    -- Prescaler de clock
    -- Gera o tick a partir do valor do prescaler.
    -- O tick sai quando o contador do prescaler alcança o valor do prescaler.
    -- O prescaler reduz a frequência de contagem do temporizador.
    -- O prescaler tem 32 bits; a frequência de contagem vai de 50 MHz a 0,0116 Hz.
    -------------------------------------------------------------------------------
    u_clock_prescaler : entity work.clock_prescaler
        generic map (
            data_width => data_width
        )
        port map (
            i_clk        => i_clk,
            i_rst        => i_rst,
            i_prescaler_in => prescaler_reg,
            o_tick         => tick
        );

    -------------------------------------------------------------------------------
    -- Registrador de configuração
    -- Guarda os bits de configuração do temporizador
    -- irq_mask, pwm_en, mode_signal, start_signal
    -- irq_mask: máscara da requisição de interrupção
    -- pwm_en: habilita o PWM
    -- mode_signal: modo do temporizador (parar no topo ou reiniciar)
    -- start_signal: liga e desliga a contagem
    -- O registrador tem 4 bits, um por configuração
    -- Bit:
    -- 0: start_signal
    -- 1: mode_signal
    -- 2: pwm_en
    -- 3: irq_mask
    -------------------------------------------------------------------------------
    u_config_reg : entity work.clearable_register
      generic map (
        data_width => 4
      )
      port map (
        i_clk    => i_clk,
        i_clear  => i_rst,
        i_enable => wr_en(0),
        i_d      => i_data_in(3 downto 0),
        o_d      => config_reg
      );

    -- Separa os bits de configuração
    start_signal <= config_reg(0);
    mode_signal  <= config_reg(1);
    pwm_en       <= config_reg(2);
    irq_mask     <= config_reg(3);
    ---------------------------------------------------------------------------
    -- Seletor da entrada do contador
    -- Carrega ou incrementa o contador conforme cnt_sel.
    -- Com cnt_sel = '1', o contador recebe i_data_in.
    -- Com cnt_sel = '0', o contador é incrementado de 1.
    ---------------------------------------------------------------------------
    u_mux_cnt_sel : entity work.mux_2x1
      generic map (
        data_width => data_width
      )
      port map (
        i_d0  => next_counter,
        i_d1  => i_data_in,
        i_sel => cnt_sel,
        o_d   => mux_cnt
      );

    ---------------------------------------------------------------------------
    -- Registrador do contador
    -- Guarda o valor atual do contador.
    -- A limpeza zera o contador: no reset do sistema, no reset do temporizador ou
    -- quando há overflow e o modo é de reinício automático.
    -- Habilitado na carga, ou com a partida ligada e sem overflow no modo de parada.
    ------------------------------------------------------------------------------
    u_counter_reg : entity work.clearable_register
      generic map (
        data_width => data_width
      )
      port map (
        i_clk    => i_clk,
        i_clear  => counter_clear,
        i_enable => counter_enable,
        i_d      => mux_cnt,
        o_d      => counter
      );

    ----------------------------------------------------------------------------
    -- Somador de constante
    -- Incrementa o contador de 1.
    ------------------------------------------------------------------------------
    u_constant_adder : entity work.ADDER
      generic map (
        data_width => data_width
      )
      port map (
        i_a => counter,
        i_b => ADDER_ONE,
        o_d => next_counter
      );

    --------------------------------------------------------------------------
    -- Registrador de topo
    -- Define a contagem máxima. O valor padrão, também o do reset, é 0xFFFFFFFF.
    -- É carregado com i_data_in quando wr_en(4) está em '1'.
    --------------------------------------------------------------------------
    u_top_reg : entity work.clearable_register
      generic map (
        data_width  => data_width,
        clear_value => '1'
      )
      port map (
        i_clk    => i_clk,
        i_clear  => i_rst,
        i_enable => wr_en(3),
        i_d      => i_data_in,
        o_d      => top_reg
      );

    ---------------------------------------------------------------------------
    -- Unidade de detecção de overflow
    -- O overflow ocorre quando o contador alcança o topo.
    ---------------------------------------------------------------------------
    u_counter_overflow : entity work.counter_overflow
        generic map (
            data_width => data_width
        )
        port map (
            i_counter_value => counter, -- Valor atual do contador
            i_top_value     => top_reg, -- Valor do registrador de topo
            o_overflow      => overflow -- Overflow (ativo em '1')
        );


    -- ============================================================================
    -- Registra o overflow anterior
    -- ============================================================================
    u_ovf_prev : entity work.flip_flop
        port map (
        i_clk    => i_clk,
        i_rst    => i_rst,
        i_enable => '1',          -- sempre captura
        i_d      => overflow,     -- nível atual do overflow
        o_d      => overflow_prev -- valor do ciclo anterior
    );
    overflow_pulse <= overflow and not overflow_prev;
    ---------------------------------------------------------------------------
    -- Registrador de status de overflow
    -- Guarda o status de overflow do temporizador.
    -- É limpo na leitura.
    ---------------------------------------------------------------------------
    u_irq_status_reg : entity work.clearable_register
      generic map (
        data_width => 1
      )
      port map (
        i_clk    => i_clk,
        i_clear  => ovf_clear,
        i_enable => overflow_pulse,
        i_d      => ONE_BIT,
        o_d      => irq_status_reg_q
      );
    overflow_status <= irq_status_reg_q(0);

    ---------------------------------------------------------------------------
    -- Seletor da interrupção
    -- A interrupção é escolhida pela máscara.
    -- Com a máscara em '1', a interrupção sobe no overflow.
    -- Com a máscara em '0', a interrupção não sobe.
    -- Habilita ou desabilita a interrupção de overflow.
    -------------------------------------------------------------------------------
    u_mux_irq_sel : entity work.mux_2x1
      generic map (
        data_width => 1
      )
      port map (
        i_d0  => irq_disabled,
        i_d1  => irq_enabled,
        i_sel => irq_mask,
        o_d   => irq_vec
      );
    o_irq <= irq_vec(0); -- Liga a interrupção à saída

    ---------------------------------------------------------------------------
    -- Registrador do ciclo de trabalho
    -- Guarda o ciclo de trabalho do PWM.
    -- É carregado com i_data_in quando wr_en(5) está em '1'.
    -- Define a largura do pulso do PWM.
    ---------------------------------------------------------------------------
    u_duty_reg : entity work.clearable_register
      generic map (
        data_width => data_width
      )
      port map (
        i_clk    => i_clk,
        i_clear  => i_rst,
        i_enable => wr_en(4),
        i_d      => i_data_in,
        o_d      => duty_reg
      );

  ---------------------------------------------------------------------------
    -- Comparador do PWM
    -- Compara o contador com o ciclo de trabalho.
    -- A saída indica se o contador é menor que o ciclo de trabalho.
    -- Esse sinal controla a saída PWM.
    ---------------------------------------------------------------------------
    u_pwm_alu : entity work.alu_ge_unsigned
        generic map (
            data_width => data_width
        )
        port map (
            i_source_1    => counter, -- Valor atual do contador
            i_source_2    => duty_reg, -- Ciclo de trabalho
            o_ge         => pwm_alu  -- Saída PWM ('1' quando contador < ciclo de trabalho)
        );

    ---------------------------------------------------------------------------
    -- Buffer tristate do PWM
    -- Controla a saída PWM.
    -- Com o PWM habilitado, a saída é dirigida pelo comparador.
    ---------------------------------------------------------------------------
    u_pwm_tristate : entity work.tristate_buffer_1bit
      port map (
        i_d      => pwm_inverted,
        i_enable => pwm_en,
        o_d      => pwm_out
      );
    o_pwm <= pwm_out; -- Liga a saída PWM à porta

    ---------------------------------------------------------------------------
    -- Seletor do dado de leitura
    -- Escolhe o dado de saída conforme a leitura e rd_sel.
    -- Com leitura em '1', a saída é escolhida por rd_sel.
    -- Com leitura em '0', a saída é escolhida por cnt_sel.
    ---------------------------------------------------------------------------
    configs_readback <= (31 downto 4 => '0') & (irq_mask & pwm_en & mode_signal & start_signal); -- Concatena os registradores para o multiplexador
    pwm_readback <= (31 downto 1 => '0') & pwm_out; -- Concatena a saída PWM para o multiplexador
    overflow_readback <= (31 downto 1 => '0') & overflow_status; -- Concatena o status de overflow para o multiplexador
    u_mux_out_sel : entity work.mux_8x1
      generic map (
        data_width => data_width
      )
      port map (
        i_d0  => counter,
        i_d1  => top_reg,
        i_d2  => duty_reg,
        i_d3  => configs_readback,
        i_d4  => pwm_readback,
        i_d5  => overflow_readback,
        i_d6  => prescaler_reg,
        i_d7  => ZERO_WORD,
        i_sel => rd_sel,
        o_d   => o_data_out
      );

end architecture;