-- =============================================================================
-- Periférico do ADC do MAX 10 com o PLL e o núcleo do conversor
--
-- Topo estrutural da placa: liga o max10_adc (registradores e sequenciador) ao
-- núcleo altera_modular_adc (max10_adc_ip) e o PLL de 10 MHz (max10_adc_pll,
-- em Verilog, instanciado como component) ao clock do conversor. Só conecta;
-- a plataforma ainda liga o pino ADC_CLK_10 a i_adc_clk_10 e o barramento do
-- SoC. As entradas analógicas (ANAIN1 e ADC1IN1 a ADC1IN8) não têm porta nem
-- atribuição de pino: o Quartus as liga ao bloco do conversor pelo próprio IP.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.config_pkg.all;
use work.max10_adc_consts.all;

entity max10_adc_shell is
    generic (
        -- Frequência de i_clk em Hz.
        clk_freq  : positive := 100_000_000;
        -- Frequência de varredura em Hz que o período tem ao sair do reset.
        scan_freq : positive := 1000
    );
    port (
        -- Clock do módulo.
        i_clk        : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst        : in    std_logic;
        -- Clock de 10 MHz do conversor (pino ADC_CLK_10).
        i_adc_clk_10 : in    std_logic;
        -- Pulso de escrita do processador.
        i_write      : in    std_logic;
        -- Pulso de leitura do processador.
        i_read       : in    std_logic;
        -- Endereço de palavra do registrador.
        i_address    : in    std_logic_vector(ADC_ADDR_BITS - 1 downto 0);
        -- Dado de escrita do processador.
        i_data_in    : in    word_t;
        -- Dado de leitura para o processador.
        o_data_out   : out   word_t;
        -- Requisição de interrupção de nível.
        o_irq        : out   std_logic
    );
end entity max10_adc_shell;

architecture rtl of max10_adc_shell is

    -- PLL de 10 MHz do conversor, escrito em Verilog em max10_adc_pll.v.
    component max10_adc_pll is
        port (
            i_clk_10  : in    std_logic;
            o_adc_clk : out   std_logic;
            o_locked  : out   std_logic
        );
    end component max10_adc_pll;

    -- Clock de 10 MHz do conversor.
    signal adc_clk     : std_logic;
    -- O PLL do conversor travou.
    signal adc_locked  : std_logic;
    -- Comando válido do periférico ao núcleo.
    signal cmd_valid   : std_logic;
    -- Canal do comando.
    signal cmd_channel : std_logic_vector(ADC_CHANNEL_BITS - 1 downto 0);
    -- Primeiro comando.
    signal cmd_sop     : std_logic;
    -- Último comando.
    signal cmd_eop     : std_logic;
    -- Comando aceito.
    signal cmd_ready   : std_logic;
    -- Resposta válida do núcleo.
    signal rsp_valid   : std_logic;
    -- Canal da resposta.
    signal rsp_channel : std_logic_vector(ADC_CHANNEL_BITS - 1 downto 0);
    -- Amostra da resposta.
    signal rsp_data    : std_logic_vector(ADC_SAMPLE_BITS - 1 downto 0);

begin

    u_pll : component max10_adc_pll
        port map (
            i_clk_10  => i_adc_clk_10,
            o_adc_clk => adc_clk,
            o_locked  => adc_locked
        );

    u_core : entity work.max10_adc_ip
        port map (
            i_clk         => i_clk,
            i_rst         => i_rst,
            i_adc_clk     => adc_clk,
            i_adc_locked  => adc_locked,
            i_cmd_valid   => cmd_valid,
            i_cmd_channel => cmd_channel,
            i_cmd_sop     => cmd_sop,
            i_cmd_eop     => cmd_eop,
            o_cmd_ready   => cmd_ready,
            o_rsp_valid   => rsp_valid,
            o_rsp_channel => rsp_channel,
            o_rsp_data    => rsp_data
        );

    u_adc : entity work.max10_adc
        generic map (
            clk_freq  => clk_freq,
            scan_freq => scan_freq
        )
        port map (
            i_clk         => i_clk,
            i_rst         => i_rst,
            i_write       => i_write,
            i_read        => i_read,
            i_address     => i_address,
            i_data_in     => i_data_in,
            o_data_out    => o_data_out,
            o_irq         => o_irq,
            o_cmd_valid   => cmd_valid,
            o_cmd_channel => cmd_channel,
            o_cmd_sop     => cmd_sop,
            o_cmd_eop     => cmd_eop,
            i_cmd_ready   => cmd_ready,
            i_rsp_valid   => rsp_valid,
            i_rsp_channel => rsp_channel,
            i_rsp_data    => rsp_data
        );

end architecture rtl;
