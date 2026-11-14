-- =============================================================================
-- Registrador de CRC-32 do Ethernet, um nibble ou um byte por ciclo
--
-- Guarda o estado do CRC-32 do IEEE 802.3. Com i_clear em '1' o estado volta a
-- CRC_INIT; com i_enable em '1' absorve i_nibble (bit 0 primeiro, como o MII o
-- envia) e, com i_wide em '1', também i_nibble_hi logo depois, o que absorve o
-- byte {i_nibble_hi, i_nibble} com o bit menos significativo primeiro, como o
-- GMII o envia. o_residue_ok vale '1' quando o estado é CRC_RESIDUE, ou seja,
-- quando os dados absorvidos formam um quadro com FCS íntegro. O FCS a
-- transmitir é o complemento de o_crc, byte menos significativo primeiro.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.eth_consts.all;

entity eth_crc32 is
    port (
        -- Clock do domínio.
        i_clk         : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst         : in    std_logic;
        -- Volta o estado ao valor inicial, ativo em '1'.
        i_clear       : in    std_logic;
        -- Absorve os dados neste ciclo, ativo em '1'.
        i_enable      : in    std_logic;
        -- Nibble a absorver, ou a metade baixa do byte.
        i_nibble      : in    std_logic_vector(3 downto 0);
        -- '1' absorve também i_nibble_hi, a metade alta do byte.
        i_wide        : in    std_logic := '0';
        -- Metade alta do byte, usada só com i_wide em '1'.
        i_nibble_hi   : in    std_logic_vector(3 downto 0) := (others => '0');
        -- Estado atual do CRC.
        o_crc         : out   std_logic_vector(31 downto 0);
        -- O estado é o resíduo de um quadro íntegro.
        o_residue_ok  : out   std_logic
    );
end entity eth_crc32;

architecture rtl of eth_crc32 is

    -- Estado do CRC.
    signal crc  : std_logic_vector(31 downto 0) := CRC_INIT;
    -- Estado depois do nibble baixo.
    signal low  : std_logic_vector(31 downto 0);
    -- Estado seguinte, depois de um nibble ou de um byte.
    signal next_crc : std_logic_vector(31 downto 0);

begin

    low      <= crc32_nibble(crc, i_nibble);
    next_crc <= crc32_nibble(low, i_nibble_hi) when i_wide = '1' else low;

    p_crc : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            if i_rst = '1' or i_clear = '1' then
                crc <= CRC_INIT;
            elsif i_enable = '1' then
                crc <= next_crc;
            end if;
        end if;

    end process p_crc;

    o_crc        <= crc;
    o_residue_ok <= '1' when crc = CRC_RESIDUE else '0';

end architecture rtl;
