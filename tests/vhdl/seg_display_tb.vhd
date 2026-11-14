-- =============================================================================
-- Testbench do seg_display com a partição escrita em texto
--
-- Liga o seg_display com uma partição em texto (ver gpio_partition_pkg), com os
-- generics digits e active_low, e expõe todas as portas do módulo.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.config_pkg.all;
use work.gpio_partition_pkg.all;

entity seg_display_tb is
    generic (
        -- Número de dígitos do display.
        digits     : positive range 1 to 8 := 6;
        -- Segmentos acesos em nível baixo quando verdadeiro.
        active_low : boolean               := true;
        -- Partição em texto: índices de dígito separados por vírgula e grupos separados por barra.
        partition  : string                := "0,1,2,3,4,5";
        -- Dígitos de oito segmentos (com o ponto decimal) quando verdadeiro.
        has_dp     : boolean               := false
    );
    port (
        -- Clock do core.
        i_clk     : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst     : in    std_logic;
        -- Endereço de palavra dentro da janela do periférico.
        i_address : in    std_logic_vector(7 downto 0);
        -- Dado escrito pelo core.
        i_data_in : in    word_t;
        -- Pulso de escrita do core.
        i_write   : in    std_logic;
        -- Dado lido pelo core.
        o_rdata   : out   word_t;
        -- Clock da cadeia JTAG.
        i_tck       : in    std_logic;
        -- Dado serial vindo do hospedeiro.
        i_tdi       : in    std_logic;
        -- Dado serial para o hospedeiro.
        o_tdo       : out   std_logic;
        -- Registrador de instrução do Virtual JTAG.
        i_ir_in     : in    std_logic_vector(1 downto 0);
        -- Estado Capture-DR da cadeia virtual.
        i_state_cdr : in    std_logic;
        -- Estado Shift-DR da cadeia virtual.
        i_state_sdr : in    std_logic;
        -- Estado Update-DR da cadeia virtual.
        i_state_udr : in    std_logic;
        -- Estado Update-IR da cadeia virtual.
        i_state_uir : in    std_logic;
        -- Bandeira de falha gravada pelo hospedeiro.
        o_fail      : out   std_logic;
        -- Valor guardado, quatro bits por dígito.
        o_value   : out   std_logic_vector(4 * digits - 1 downto 0);
        -- Segmentos dos dígitos, sete bits por dígito (oito com has_dp, o ponto no bit 7).
        o_hex     : out   std_logic_vector((7 + boolean'pos(has_dp)) * digits - 1 downto 0);
        -- Bits do ponto decimal guardados, um por dígito.
        o_dp      : out   std_logic_vector(digits - 1 downto 0)
    );
end entity seg_display_tb;

architecture rtl of seg_display_tb is

begin

    u_dut : entity work.seg_display
        generic map (
            digits        => digits,
            active_low    => active_low,
            group_count   => count_groups(partition),
            member_count  => count_members(partition),
            group_sizes   => encode_sizes(partition),
            group_members => encode_members(partition),
            has_dp        => has_dp
        )
        port map (
            i_clk       => i_clk,
            i_rst       => i_rst,
            i_address   => i_address,
            i_data_in   => i_data_in,
            i_write     => i_write,
            o_rdata     => o_rdata,
            i_tck       => i_tck,
            i_tdi       => i_tdi,
            o_tdo       => o_tdo,
            i_ir_in     => i_ir_in,
            i_state_cdr => i_state_cdr,
            i_state_sdr => i_state_sdr,
            i_state_udr => i_state_udr,
            i_state_uir => i_state_uir,
            o_value     => o_value,
            o_fail      => o_fail,
            o_hex       => o_hex,
            o_dp        => o_dp
        );

end architecture rtl;
