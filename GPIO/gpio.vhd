-- =============================================================================
-- Módulo de E/S de uso geral
--
-- Liga o processador a um conjunto de pinos bidirecionais. Integra várias
-- instâncias de gpio_cell, um decodificador das operações mapeadas em memória e
-- um multiplexador para a leitura de volta. Suporta controle de direção,
-- operações de saída e configuração de interrupção. A lógica interna depende de
-- data_width.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

library work;

entity gpio is
    generic (
        -- Largura do barramento de dados em bits.
        data_width : natural := 32
    );
    port (
        -- Clock do módulo.
        i_clk       : in  std_logic;

        -- Reset, ativo em '1'.
        i_rst       : in  std_logic; 

        -- Dado de escrita vindo do processador.
        i_data_in     : in  std_logic_vector(data_width-1 downto 0);

        -- Endereço de palavra acessado pelo processador.
        i_address     : in  std_logic_vector(3 downto 0);

        -- Pulso de escrita do processador ('1' = escreve).
        i_write       : in  std_logic; 

        -- Pulso de leitura do processador ('1' = lê).
        i_read        : in  std_logic; 

        -- Dado de leitura para o processador.
        o_data_out    : out std_logic_vector(data_width-1 downto 0);

        -- Requisição de interrupção, ativa em '1'.
        o_irq         : out std_logic;

        -- Pinos de E/S físicos (bidirecionais).
        io_gpio_pins   : inout std_logic_vector(data_width-1 downto 0)
    );
end gpio;

architecture rtl of gpio is

    -- Habilitações de escrita dos registradores.
    signal wr_en   : std_logic_vector(6 downto 0);
    -- Operação do registrador de saída.
    signal wr_op   : std_logic_vector(1 downto 0);
    -- Seletor do multiplexador de leitura.
    signal rd_sel  : std_logic_vector(2 downto 0);

    -- Registrador de direção de todas as células.
    signal dir_reg         : std_logic_vector(data_width-1 downto 0);
    -- Registrador de saída de todas as células.
    signal out_reg         : std_logic_vector(data_width-1 downto 0);
    -- Entradas dos pinos sincronizadas.
    signal pins_input      : std_logic_vector(data_width-1 downto 0);
    -- Máscaras globais de interrupção de todas as células.
    signal irq_mask        : std_logic_vector(data_width-1 downto 0);
    -- Máscaras de borda de subida de todas as células.
    signal irq_rise_mask   : std_logic_vector(data_width-1 downto 0);
    -- Máscaras de borda de descida de todas as células.
    signal irq_fall_mask   : std_logic_vector(data_width-1 downto 0);
    -- Status de interrupção de todas as células.
    signal irq_status      : std_logic_vector(data_width-1 downto 0);

    -- Estado interno de cada célula, sete bits por célula.
    type dout_array_t is array (0 to data_width - 1) of std_logic_vector(6 downto 0);
    -- Estado interno lido de cada célula.
    signal dout_array : dout_array_t;

    -- Dado de leitura escolhido pelo seletor.
    signal selected_read : std_logic_vector(data_width-1 downto 0);
    -- Vetor de zeros para as leituras não usadas.
    constant ZERO_VECTOR : std_logic_vector(data_width-1 downto 0) := (others => '0');

begin

    -----------------------------------------------------------------------------
    -- Decodificador de operações do GPIO
    -----------------------------------------------------------------------------
    u_gpio_operation_decoder : entity work.gpio_operation_decoder
        port map (
            i_address => i_address,
            i_write   => i_write,
            i_read    => i_read,
            o_wr_en   => wr_en,
            o_wr_op   => wr_op,
            o_rd_sel  => rd_sel
        );

    -----------------------------------------------------------------------------
    -- Instâncias de gpio_cell, uma por pino
    -----------------------------------------------------------------------------
    gen_cells : for i in 0 to data_width - 1 generate
    begin
        u_gpio_cell : entity work.gpio_cell
            port map (
                i_clk      => i_clk,
                i_rst      => i_rst,
                i_data_in    => i_data_in(i),
                o_data_out   => dout_array(i),
                i_wr_signals => wr_en,
                i_wr_op      => wr_op,
                io_gpio_pin   => io_gpio_pins(i)
            );

        dir_reg(i)        <= dout_array(i)(0);
        out_reg(i)        <= dout_array(i)(1);
        pins_input(i)     <= dout_array(i)(2);
        irq_mask(i)       <= dout_array(i)(3);
        irq_rise_mask(i)  <= dout_array(i)(4);
        irq_fall_mask(i)  <= dout_array(i)(5);
        irq_status(i)     <= dout_array(i)(6);
    end generate;

    -----------------------------------------------------------------------------
    -- Multiplexador de leitura
    -----------------------------------------------------------------------------
    u_read_mux : entity work.mux_8x1
      generic map (
        data_width => data_width
      )
      port map (
        i_d0  => dir_reg,
        i_d1  => out_reg,
        i_d2  => pins_input,
        i_d3  => irq_status,
        i_d4  => irq_mask,
        i_d5  => irq_rise_mask,
        i_d6  => irq_fall_mask,
        i_d7  => ZERO_VECTOR,
        i_sel => rd_sel,
        o_d   => selected_read
      );
    o_data_out <= selected_read;
    -----------------------------------------------------------------------------
    -- Lógica de geração da interrupção.
    -- A interrupção sobe se qualquer bit de status de interrupção estiver ligado (OU de redução).
    -----------------------------------------------------------------------------
    o_irq <= '1' when irq_status /= ZERO_VECTOR else '0';

end architecture;