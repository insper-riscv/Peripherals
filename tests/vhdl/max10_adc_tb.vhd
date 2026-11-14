-- =============================================================================
-- Testbench do max10_adc com o modelo do núcleo do ADC
--
-- Liga o periférico ao modelo comportamental de altera_modular_adc e deixa ao
-- cocotb o barramento, o valor de cada canal (i_analog) e os sinais de comando
-- do núcleo, para que ele confira a ordem, o startofpacket e o endofpacket dos
-- comandos.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.config_pkg.all;
use work.max10_adc_consts.all;

entity max10_adc_tb is
    generic (
        -- Frequência de i_clk em Hz.
        clk_freq          : positive := 100_000_000;
        -- Frequência de varredura em Hz do período de reset.
        scan_freq         : positive := 1000;
        -- Ciclos de clock de uma conversão do modelo.
        conversion_cycles : positive := 12;
        -- A resposta do modelo sai um ciclo depois do ready.
        rsp_late          : boolean  := false
    );
    port (
        -- Clock do módulo.
        i_clk         : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst         : in    std_logic;
        -- Pulso de escrita do processador.
        i_write       : in    std_logic;
        -- Pulso de leitura do processador.
        i_read        : in    std_logic;
        -- Endereço de palavra do registrador.
        i_address     : in    std_logic_vector(ADC_ADDR_BITS - 1 downto 0);
        -- Dado de escrita do processador.
        i_data_in     : in    word_t;
        -- Dado de leitura para o processador.
        o_data_out    : out   word_t;
        -- Requisição de interrupção.
        o_irq         : out   std_logic;
        -- Valor de cada canal do conversor, 12 bits por canal.
        i_analog      : in    std_logic_vector(ADC_CHANNELS * ADC_SAMPLE_BITS - 1 downto 0);
        -- Comando válido para o núcleo.
        o_cmd_valid   : out   std_logic;
        -- Número do canal do comando.
        o_cmd_channel : out   std_logic_vector(ADC_CHANNEL_BITS - 1 downto 0);
        -- Primeiro comando da varredura.
        o_cmd_sop     : out   std_logic;
        -- Último comando da varredura.
        o_cmd_eop     : out   std_logic;
        -- O núcleo aceitou o comando.
        o_cmd_ready   : out   std_logic
    );
end entity max10_adc_tb;

architecture rtl of max10_adc_tb is

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

    o_cmd_valid   <= cmd_valid;
    o_cmd_channel <= cmd_channel;
    o_cmd_sop     <= cmd_sop;
    o_cmd_eop     <= cmd_eop;
    o_cmd_ready   <= cmd_ready;

    u_dut : entity work.max10_adc
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

    u_model : entity work.max10_adc_core_model
        generic map (
            conversion_cycles => conversion_cycles,
            rsp_late          => rsp_late
        )
        port map (
            i_clk         => i_clk,
            i_rst         => i_rst,
            i_analog      => i_analog,
            i_cmd_valid   => cmd_valid,
            i_cmd_channel => cmd_channel,
            i_cmd_sop     => cmd_sop,
            i_cmd_eop     => cmd_eop,
            o_cmd_ready   => cmd_ready,
            o_rsp_valid   => rsp_valid,
            o_rsp_channel => rsp_channel,
            o_rsp_data    => rsp_data,
            o_rsp_sop     => open,
            o_rsp_eop     => open
        );

end architecture rtl;
