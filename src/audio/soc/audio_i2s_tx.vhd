-- =============================================================================
-- Serializador I2S de reprodução
--
-- Envia, em formato I2S (MSB um ciclo de BCLK depois da troca do LRCK, dado
-- trocando na borda de descida do BCLK), uma palavra por canal. Os níveis i_bclk
-- e i_lrck já estão no domínio de i_clk, gerados no modo mestre ou
-- sincronizados no modo escravo; o bloco só observa suas bordas. A troca do LRCK
-- é detectada na borda de subida do BCLK seguinte, quando o LRCK já está
-- estável, e então a palavra do canal é carregada; o bit seguinte fica pronto
-- e sai na próxima borda de descida.
--
-- Um quadro é composto pelo canal esquerdo (LRCK em '0') seguido do direito.
-- O quadro só é consumido se i_available estiver em '1' no início do canal
-- esquerdo; caso contrário os dois canais saem zerados e o_underflow pulsa. A
-- palavra i_data vem alinhada à esquerda em 32 bits; os bits além da largura da
-- palavra são zeros e saem como preenchimento até o fim do canal.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity audio_i2s_tx is
    port (
        -- Clock do sistema.
        i_clk         : in    std_logic;
        -- Reset síncrono, ativo em nível alto.
        i_rst         : in    std_logic;
        -- Habilita o consumo de quadros.
        i_enable      : in    std_logic;
        -- Clock de bit, já no domínio de i_clk.
        i_bclk        : in    std_logic;
        -- Clock de canal, já no domínio de i_clk.
        i_lrck        : in    std_logic;
        -- Há dados para o quadro que começa neste canal esquerdo.
        i_available   : in    std_logic;
        -- Palavra do canal que começa, alinhada à esquerda em 32 bits.
        i_data        : in    std_logic_vector(31 downto 0);
        -- Pulso: a palavra i_data foi consumida neste ciclo.
        o_load        : out   std_logic;
        -- Pulso: começa um canal direito (o quadro termina de ser carregado).
        o_right_slot  : out   std_logic;
        -- Pulso: um quadro começou sem dados disponíveis.
        o_underflow   : out   std_logic;
        -- Dado serial enviado ao codec.
        o_sdata       : out   std_logic
    );
end entity audio_i2s_tx;

architecture rtl of audio_i2s_tx is

    -- Nível anterior do BCLK, para detectar as bordas.
    signal bclk_prev  : std_logic;
    -- Nível do LRCK visto na última borda de subida do BCLK.
    signal lrck_seen  : std_logic;
    -- Borda de subida do BCLK neste ciclo.
    signal rise       : std_logic;
    -- Borda de descida do BCLK neste ciclo.
    signal fall       : std_logic;
    -- Começo de canal: o LRCK trocou desde a borda de subida anterior.
    signal new_slot   : std_logic;
    -- O quadro em curso consome dados (decidido no canal esquerdo).
    signal frame_go   : std_logic;
    -- Registrador de deslocamento, bit a enviar na posição mais alta.
    signal shift_reg  : std_logic_vector(31 downto 0);
    -- Bit preparado na borda de subida, enviado na de descida.
    signal next_bit   : std_logic;
    -- Palavra carregada neste ciclo, ou zero.
    signal load_now   : std_logic;
    -- Saída serial registrada.
    signal sdata      : std_logic;

begin

    rise     <= i_bclk and not bclk_prev;
    fall     <= bclk_prev and not i_bclk;
    new_slot <= rise when i_lrck /= lrck_seen else '0';

    load_now <= new_slot and ((not i_lrck and i_enable and i_available) or (i_lrck and frame_go));

    o_load       <= load_now;
    o_right_slot <= new_slot and i_lrck;
    o_underflow  <= new_slot and not i_lrck and i_enable and not i_available;
    o_sdata      <= sdata;

    p_serial : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            if i_rst = '1' then
                bclk_prev <= '0';
                lrck_seen <= '0';
                frame_go  <= '0';
                shift_reg <= (others => '0');
                next_bit  <= '0';
                sdata     <= '0';
            else
                bclk_prev <= i_bclk;

                if fall = '1' then
                    sdata <= next_bit;
                end if;

                if rise = '1' then
                    lrck_seen <= i_lrck;

                    if new_slot = '1' then
                        if i_lrck = '0' then
                            frame_go <= i_enable and i_available;
                        end if;

                        if load_now = '1' then
                            next_bit  <= i_data(31);
                            shift_reg <= i_data(30 downto 0) & '0';
                        else
                            next_bit  <= '0';
                            shift_reg <= (others => '0');
                        end if;
                    else
                        next_bit  <= shift_reg(31);
                        shift_reg <= shift_reg(30 downto 0) & '0';
                    end if;
                end if;
            end if;
        end if;

    end process p_serial;

end architecture rtl;
