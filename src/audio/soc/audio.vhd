-- =============================================================================
-- Interface de áudio digital I2S para o codec WM8731, mapeada em memória
--
-- Liga o barramento do núcleo a um codec de áudio por I2S (AUD_XCK, AUD_BCLK,
-- AUD_ADCLRCK, AUD_ADCDAT, AUD_DACLRCK e AUD_DACDAT na DE2-115). A configuração
-- do codec é feita por I2C, fora deste periférico. Estrutura:
--   - clock mestre do codec por acumulador fracionário e, no modo mestre
--     (generic master), clocks de bit e de canal derivados dele; no modo escravo
--     BCLK e LRCK são entradas e passam por sincronizadores de dois estágios;
--   - serializador de reprodução e desserializador de gravação, ambos com
--     palavra de 16, 24 ou 32 bits por canal, cada um com uma fila de palavras
--     (amostras esquerda e direita intercaladas);
--   - tom de teste opcional, uma onda quadrada em hardware que substitui a fila
--     de reprodução;
--   - interrupção de nível por limiares das filas e por erro.
--
-- Os pinos bidirecionais saem como entrada, saída e habilitação de saída, para
-- a camada de tristate do topo. Mapa de registradores em endereços de palavra:
--
--   0 CONTROL    R/W  bits 0 TX_EN, 1 RX_EN, 2 TX_IRQ_EN, 3 RX_IRQ_EN, 4 ERR_IRQ_EN,
--                     5 CLK_EN, 6 TONE_EN e 9:8 WORD (0 = 16, 1 = 24, 2 ou 3 = 32 bits)
--   1 STATUS     R/W1C bits 0 TX_NOT_FULL, 1 RX_NOT_EMPTY, 2 TX_EMPTY, 3 RX_FULL,
--                     4 TX_UNDERFLOW, 5 RX_OVERFLOW e 6 TX_DROPPED (4 a 6 limpam com 1)
--   2 LEVELS     R    bits 15:0 nível da fila de reprodução e 31:16 da de gravação
--   3 TX_DATA    W    empilha uma amostra na fila de reprodução
--   4 RX_DATA    R    amostra mais antiga da fila de gravação, removida pela leitura
--   5 IRQ_LEVEL  R/W  bits 15:0 limiar da reprodução (interrompe com nível <= limiar)
--                     e 31:16 da gravação (interrompe com nível >= limiar)
--   6 XCK_STEP   R/W  passo do acumulador do clock mestre (2 * f_mestre em Hz)
--   7 XCK_MOD    R/W  módulo do acumulador (frequência do clock do sistema em Hz)
--   8 BCLK_DIV   R/W  bits 15:0, f_mestre / f_bclk
--   9 SLOT_BITS  R/W  bits 15:0, ciclos de BCLK por canal
--  10 TONE_HALF  R/W  bits 15:0, quadros por semiciclo do tom
--  11 TONE_AMP   R/W  bits 15:0, amplitude do tom em escala de 16 bits
--  12 CONFIG     R    bits 15:0 profundidade da reprodução e 31:16 da gravação
--  13 CAPS       R    bits 0 MASTER e 1 HAS_TONE
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.config_pkg.all;
use work.audio_consts.all;

entity audio is
    generic (
        -- Frequência do clock do sistema em Hz (módulo do gerador do clock mestre).
        clk_freq      : positive := 50_000_000;
        -- Frequência do clock mestre AUD_XCK em Hz (no máximo a metade de clk_freq).
        xck_freq      : positive := 12_288_000;
        -- Taxa de amostragem em Hz que define o divisor inicial do clock de bit.
        sample_rate   : positive := 48_000;
        -- Ciclos de BCLK por canal no reset (no mínimo a largura da palavra).
        slot_bits     : positive := 32;
        -- Largura da palavra no reset: 16, 24 ou 32 bits.
        word_bits     : positive := 24;
        -- Profundidade da fila de reprodução, em palavras (no mínimo 2).
        tx_fifo_depth : positive := 32;
        -- Profundidade da fila de gravação, em palavras (no mínimo 2).
        rx_fifo_depth : positive := 32;
        -- Modo mestre (verdadeiro) ou escravo (falso) para BCLK e LRCK.
        master        : boolean  := true;
        -- Inclui o gerador de tom de teste.
        has_tone      : boolean  := true;
        -- Frequência do tom no reset, em Hz.
        tone_freq     : positive := 1000;
        -- Amplitude do tom no reset, em escala de 16 bits.
        tone_amp      : natural  := 8192;
        -- Reset com clocks, reprodução e tom ligados, para provar o caminho sem software.
        autostart     : boolean  := false
    );
    port (
        -- Clock do sistema.
        i_clk         : in    std_logic;
        -- Reset síncrono, ativo em nível alto.
        i_rst         : in    std_logic;
        -- Pulso de escrita do processador.
        i_write       : in    std_logic;
        -- Pulso de leitura do processador.
        i_read        : in    std_logic;
        -- Endereço de palavra do registrador.
        i_address     : in    std_logic_vector(3 downto 0);
        -- Dado de escrita vindo do processador.
        i_data_in     : in    word_t;
        -- Dado de leitura devolvido ao processador.
        o_data_out    : out   word_t;
        -- Requisição de interrupção de nível.
        o_irq         : out   std_logic;
        -- Clock mestre do codec (AUD_XCK).
        o_xck         : out   std_logic;
        -- Entrada do clock de bit (AUD_BCLK), usada no modo escravo.
        i_bclk        : in    std_logic;
        -- Saída do clock de bit (AUD_BCLK), usada no modo mestre.
        o_bclk        : out   std_logic;
        -- Habilitação da saída do clock de bit.
        o_bclk_oe     : out   std_logic;
        -- Entrada do clock de canal do ADC (AUD_ADCLRCK), usada no modo escravo.
        i_adclrck     : in    std_logic;
        -- Saída do clock de canal do ADC (AUD_ADCLRCK), usada no modo mestre.
        o_adclrck     : out   std_logic;
        -- Habilitação da saída do clock de canal do ADC.
        o_adclrck_oe  : out   std_logic;
        -- Entrada do clock de canal do DAC (AUD_DACLRCK), usada no modo escravo.
        i_daclrck     : in    std_logic;
        -- Saída do clock de canal do DAC (AUD_DACLRCK), usada no modo mestre.
        o_daclrck     : out   std_logic;
        -- Habilitação da saída do clock de canal do DAC.
        o_daclrck_oe  : out   std_logic;
        -- Dado serial do ADC (AUD_ADCDAT).
        i_adcdat      : in    std_logic;
        -- Dado serial do DAC (AUD_DACDAT).
        o_dacdat      : out   std_logic
    );
end entity audio;

architecture rtl of audio is

    -- Converte a largura da palavra em bits no código do campo WORD.

    function word_code (
        bits : positive
    ) return natural is
    begin

        if bits = 16 then
            return WORD_16;
        elsif bits = 24 then
            return WORD_24;
        end if;

        return WORD_32;

    end function word_code;

    -- Converte um booleano em std_logic.

    function to_sl (
        value : boolean
    ) return std_logic is
    begin

        if value then
            return '1';
        end if;

        return '0';

    end function to_sl;

    -- Divisor do clock de bit no reset, em inversões do clock mestre.
    constant RESET_BCLK_DIV : natural := xck_freq / (sample_rate * 2 * slot_bits);
    -- Quadros por semiciclo do tom no reset.
    constant RESET_TONE_HALF : natural := sample_rate / (2 * tone_freq);
    -- Código do campo WORD no reset.
    constant RESET_WORD : natural := word_code(word_bits);

    -- Habilita a geração dos clocks.
    signal clk_en      : std_logic;
    -- Habilita o serializador.
    signal tx_en       : std_logic;
    -- Habilita o desserializador.
    signal rx_en       : std_logic;
    -- Habilita a interrupção da fila de reprodução.
    signal tx_irq_en   : std_logic;
    -- Habilita a interrupção da fila de gravação.
    signal rx_irq_en   : std_logic;
    -- Habilita a interrupção de erro.
    signal err_irq_en  : std_logic;
    -- Habilita o tom de teste.
    signal tone_en     : std_logic;
    -- Código da largura da palavra.
    signal word_sel    : std_logic_vector(1 downto 0);
    -- Largura da palavra em bits.
    signal word_len    : unsigned(5 downto 0);
    -- Subfluxo pendente.
    signal tx_underflow_flag : std_logic;
    -- Sobrefluxo pendente.
    signal rx_overflow_flag  : std_logic;
    -- Escrita descartada pendente.
    signal tx_dropped_flag   : std_logic;
    -- Limiar da fila de reprodução.
    signal tx_thr      : std_logic_vector(15 downto 0);
    -- Limiar da fila de gravação.
    signal rx_thr      : std_logic_vector(15 downto 0);
    -- Passo do gerador do clock mestre.
    signal xck_step    : std_logic_vector(31 downto 0);
    -- Módulo do gerador do clock mestre.
    signal xck_mod     : std_logic_vector(31 downto 0);
    -- Divisor do clock de bit.
    signal bclk_div    : std_logic_vector(15 downto 0);
    -- Ciclos de BCLK por canal.
    signal slot_len    : std_logic_vector(15 downto 0);
    -- Quadros por semiciclo do tom.
    signal tone_half   : std_logic_vector(15 downto 0);
    -- Amplitude do tom.
    signal tone_amp_r  : std_logic_vector(15 downto 0);

    -- Inversão do clock mestre.
    signal xck_edge    : std_logic;
    -- Clock mestre gerado.
    signal xck         : std_logic;
    -- BCLK gerado no modo mestre.
    signal gen_bclk    : std_logic;
    -- LRCK gerado no modo mestre.
    signal gen_lrck    : std_logic;
    -- Entradas do codec sincronizadas, na ordem BCLK, DACLRCK, ADCLRCK e ADCDAT.
    signal sync_in     : std_logic_vector(3 downto 0);
    -- BCLK efetivo.
    signal bclk        : std_logic;
    -- LRCK efetivo da reprodução.
    signal tx_lrck     : std_logic;
    -- LRCK efetivo da gravação.
    signal rx_lrck     : std_logic;

    -- Tom de teste selecionado nesta instância.
    signal tone_sel    : std_logic;
    -- Nível do tom.
    signal tone_level  : std_logic;
    -- Palavra do tom alinhada à esquerda.
    signal tone_word   : std_logic_vector(31 downto 0);
    -- Pulso de fim de quadro do serializador.
    signal tx_right    : std_logic;
    -- Pulso de consumo de palavra do serializador.
    signal tx_load     : std_logic;
    -- Pulso de subfluxo do serializador.
    signal tx_underflow : std_logic;
    -- Palavra entregue ao serializador.
    signal tx_word     : std_logic_vector(31 downto 0);
    -- Palavra mais antiga da fila de reprodução.
    signal tx_head     : std_logic_vector(31 downto 0);
    -- Escrita na fila de reprodução aceita.
    signal tx_push_ok  : std_logic;
    -- Escrita na fila de reprodução pedida.
    signal tx_push     : std_logic;
    -- Remoção da fila de reprodução.
    signal tx_pop      : std_logic;
    -- A fila de reprodução está cheia.
    signal tx_full     : std_logic;
    -- A fila de reprodução está vazia.
    signal tx_empty    : std_logic;
    -- Nível da fila de reprodução.
    signal tx_level    : natural range 0 to tx_fifo_depth;
    -- Há um quadro para consumir.
    signal tx_available : std_logic;

    -- Pulso de palavra do desserializador.
    signal rx_valid    : std_logic;
    -- Canal da palavra do desserializador.
    signal rx_right    : std_logic;
    -- Palavra do desserializador.
    signal rx_word     : std_logic_vector(31 downto 0);
    -- Há espaço para um quadro inteiro na fila de gravação.
    signal rx_space    : std_logic;
    -- O quadro em curso foi aceito pela fila de gravação.
    signal rx_frame_ok : std_logic;
    -- Inserção na fila de gravação.
    signal rx_push     : std_logic;
    -- Remoção da fila de gravação.
    signal rx_pop      : std_logic;
    -- Palavra mais antiga da fila de gravação.
    signal rx_head     : std_logic_vector(31 downto 0);
    -- A fila de gravação está cheia.
    signal rx_full     : std_logic;
    -- A fila de gravação está vazia.
    signal rx_empty    : std_logic;
    -- Nível da fila de gravação.
    signal rx_level    : natural range 0 to rx_fifo_depth;

    -- Escrita em registrador deste ciclo.
    signal write_reg   : std_logic;

begin

    assert tx_fifo_depth >= 2 and tx_fifo_depth <= 65535
        report "audio: tx_fifo_depth must be between 2 and 65535"
        severity failure;
    assert rx_fifo_depth >= 2 and rx_fifo_depth <= 65535
        report "audio: rx_fifo_depth must be between 2 and 65535"
        severity failure;
    assert word_bits = 16 or word_bits = 24 or word_bits = 32
        report "audio: word_bits must be 16, 24 or 32"
        severity failure;
    assert slot_bits >= word_bits
        report "audio: slot_bits must be at least word_bits"
        severity failure;
    assert RESET_BCLK_DIV >= 1
        report "audio: xck_freq is too low for sample_rate and slot_bits"
        severity failure;
    assert xck_freq * 2 <= clk_freq
        report "audio: xck_freq must be at most clk_freq / 2"
        severity failure;

    -- -------------------------------------------------------------------------
    -- Clocks
    -- -------------------------------------------------------------------------

    u_xck : entity work.audio_xck_gen
        port map (
            i_clk    => i_clk,
            i_rst    => i_rst,
            i_enable => clk_en,
            i_step   => xck_step,
            i_mod    => xck_mod,
            o_xck    => xck,
            o_edge   => xck_edge
        );

    o_xck <= xck;

    g_master : if master generate

        u_frame_clocks : entity work.audio_frame_clocks
            port map (
                i_clk       => i_clk,
                i_rst       => i_rst,
                i_enable    => clk_en,
                i_xck_edge  => xck_edge,
                i_bclk_div  => bclk_div,
                i_slot_bits => slot_len,
                o_bclk      => gen_bclk,
                o_lrck      => gen_lrck
            );

        bclk         <= gen_bclk;
        tx_lrck      <= gen_lrck;
        rx_lrck      <= gen_lrck;
        o_bclk       <= gen_bclk;
        o_bclk_oe    <= '1';
        o_adclrck    <= gen_lrck;
        o_adclrck_oe <= '1';
        o_daclrck    <= gen_lrck;
        o_daclrck_oe <= '1';

    end generate g_master;

    g_slave : if not master generate

        bclk         <= sync_in(0);
        tx_lrck      <= sync_in(1);
        rx_lrck      <= sync_in(2);
        o_bclk       <= '0';
        o_bclk_oe    <= '0';
        o_adclrck    <= '0';
        o_adclrck_oe <= '0';
        o_daclrck    <= '0';
        o_daclrck_oe <= '0';

    end generate g_slave;

    u_input_sync : entity work.synchronizer
        generic map (
            stages     => 2,
            data_width => 4
        )
        port map (
            i_clk => i_clk,
            i_rst => i_rst,
            i_d   => i_adcdat & i_adclrck & i_daclrck & i_bclk,
            o_d   => sync_in
        );

    -- -------------------------------------------------------------------------
    -- Reprodução
    -- -------------------------------------------------------------------------

    word_len <= to_unsigned(16, 6) when word_sel = "00" else
                to_unsigned(24, 6) when word_sel = "01" else
                to_unsigned(32, 6);

    tone_sel <= tone_en;

    g_tone : if has_tone generate

        u_tone : entity work.audio_tone
            port map (
                i_clk     => i_clk,
                i_rst     => i_rst,
                i_enable  => tone_en,
                i_half    => tone_half,
                i_advance => tx_right,
                o_level   => tone_level
            );

    end generate g_tone;

    g_no_tone : if not has_tone generate

        tone_level <= '0';

    end generate g_no_tone;

    tone_word <= tone_amp_r & x"0000" when tone_level = '0' else
                 std_logic_vector(unsigned(not tone_amp_r) + 1) & x"0000";

    tx_available <= '1' when tone_sel = '1' or tx_level >= 2 else '0';
    tx_word      <= tone_word when tone_sel = '1' else
                    std_logic_vector(shift_left(unsigned(tx_head), 32 - to_integer(word_len)));
    tx_pop       <= tx_load and not tone_sel;
    tx_push      <= '1' when i_write = '1' and i_address = ADDR_TX_DATA else '0';

    u_tx_fifo : entity work.uart_fifo
        generic map (
            data_width => 32,
            depth      => tx_fifo_depth
        )
        port map (
            i_clk           => i_clk,
            i_rst           => i_rst,
            i_push          => tx_push,
            i_push_data     => i_data_in(31 downto 0),
            i_pop           => tx_pop,
            o_pop_data      => tx_head,
            o_push_accepted => tx_push_ok,
            o_pop_accepted  => open,
            o_full          => tx_full,
            o_empty         => tx_empty,
            o_level         => tx_level
        );

    u_tx : entity work.audio_i2s_tx
        port map (
            i_clk        => i_clk,
            i_rst        => i_rst,
            i_enable     => tx_en,
            i_bclk       => bclk,
            i_lrck       => tx_lrck,
            i_available  => tx_available,
            i_data       => tx_word,
            o_load       => tx_load,
            o_right_slot => tx_right,
            o_underflow  => tx_underflow,
            o_sdata      => o_dacdat
        );

    -- -------------------------------------------------------------------------
    -- Gravação
    -- -------------------------------------------------------------------------

    rx_space <= '1' when rx_level <= rx_fifo_depth - 2 else '0';
    rx_push  <= rx_valid and ((not rx_right and rx_space) or (rx_right and rx_frame_ok));
    rx_pop   <= '1' when i_read = '1' and i_address = ADDR_RX_DATA else '0';

    u_rx : entity work.audio_i2s_rx
        port map (
            i_clk       => i_clk,
            i_rst       => i_rst,
            i_enable    => rx_en,
            i_word_bits => word_len,
            i_bclk      => bclk,
            i_lrck      => rx_lrck,
            i_sdata     => sync_in(3),
            o_valid     => rx_valid,
            o_right     => rx_right,
            o_word      => rx_word
        );

    u_rx_fifo : entity work.uart_fifo
        generic map (
            data_width => 32,
            depth      => rx_fifo_depth
        )
        port map (
            i_clk           => i_clk,
            i_rst           => i_rst,
            i_push          => rx_push,
            i_push_data     => rx_word,
            i_pop           => rx_pop,
            o_pop_data      => rx_head,
            o_push_accepted => open,
            o_pop_accepted  => open,
            o_full          => rx_full,
            o_empty         => rx_empty,
            o_level         => rx_level
        );

    -- -------------------------------------------------------------------------
    -- Registradores e interrupção
    -- -------------------------------------------------------------------------

    write_reg <= i_write;

    o_irq <= (tx_irq_en and to_sl(tx_level <= to_integer(unsigned(tx_thr)))) or
             (rx_irq_en and to_sl(rx_level >= to_integer(unsigned(rx_thr)))) or
             (err_irq_en and (tx_underflow_flag or rx_overflow_flag or tx_dropped_flag));

    p_registers : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            if i_rst = '1' then
                clk_en            <= to_sl(autostart);
                tx_en             <= to_sl(autostart);
                rx_en             <= '0';
                tx_irq_en         <= '0';
                rx_irq_en         <= '0';
                err_irq_en        <= '0';
                tone_en           <= to_sl(autostart and has_tone);
                word_sel          <= std_logic_vector(to_unsigned(RESET_WORD, 2));
                tx_underflow_flag <= '0';
                rx_overflow_flag  <= '0';
                tx_dropped_flag   <= '0';
                rx_frame_ok       <= '0';
                tx_thr            <= (others => '0');
                rx_thr            <= x"0001";
                xck_step          <= std_logic_vector(to_unsigned(2 * xck_freq, 32));
                xck_mod           <= std_logic_vector(to_unsigned(clk_freq, 32));
                bclk_div          <= std_logic_vector(to_unsigned(RESET_BCLK_DIV, 16));
                slot_len          <= std_logic_vector(to_unsigned(slot_bits, 16));
                tone_half         <= std_logic_vector(to_unsigned(RESET_TONE_HALF, 16));
                tone_amp_r        <= std_logic_vector(to_unsigned(tone_amp, 16));
            else
                if write_reg = '1' then
                    case i_address is

                        when ADDR_CONTROL =>

                            tx_en      <= i_data_in(CTRL_TX_EN);
                            rx_en      <= i_data_in(CTRL_RX_EN);
                            tx_irq_en  <= i_data_in(CTRL_TX_IRQ_EN);
                            rx_irq_en  <= i_data_in(CTRL_RX_IRQ_EN);
                            err_irq_en <= i_data_in(CTRL_ERR_IRQ_EN);
                            clk_en     <= i_data_in(CTRL_CLK_EN);
                            tone_en    <= i_data_in(CTRL_TONE_EN) and to_sl(has_tone);
                            word_sel   <= i_data_in(9 downto 8);

                        when ADDR_IRQ_LEVEL =>

                            tx_thr <= i_data_in(15 downto 0);
                            rx_thr <= i_data_in(31 downto 16);

                        when ADDR_XCK_STEP =>

                            xck_step <= i_data_in(31 downto 0);

                        when ADDR_XCK_MOD =>

                            xck_mod <= i_data_in(31 downto 0);

                        when ADDR_BCLK_DIV =>

                            bclk_div <= i_data_in(15 downto 0);

                        when ADDR_SLOT_BITS =>

                            slot_len <= i_data_in(15 downto 0);

                        when ADDR_TONE_HALF =>

                            tone_half <= i_data_in(15 downto 0);

                        when ADDR_TONE_AMP =>

                            tone_amp_r <= i_data_in(15 downto 0);

                        when ADDR_STATUS =>

                            if i_data_in(STAT_TX_UNDERFLOW) = '1' then
                                tx_underflow_flag <= '0';
                            end if;
                            if i_data_in(STAT_RX_OVERFLOW) = '1' then
                                rx_overflow_flag <= '0';
                            end if;
                            if i_data_in(STAT_TX_DROPPED) = '1' then
                                tx_dropped_flag <= '0';
                            end if;

                        when others =>

                            null;

                    end case;
                end if;

                -- Os eventos novos têm prioridade sobre uma limpeza simultânea.
                if tx_underflow = '1' then
                    tx_underflow_flag <= '1';
                end if;
                if rx_valid = '1' and rx_right = '0' and rx_space = '0' then
                    rx_overflow_flag <= '1';
                end if;
                if tx_push = '1' and tx_push_ok = '0' then
                    tx_dropped_flag <= '1';
                end if;

                if rx_en = '0' then
                    rx_frame_ok <= '0';
                elsif rx_valid = '1' and rx_right = '0' then
                    rx_frame_ok <= rx_space;
                end if;
            end if;
        end if;

    end process p_registers;

    p_readback : process (
                          i_address, tx_en, rx_en, tx_irq_en, rx_irq_en, err_irq_en, clk_en, tone_en, word_sel,
                          tx_full, rx_empty, tx_empty, rx_full, tx_underflow_flag, rx_overflow_flag,
                          tx_dropped_flag, tx_level, rx_level, rx_head, tx_thr, rx_thr, xck_step, xck_mod,
                          bclk_div, slot_len, tone_half, tone_amp_r
                         ) is

        -- Valor montado para o registrador selecionado.
        variable value : word_t;

    begin

        value := (others => '0');

        case i_address is

            when ADDR_CONTROL =>

                value(CTRL_TX_EN)      := tx_en;
                value(CTRL_RX_EN)      := rx_en;
                value(CTRL_TX_IRQ_EN)  := tx_irq_en;
                value(CTRL_RX_IRQ_EN)  := rx_irq_en;
                value(CTRL_ERR_IRQ_EN) := err_irq_en;
                value(CTRL_CLK_EN)     := clk_en;
                value(CTRL_TONE_EN)    := tone_en;
                value(9 downto 8)      := word_sel;

            when ADDR_STATUS =>

                value(STAT_TX_NOT_FULL)  := not tx_full;
                value(STAT_RX_NOT_EMPTY) := not rx_empty;
                value(STAT_TX_EMPTY)     := tx_empty;
                value(STAT_RX_FULL)      := rx_full;
                value(STAT_TX_UNDERFLOW) := tx_underflow_flag;
                value(STAT_RX_OVERFLOW)  := rx_overflow_flag;
                value(STAT_TX_DROPPED)   := tx_dropped_flag;

            when ADDR_LEVELS =>

                value(15 downto 0)  := std_logic_vector(to_unsigned(tx_level, 16));
                value(31 downto 16) := std_logic_vector(to_unsigned(rx_level, 16));

            when ADDR_RX_DATA =>

                value(31 downto 0) := rx_head;

            when ADDR_IRQ_LEVEL =>

                value(15 downto 0)  := tx_thr;
                value(31 downto 16) := rx_thr;

            when ADDR_XCK_STEP =>

                value(31 downto 0) := xck_step;

            when ADDR_XCK_MOD =>

                value(31 downto 0) := xck_mod;

            when ADDR_BCLK_DIV =>

                value(15 downto 0) := bclk_div;

            when ADDR_SLOT_BITS =>

                value(15 downto 0) := slot_len;

            when ADDR_TONE_HALF =>

                value(15 downto 0) := tone_half;

            when ADDR_TONE_AMP =>

                value(15 downto 0) := tone_amp_r;

            when ADDR_CONFIG =>

                value(15 downto 0)  := std_logic_vector(to_unsigned(tx_fifo_depth, 16));
                value(31 downto 16) := std_logic_vector(to_unsigned(rx_fifo_depth, 16));

            when ADDR_CAPS =>

                value(0) := to_sl(master);
                value(1) := to_sl(has_tone);

            when others =>

                null;

        end case;

        o_data_out <= value;

    end process p_readback;

end architecture rtl;
