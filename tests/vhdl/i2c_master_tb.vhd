-- =============================================================================
-- Testbench do i2c_master com o barramento I2C acessível ao cocotb
--
-- Faz o papel do pull-up e do E ligado das linhas: cada linha vale
-- '0' quando o mestre ou o escravo simulado (i_slave_scl_low, i_slave_sda_low)
-- a puxa para baixo, e '1' caso contrário. o_scl e o_sda mostram o nível
-- resolvido, que também volta ao mestre pelas entradas i_scl e i_sda.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.config_pkg.all;

entity i2c_master_tb is
    generic (
        -- Frequência de i_clk em Hz.
        clk_freq : positive := 100_000_000;
        -- Frequência de SCL em Hz do divisor de reset.
        scl_freq : positive := 100_000
    );
    port (
        -- Clock do módulo.
        i_clk           : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst           : in    std_logic;
        -- Pulso de escrita do processador.
        i_write         : in    std_logic;
        -- Pulso de leitura do processador.
        i_read          : in    std_logic;
        -- Endereço de palavra do registrador.
        i_address       : in    std_logic_vector(2 downto 0);
        -- Dado de escrita do processador.
        i_data_in       : in    word_t;
        -- Dado de leitura para o processador.
        o_data_out      : out   word_t;
        -- Requisição de interrupção.
        o_irq           : out   std_logic;
        -- O escravo simulado puxa SCL para baixo.
        i_slave_scl_low : in    std_logic;
        -- O escravo simulado puxa SDA para baixo.
        i_slave_sda_low : in    std_logic;
        -- Nível resolvido de SCL.
        o_scl           : out   std_logic;
        -- Nível resolvido de SDA.
        o_sda           : out   std_logic
    );
end entity i2c_master_tb;

architecture rtl of i2c_master_tb is

    -- O mestre puxa SCL para baixo.
    signal master_scl_low : std_logic;
    -- O mestre puxa SDA para baixo.
    signal master_sda_low : std_logic;
    -- Nível resolvido de SCL.
    signal scl_line       : std_logic;
    -- Nível resolvido de SDA.
    signal sda_line       : std_logic;

begin

    scl_line <= '0' when master_scl_low = '1' or i_slave_scl_low = '1' else '1';
    sda_line <= '0' when master_sda_low = '1' or i_slave_sda_low = '1' else '1';
    o_scl    <= scl_line;
    o_sda    <= sda_line;

    u_dut : entity work.i2c_master
        generic map (
            clk_freq => clk_freq,
            scl_freq => scl_freq
        )
        port map (
            i_clk      => i_clk,
            i_rst      => i_rst,
            i_write    => i_write,
            i_read     => i_read,
            i_address  => i_address,
            i_data_in  => i_data_in,
            o_data_out => o_data_out,
            o_irq      => o_irq,
            o_scl_low  => master_scl_low,
            o_sda_low  => master_sda_low,
            i_scl      => scl_line,
            i_sda      => sda_line
        );

end architecture rtl;
