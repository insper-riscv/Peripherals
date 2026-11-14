-- =============================================================================
-- Saída de áudio HDMI pelo barramento I2S do transmissor ADV7513
--
-- Liga o processador à entrada de áudio I2S do transmissor HDMI de uma placa
-- (ADV7513 da DE10-Nano: HDMI_MCLK, HDMI_SCLK, HDMI_LRCLK e HDMI_I2S0). É um
-- invólucro fino sobre o periférico de áudio I2S (entidade audio), usado no modo
-- mestre e só para reprodução: o periférico gera o clock mestre, o clock de bit
-- e o clock de canal, serializa as amostras estéreo da fila (ou do tom de teste)
-- e entrega os quatro sinais. O invólucro só calcula os generics do bloco de
-- áudio a partir da taxa de amostragem, da razão MCLK/LRCLK e da largura da
-- palavra, e fixa o que não existe nesta direção: nenhuma entrada de áudio, nenhum
-- clock de entrada e nenhum sinal de habilitação de saída.
--
-- Temporização gerada (slot de 32 ciclos de SCLK por canal):
--   LRCLK = fs, SCLK = 64 * fs, MCLK = mclk_ratio * fs
-- com fs = sample_rate. O formato é I2S padrão: LRCLK em '0' no canal esquerdo,
-- bit mais significativo um ciclo de SCLK depois da troca do LRCLK, dado trocando
-- na borda de descida de SCLK. A palavra de 16 ou 24 bits sai alinhada à esquerda
-- no slot de 32 bits, com zeros no resto.
--
-- A configuração do transmissor (registradores de áudio do ADV7513) é feita pelo
-- I2C, fora deste periférico, pelo software ou pela tabela de áudio do
-- sequenciador do hdmi_tx. O mapa de registradores é o do periférico de áudio,
-- em endereços de palavra de 4 bits (docs/pt-br/audio). A fila de gravação do
-- bloco de áudio fica sem uso, com a profundidade mínima e a entrada em '0'.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.config_pkg.all;

entity hdmi_audio is
    generic (
        -- Frequência do clock do sistema em Hz (no mínimo o dobro da frequência do MCLK).
        clk_freq      : positive := 100_000_000;
        -- Taxa de amostragem no reset, em Hz: 32000, 44100 ou 48000.
        sample_rate   : positive := 48_000;
        -- Razão MCLK/LRCLK no reset: 128 ou 256.
        mclk_ratio    : positive := 256;
        -- Largura da palavra no reset: 16 ou 24 bits.
        word_bits     : positive := 24;
        -- Profundidade da fila de reprodução, em palavras (no mínimo 2).
        tx_fifo_depth : positive := 32;
        -- Inclui o gerador de tom de teste.
        has_tone      : boolean  := true;
        -- Frequência do tom no reset, em Hz.
        tone_freq     : positive := 1000;
        -- Amplitude do tom no reset, em escala de 16 bits.
        tone_amp      : natural  := 8192;
        -- Reset com clocks, reprodução e tom ligados, para tocar o tom sem software.
        autostart     : boolean  := false
    );
    port (
        -- Clock do sistema.
        i_clk      : in    std_logic;
        -- Reset síncrono, ativo em nível alto.
        i_rst      : in    std_logic;
        -- Pulso de escrita do processador.
        i_write    : in    std_logic;
        -- Pulso de leitura do processador.
        i_read     : in    std_logic;
        -- Endereço de palavra do registrador.
        i_address  : in    std_logic_vector(3 downto 0);
        -- Dado de escrita vindo do processador.
        i_data_in  : in    word_t;
        -- Dado de leitura devolvido ao processador.
        o_data_out : out   word_t;
        -- Requisição de interrupção de nível.
        o_irq      : out   std_logic;
        -- Clock mestre do transmissor (HDMI_MCLK).
        o_mclk     : out   std_logic;
        -- Clock de bit (HDMI_SCLK).
        o_sclk     : out   std_logic;
        -- Clock de canal, '0' no canal esquerdo (HDMI_LRCLK).
        o_lrclk    : out   std_logic;
        -- Dado serial do canal 0 (HDMI_I2S0).
        o_i2s0     : out   std_logic
    );
end entity hdmi_audio;

architecture rtl of hdmi_audio is

    -- Ciclos de SCLK por canal, fixos no slot de 32 bits do I2S.
    constant SLOT_BITS : positive := 32;

    -- Frequência do clock mestre no reset, em Hz.
    constant MCLK_FREQ : positive := mclk_ratio * sample_rate;

begin

    assert sample_rate = 32_000 or sample_rate = 44_100 or sample_rate = 48_000
        report "hdmi_audio: sample_rate must be 32000, 44100 or 48000"
        severity failure;
    assert mclk_ratio = 128 or mclk_ratio = 256
        report "hdmi_audio: mclk_ratio must be 128 or 256"
        severity failure;
    assert word_bits = 16 or word_bits = 24
        report "hdmi_audio: word_bits must be 16 or 24"
        severity failure;

    u_audio : entity work.audio
        generic map (
            clk_freq      => clk_freq,
            xck_freq      => MCLK_FREQ,
            sample_rate   => sample_rate,
            slot_bits     => SLOT_BITS,
            word_bits     => word_bits,
            tx_fifo_depth => tx_fifo_depth,
            rx_fifo_depth => 2,
            master        => true,
            has_tone      => has_tone,
            tone_freq     => tone_freq,
            tone_amp      => tone_amp,
            autostart     => autostart
        )
        port map (
            i_clk        => i_clk,
            i_rst        => i_rst,
            i_write      => i_write,
            i_read       => i_read,
            i_address    => i_address,
            i_data_in    => i_data_in,
            o_data_out   => o_data_out,
            o_irq        => o_irq,
            o_xck        => o_mclk,
            i_bclk       => '0',
            o_bclk       => o_sclk,
            o_bclk_oe    => open,
            i_adclrck    => '0',
            o_adclrck    => open,
            o_adclrck_oe => open,
            i_daclrck    => '0',
            o_daclrck    => o_lrclk,
            o_daclrck_oe => open,
            i_adcdat     => '0',
            o_dacdat     => o_i2s0
        );

end architecture rtl;
