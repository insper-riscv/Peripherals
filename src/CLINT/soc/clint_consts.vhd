-- =============================================================================
-- Constantes do CLINT
--
-- Endereços de palavra (deslocamento em palavras dentro do periférico) dos
-- registradores do CLINT, no leiaute do CLINT da SiFive que o porte do FreeRTOS
-- espera, e o valor de reset do mtimecmp.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

package clint_consts is

    -- Largura em bits do endereço de palavra do CLINT (64 KiB em bytes).
    constant CLINT_ADDR_WIDTH : natural := 14;

    -- Endereço de palavra do msip (deslocamento 0x0000 em bytes).
    constant ADDR_MSIP        : std_logic_vector(CLINT_ADDR_WIDTH - 1 downto 0) := "00000000000000";
    -- Endereço de palavra da metade baixa do mtimecmp (deslocamento 0x4000 em bytes).
    constant ADDR_MTIMECMP_LO : std_logic_vector(CLINT_ADDR_WIDTH - 1 downto 0) := "01000000000000";
    -- Endereço de palavra da metade alta do mtimecmp (deslocamento 0x4004 em bytes).
    constant ADDR_MTIMECMP_HI : std_logic_vector(CLINT_ADDR_WIDTH - 1 downto 0) := "01000000000001";
    -- Endereço de palavra da metade baixa do mtime (deslocamento 0xBFF8 em bytes).
    constant ADDR_MTIME_LO    : std_logic_vector(CLINT_ADDR_WIDTH - 1 downto 0) := "10111111111110";
    -- Endereço de palavra da metade alta do mtime (deslocamento 0xBFFC em bytes).
    constant ADDR_MTIME_HI    : std_logic_vector(CLINT_ADDR_WIDTH - 1 downto 0) := "10111111111111";

end package clint_consts;
