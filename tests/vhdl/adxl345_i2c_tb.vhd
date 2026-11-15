-- =============================================================================
-- Testbench do adxl345_i2c com o barramento I2C acessível ao cocotb
--
-- Faz o papel do pull-up e do E ligado das linhas: cada linha vale '0' quando
-- o controlador ou o escravo simulado (i_slave_scl_low, i_slave_sda_low) a
-- puxa para baixo, e '1' caso contrário. o_scl e o_sda mostram o nível
-- resolvido, que também volta ao controlador. Os pinos de interrupção do chip
-- são entradas livres para o modelo do acelerômetro.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.config_pkg.all;

entity adxl345_i2c_tb is
    generic (
        -- Frequência de i_clk em Hz.
        clock_hz            : positive := 4_000_000;
        -- Frequência de SCL em Hz do divisor de reset.
        scl_hz              : positive := 200_000;
        -- Amostras por segundo depois do reset.
        sample_hz           : positive := 6666;
        -- Intervalo entre uma parada e o início seguinte, em nanossegundos.
        bus_free_ns         : positive := 1300;
        -- Verdadeiro com SDO em nível alto (endereço 0x1D).
        address_select_high : boolean  := false
    );
    port (
        -- Clock do módulo.
        i_clk           : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst           : in    std_logic;
        -- Pulso de escrita do processador.
        i_write         : in    std_logic;
        -- Endereço de palavra do registrador.
        i_address       : in    std_logic_vector(2 downto 0);
        -- Dado de escrita do processador.
        i_data_in       : in    word_t;
        -- Dado de leitura para o processador.
        o_data_out      : out   word_t;
        -- Requisição de interrupção.
        o_irq           : out   std_logic;
        -- Seleção de chip do acelerômetro.
        o_adxl_cs_n     : out   std_logic;
        -- Seleção de endereço do acelerômetro.
        o_adxl_sdo      : out   std_logic;
        -- Interrupção 1 do acelerômetro.
        i_adxl_int1     : in    std_logic;
        -- Interrupção 2 do acelerômetro.
        i_adxl_int2     : in    std_logic;
        -- O escravo simulado puxa SCL para baixo.
        i_slave_scl_low : in    std_logic;
        -- O escravo simulado puxa SDA para baixo.
        i_slave_sda_low : in    std_logic;
        -- Nível resolvido de SCL.
        o_scl           : out   std_logic;
        -- Nível resolvido de SDA.
        o_sda           : out   std_logic
    );
end entity adxl345_i2c_tb;

architecture rtl of adxl345_i2c_tb is

    -- O controlador puxa SCL para baixo.
    signal master_scl_low : std_logic;
    -- O controlador puxa SDA para baixo.
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

    u_dut : entity work.adxl345_i2c
        generic map (
            clock_hz            => clock_hz,
            scl_hz              => scl_hz,
            sample_hz           => sample_hz,
            bus_free_ns         => bus_free_ns,
            address_select_high => address_select_high
        )
        port map (
            i_clk          => i_clk,
            i_rst          => i_rst,
            i_data_in      => i_data_in,
            i_address      => i_address,
            i_write        => i_write,
            o_data_out     => o_data_out,
            o_irq          => o_irq,
            o_adxl_cs_n    => o_adxl_cs_n,
            o_adxl_sdo     => o_adxl_sdo,
            o_adxl_scl_low => master_scl_low,
            o_adxl_sda_low => master_sda_low,
            i_adxl_scl     => scl_line,
            i_adxl_sda     => sda_line,
            i_adxl_int1    => i_adxl_int1,
            i_adxl_int2    => i_adxl_int2
        );

end architecture rtl;
