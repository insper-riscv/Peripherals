-- =============================================================================
-- Grupo de E/S de uso geral: um arquivo de registradores sobre 1 a 32 pinos
--
-- Integra uma gpio_cell por pino, o decodificador das operações mapeadas em
-- memória e o multiplexador da leitura de volta. O bit k de cada registrador é o
-- pino k do grupo. Os bits acima de width leem zero e ignoram a escrita. O grupo
-- não toca os pinos físicos: entrega, por pino, o valor dirigido e a habilitação
-- do tristate, e recebe o valor do pino. O bloco gpio liga um grupo aos pinos.
-- Cada pino tem direção (livre, só entrada, só saída) e polaridade próprias.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.config_pkg.all;
use work.gpio_pkg.all;

entity gpio_group is
    generic (
        -- Pinos do grupo, de 1 a 32.
        width      : positive range 1 to 32 := 32;
        -- Direção de cada pino, 2 bits por pino (0 livre, 1 só entrada, 2 só saída); o pino k ocupa os bits 2k+1 a 2k.
        dir_modes  : std_logic_vector(2 * width - 1 downto 0) := (others => '0');
        -- Polaridade de cada pino: '1' é ativo em nível baixo e '0' é ativo em nível alto.
        active_low : std_logic_vector(width - 1 downto 0) := (others => '0')
    );
    port (
        -- Clock do módulo.
        i_clk : in    std_logic;

        -- Reset, ativo em '1'.
        i_rst : in    std_logic;

        -- Dado de escrita vindo do processador.
        i_data_in : in    word_t;

        -- Endereço de palavra dentro do grupo (0 a 15).
        i_address : in    std_logic_vector(3 downto 0);

        -- Pulso de escrita do processador ('1' = escreve).
        i_write : in    std_logic;

        -- Pulso de leitura do processador ('1' = lê).
        i_read : in    std_logic;

        -- Dado de leitura para o processador.
        o_data_out : out   word_t;

        -- Requisição de interrupção, ativa em '1'.
        o_irq : out   std_logic;

        -- Valor de cada pino físico.
        i_pins : in    std_logic_vector(width - 1 downto 0);

        -- Valor que a célula dirige a cada pino.
        o_pins_drv : out   std_logic_vector(width - 1 downto 0);

        -- Habilitação do tristate de cada pino ('1' dirige, '0' solta).
        o_pins_en : out   std_logic_vector(width - 1 downto 0)
    );
end entity gpio_group;

architecture rtl of gpio_group is

    -- Habilitações de escrita dos registradores.
    signal wr_en  : std_logic_vector(7 downto 0);
    -- Operação do registrador de saída.
    signal wr_op  : std_logic_vector(1 downto 0);
    -- Seletor do multiplexador de leitura.
    signal rd_sel : std_logic_vector(2 downto 0);

    -- Registrador de direção de todas as células.
    signal dir_reg       : std_logic_vector(width - 1 downto 0);
    -- Registrador de saída de todas as células.
    signal out_reg       : std_logic_vector(width - 1 downto 0);
    -- Entradas dos pinos sincronizadas.
    signal pins_input    : std_logic_vector(width - 1 downto 0);
    -- Máscaras globais de interrupção de todas as células.
    signal irq_mask      : std_logic_vector(width - 1 downto 0);
    -- Máscaras de borda de subida de todas as células.
    signal irq_rise_mask : std_logic_vector(width - 1 downto 0);
    -- Máscaras de borda de descida de todas as células.
    signal irq_fall_mask : std_logic_vector(width - 1 downto 0);
    -- Status de interrupção de todas as células.
    signal irq_status    : std_logic_vector(width - 1 downto 0);
    -- Modos de nível de todas as células.
    signal irq_level     : std_logic_vector(width - 1 downto 0);
    -- O endereço lido é o do modo de nível.
    signal rd_level      : std_logic;
    -- Modo de nível entregue ao multiplexador de leitura (zero fora do seu endereço).
    signal level_read    : std_logic_vector(width - 1 downto 0);

    -- Estado interno de cada célula, oito bits por célula.
    type dout_array_t is array (0 to width - 1) of std_logic_vector(7 downto 0);

    -- Estado interno lido de cada célula.
    signal dout_array : dout_array_t;

    -- Dado de leitura escolhido pelo seletor.
    signal   selected_read : std_logic_vector(width - 1 downto 0);
    -- Dado de escrita dos pinos do grupo (os bits baixos da palavra).
    signal   data_pins     : std_logic_vector(width - 1 downto 0);
    -- Vetor de zeros para as leituras não usadas.
    constant ZERO_VECTOR   : std_logic_vector(width - 1 downto 0) := (others => '0');

begin

    data_pins <= i_data_in(width - 1 downto 0);

    -----------------------------------------------------------------------------
    -- Decodificador de operações do GPIO
    -----------------------------------------------------------------------------
    u_gpio_operation_decoder : entity work.gpio_operation_decoder
        port map (
            i_address  => i_address,
            i_write    => i_write,
            i_read     => i_read,
            o_wr_en    => wr_en,
            o_wr_op    => wr_op,
            o_rd_sel   => rd_sel,
            o_rd_level => rd_level
        );

    -----------------------------------------------------------------------------
    -- Instâncias de gpio_cell, uma por pino
    -----------------------------------------------------------------------------

    gen_cells : for i in 0 to width - 1 generate
    begin

        u_gpio_cell : entity work.gpio_cell
            generic map (
                dir_mode   => to_mode(dir_modes(2 * i + 1 downto 2 * i)),
                active_low => active_low(i) = '1'
            )
            port map (
                i_clk        => i_clk,
                i_rst        => i_rst,
                i_data_in    => data_pins(i),
                o_data_out   => dout_array(i),
                i_wr_signals => wr_en,
                i_wr_op      => wr_op,
                i_pin        => i_pins(i),
                o_pin_drv    => o_pins_drv(i),
                o_pin_en     => o_pins_en(i)
            );

        dir_reg(i)       <= dout_array(i)(0);
        out_reg(i)       <= dout_array(i)(1);
        pins_input(i)    <= dout_array(i)(2);
        irq_mask(i)      <= dout_array(i)(3);
        irq_rise_mask(i) <= dout_array(i)(4);
        irq_fall_mask(i) <= dout_array(i)(5);
        irq_status(i)    <= dout_array(i)(6);
        irq_level(i)     <= dout_array(i)(7);
    end generate gen_cells;

    -----------------------------------------------------------------------------
    -- Multiplexador de leitura
    -----------------------------------------------------------------------------
    u_read_mux : entity work.mux_8x1
        generic map (
            data_width => width
        )
        port map (
            i_d0  => dir_reg,
            i_d1  => out_reg,
            i_d2  => pins_input,
            i_d3  => irq_status,
            i_d4  => irq_mask,
            i_d5  => irq_rise_mask,
            i_d6  => irq_fall_mask,
            i_d7  => level_read,
            i_sel => rd_sel,
            o_d   => selected_read
        );

    level_read <= irq_level when rd_level = '1' else ZERO_VECTOR;

    -- Os bits acima de width leem zero.
    p_read_pad : process (selected_read) is
    begin

        o_data_out                  <= (others => '0');
        o_data_out(width - 1 downto 0) <= selected_read;

    end process p_read_pad;

    -----------------------------------------------------------------------------
    -- Lógica de geração da interrupção.
    -- A interrupção sobe se qualquer bit de status de interrupção estiver ligado (OU de redução).
    -----------------------------------------------------------------------------
    o_irq <= '1' when irq_status /= ZERO_VECTOR else '0';

end architecture rtl;
