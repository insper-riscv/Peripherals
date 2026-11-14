-- ==========================================================================
-- Mestre SPI de um byte para cartão SD (modo 0)
-- ==========================================================================
-- Fixa o mestre SPI genérico no que o cartão SD exige: CPOL 0 e CPHA 0
-- (SCLK em repouso em nível baixo, MOSI mudando na borda de descida e o
-- cartão amostrando na de subida), palavra de 8 bits e bit mais significativo
-- primeiro. O período de SCLK vale 2 * (divisor + 1) ciclos de i_clk, o divisor
-- é capturado no início de cada byte e o divisor mínimo é 1 (SCLK = i_clk / 4),
-- porque MISO é amostrada na borda de descida e já deve estar sincronizada.
-- Ao fim do byte o pulso o_done dura um ciclo e o_rx_data guarda o byte
-- recebido até o próximo byte.
-- ==========================================================================

library ieee;
use ieee.std_logic_1164.all;

entity sd_spi_phy is
    generic (
        -- Largura do divisor de clock, em bits.
        divider_width : positive := 16
    );
    port (
        -- Clock do módulo.
        i_clk     : in    std_logic;
        -- Reset síncrono, ativo em nível alto.
        i_rst     : in    std_logic;
        -- Metade do período de SCLK menos um, em ciclos de i_clk.
        i_divider : in    std_logic_vector(divider_width - 1 downto 0);
        -- Pedido de início de um byte, aceito apenas com o_busy em '0'.
        i_start   : in    std_logic;
        -- Byte a transmitir, capturado junto com o pedido de início.
        i_tx_data : in    std_logic_vector(7 downto 0);
        -- Indica um byte em andamento.
        o_busy    : out   std_logic;
        -- Pulso de um ciclo no fim do byte.
        o_done    : out   std_logic;
        -- Byte recebido, válido a partir de o_done.
        o_rx_data : out   std_logic_vector(7 downto 0);
        -- Relógio serial do cartão.
        o_sclk    : out   std_logic;
        -- Dado serial para o cartão.
        o_mosi    : out   std_logic;
        -- Dado serial do cartão, já sincronizado com i_clk.
        i_miso    : in    std_logic
    );
end entity sd_spi_phy;

architecture rtl of sd_spi_phy is

    -- Largura da palavra do cartão, em bits, no formato do mestre genérico.
    constant WORD_BITS : std_logic_vector(5 downto 0) := "001000";

begin

    u_master : entity work.spi_master
        generic map (
            divider_width => divider_width,
            word_width    => 8
        )
        port map (
            i_clk       => i_clk,
            i_rst       => i_rst,
            i_cpol      => '0',
            i_cpha      => '0',
            i_lsb_first => '0',
            i_word_bits => WORD_BITS,
            i_divider   => i_divider,
            i_tx_drive  => '1',
            i_start     => i_start,
            i_tx_data   => i_tx_data,
            o_busy      => o_busy,
            o_done      => o_done,
            o_rx_data   => o_rx_data,
            o_sclk      => o_sclk,
            o_mosi      => o_mosi,
            o_mosi_oe   => open,
            i_miso      => i_miso
        );

end architecture rtl;
