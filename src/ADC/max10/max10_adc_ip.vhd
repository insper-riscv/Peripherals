-- =============================================================================
-- Instância do IP altera_modular_adc gerado (max10_adc_core)
--
-- Exclusiva da placa e fina de propósito: só declara e instancia o IP que o
-- script ip/generate.sh gera com o Platform Designer (variante autônoma do
-- núcleo, só com a interface Avalon-ST de comando e resposta). O IP é Verilog
-- do Quartus, sem entidade visível ao VHDL do projeto, por isso entra como
-- component (como o sld_virtual_jtag do virtual_jtag). O nome e as portas do
-- component são os do arquivo max10_adc_core.vhd que o gerador escreve, e este
-- arquivo não é analisado pelo GHDL; nas simulações, tests/vhdl/
-- max10_adc_core_model.vhd faz o papel do IP.
--
-- O reset do IP é ativo em '0'. O clock do IP é o do barramento, e o do
-- conversor vem do PLL de 10 MHz (i_adc_clk e i_adc_locked).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.max10_adc_consts.all;

entity max10_adc_ip is
    port (
        -- Clock do barramento e do controle do núcleo.
        i_clk         : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst         : in    std_logic;
        -- Clock de 10 MHz do conversor, saída C0 do PLL.
        i_adc_clk     : in    std_logic;
        -- O PLL do conversor travou.
        i_adc_locked  : in    std_logic;
        -- Comando válido.
        i_cmd_valid   : in    std_logic;
        -- Número do canal do comando.
        i_cmd_channel : in    std_logic_vector(ADC_CHANNEL_BITS - 1 downto 0);
        -- Primeiro comando do pacote.
        i_cmd_sop     : in    std_logic;
        -- Último comando do pacote.
        i_cmd_eop     : in    std_logic;
        -- Comando aceito.
        o_cmd_ready   : out   std_logic;
        -- Resposta válida.
        o_rsp_valid   : out   std_logic;
        -- Número do canal da resposta.
        o_rsp_channel : out   std_logic_vector(ADC_CHANNEL_BITS - 1 downto 0);
        -- Amostra da resposta.
        o_rsp_data    : out   std_logic_vector(ADC_SAMPLE_BITS - 1 downto 0)
    );
end entity max10_adc_ip;

architecture rtl of max10_adc_ip is

    -- Declaração do IP, como o gerador a escreve.
    component max10_adc_core is
        port (
            adc_pll_clock_clk      : in    std_logic;
            adc_pll_locked_export  : in    std_logic;
            clock_clk              : in    std_logic;
            command_valid          : in    std_logic;
            command_channel        : in    std_logic_vector(4 downto 0);
            command_startofpacket  : in    std_logic;
            command_endofpacket    : in    std_logic;
            command_ready          : out   std_logic;
            reset_reset_n          : in    std_logic;
            response_valid         : out   std_logic;
            response_channel       : out   std_logic_vector(4 downto 0);
            response_data          : out   std_logic_vector(11 downto 0);
            response_startofpacket : out   std_logic;
            response_endofpacket   : out   std_logic
        );
    end component max10_adc_core;

    -- Reset do IP, ativo em '0'.
    signal reset_n    : std_logic;
    -- Startofpacket da resposta, não usado.
    signal unused_sop : std_logic;
    -- Endofpacket da resposta, não usado.
    signal unused_eop : std_logic;

begin

    reset_n <= not i_rst;

    u_core : component max10_adc_core
        port map (
            adc_pll_clock_clk      => i_adc_clk,
            adc_pll_locked_export  => i_adc_locked,
            clock_clk              => i_clk,
            command_valid          => i_cmd_valid,
            command_channel        => i_cmd_channel,
            command_startofpacket  => i_cmd_sop,
            command_endofpacket    => i_cmd_eop,
            command_ready          => o_cmd_ready,
            reset_reset_n          => reset_n,
            response_valid         => o_rsp_valid,
            response_channel       => o_rsp_channel,
            response_data          => o_rsp_data,
            response_startofpacket => unused_sop,
            response_endofpacket   => unused_eop
        );

end architecture rtl;
