-- ==========================================================================
-- Mestre SPI de um byte para cartão SD (modo 0)
-- ==========================================================================
-- Troca um byte por pedido de início, com o relógio SCLK em repouso em nível
-- baixo, a saída MOSI mudando na borda de descida e o cartão amostrando na
-- borda de subida (CPOL 0, CPHA 0, bit mais significativo primeiro). O
-- período de SCLK vale 2 * (divisor + 1) ciclos de i_clk, e o divisor é
-- capturado no início de cada byte. A entrada MISO é amostrada na borda de
-- descida de SCLK, o instante mais tardio do bit, e já deve estar sincronizada
-- com i_clk. Com a amostra tardia o divisor mínimo é 1 (SCLK = i_clk / 4).
-- Ao fim do byte o pulso o_done dura um ciclo e o_rx_data guarda o byte
-- recebido até o próximo byte.
-- ==========================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

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

    -- Indica um byte em andamento.
    signal busy      : std_logic;
    -- Pulso de fim de byte.
    signal done      : std_logic;
    -- Nível atual de SCLK.
    signal sclk      : std_logic;
    -- Registrador de deslocamento da transmissão, bit 7 na saída MOSI.
    signal tx_shift  : std_logic_vector(7 downto 0);
    -- Registrador de deslocamento da recepção.
    signal rx_shift  : std_logic_vector(7 downto 0);
    -- Bits que ainda faltam amostrar no byte.
    signal bits_left : natural range 0 to 8;
    -- Ciclos já contados na metade atual do período de SCLK.
    signal tick_cnt  : unsigned(divider_width - 1 downto 0);
    -- Divisor capturado no início do byte.
    signal divider   : unsigned(divider_width - 1 downto 0);

begin

    o_busy    <= busy;
    o_done    <= done;
    o_rx_data <= rx_shift;
    o_sclk    <= sclk;
    o_mosi    <= tx_shift(7);

    p_phy : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            done <= '0';

            if i_rst = '1' then
                busy      <= '0';
                sclk      <= '0';
                tx_shift  <= (others => '1');
                rx_shift  <= (others => '0');
                bits_left <= 0;
                tick_cnt  <= (others => '0');
                divider   <= (others => '0');
            elsif busy = '0' then
                if i_start = '1' then
                    busy      <= '1';
                    tx_shift  <= i_tx_data;
                    bits_left <= 8;
                    tick_cnt  <= (others => '0');
                    divider   <= unsigned(i_divider);
                end if;
            elsif tick_cnt /= divider then
                tick_cnt <= tick_cnt + 1;
            else
                tick_cnt <= (others => '0');
                sclk     <= not sclk;

                -- Borda de descida: amostra MISO e apresenta o próximo bit.
                if sclk = '1' then
                    rx_shift  <= rx_shift(6 downto 0) & i_miso;
                    tx_shift  <= tx_shift(6 downto 0) & '1';
                    bits_left <= bits_left - 1;

                    if bits_left = 1 then
                        busy <= '0';
                        done <= '1';
                    end if;
                end if;
            end if;
        end if;

    end process p_phy;

end architecture rtl;
