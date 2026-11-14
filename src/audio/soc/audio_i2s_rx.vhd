-- =============================================================================
-- Desserializador I2S de gravação
--
-- Amostra o dado serial na borda de subida do BCLK, em formato I2S (MSB um
-- ciclo de BCLK depois da troca do LRCK). A troca do LRCK é detectada nessa
-- mesma borda; a amostra tomada nela é o último bit do canal anterior (quando o
-- canal é justo) ou descartada (quando há preenchimento). Cada palavra completa
-- sai em o_word, com extensão de sinal para 32 bits, acompanhada do pulso
-- o_valid e do canal em o_right ('0' esquerdo, '1' direito). A largura da
-- palavra é lida no começo de cada canal; um canal mais curto que a palavra é
-- descartado.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity audio_i2s_rx is
    port (
        -- Clock do sistema.
        i_clk       : in    std_logic;
        -- Reset síncrono, ativo em nível alto.
        i_rst       : in    std_logic;
        -- Habilita a captura de canais novos.
        i_enable    : in    std_logic;
        -- Largura da palavra em bits (16, 24 ou 32).
        i_word_bits : in    unsigned(5 downto 0);
        -- Clock de bit, já no domínio de i_clk.
        i_bclk      : in    std_logic;
        -- Clock de canal, já no domínio de i_clk.
        i_lrck      : in    std_logic;
        -- Dado serial vindo do codec, já no domínio de i_clk.
        i_sdata     : in    std_logic;
        -- Pulso de uma palavra completa em o_word.
        o_valid     : out   std_logic;
        -- Canal da palavra: '0' esquerdo, '1' direito.
        o_right     : out   std_logic;
        -- Palavra recebida, com extensão de sinal.
        o_word      : out   std_logic_vector(31 downto 0)
    );
end entity audio_i2s_rx;

architecture rtl of audio_i2s_rx is

    -- Nível anterior do BCLK, para detectar a borda de subida.
    signal bclk_prev : std_logic;
    -- Nível do LRCK visto na última borda de subida do BCLK.
    signal lrck_seen : std_logic;
    -- Borda de subida do BCLK neste ciclo.
    signal rise      : std_logic;
    -- Começo de canal: o LRCK trocou desde a borda de subida anterior.
    signal new_slot  : std_logic;
    -- Uma palavra está sendo recebida.
    signal active    : std_logic;
    -- Bits da palavra já recebidos.
    signal bit_count : unsigned(5 downto 0);
    -- Largura da palavra do canal em curso.
    signal word_bits : unsigned(5 downto 0);
    -- Canal em curso.
    signal chan      : std_logic;
    -- Canal da palavra completa registrada.
    signal word_chan : std_logic;
    -- Bits recebidos, o mais recente na posição zero.
    signal shift_reg : std_logic_vector(30 downto 0);
    -- Pulso registrado de palavra completa.
    signal valid     : std_logic;
    -- Palavra completa registrada.
    signal word      : std_logic_vector(31 downto 0);

    -- Alinha os bits recebidos à esquerda e estende o sinal para 32 bits.

    function extend (
        raw  : std_logic_vector(31 downto 0);
        bits : unsigned(5 downto 0)
    ) return std_logic_vector is

        -- Quantidade de bits a descartar na parte alta.
        constant SHIFT : natural := 32 - to_integer(bits);

    begin

        return std_logic_vector(shift_right(shift_left(signed(raw), SHIFT), SHIFT));

    end function extend;

begin

    rise     <= i_bclk and not bclk_prev;
    new_slot <= rise when i_lrck /= lrck_seen else '0';

    o_valid <= valid;
    o_right <= word_chan;
    o_word  <= word;

    p_capture : process (i_clk) is

        -- Palavra formada com o bit recém-amostrado.
        variable raw : std_logic_vector(31 downto 0);

    begin

        if rising_edge(i_clk) then
            valid <= '0';

            if i_rst = '1' then
                bclk_prev <= '0';
                lrck_seen <= '0';
                active    <= '0';
                bit_count <= (others => '0');
                word_bits <= (others => '0');
                chan      <= '0';
                word_chan <= '0';
                shift_reg <= (others => '0');
                word      <= (others => '0');
            else
                bclk_prev <= i_bclk;
                raw       := shift_reg & i_sdata;

                if rise = '1' then
                    lrck_seen <= i_lrck;

                    if new_slot = '1' then
                        if active = '1' and bit_count + 1 = word_bits then
                            valid     <= '1';
                            word      <= extend(raw, word_bits);
                            word_chan <= chan;
                        end if;

                        active    <= i_enable;
                        bit_count <= (others => '0');
                        chan      <= i_lrck;
                        word_bits <= i_word_bits;
                    elsif active = '1' then
                        shift_reg <= raw(30 downto 0);
                        bit_count <= bit_count + 1;

                        if bit_count + 1 = word_bits then
                            valid     <= '1';
                            word      <= extend(raw, word_bits);
                            word_chan <= chan;
                            active    <= '0';
                        end if;
                    end if;
                end if;
            end if;
        end if;

    end process p_capture;

end architecture rtl;
