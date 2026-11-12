-- =============================================================================
-- Gerador de temporização VGA 640x480 a 60 Hz e de coordenadas do framebuffer
--
-- Domínio do clock de pixel. Dois contadores, de coluna (0 a H_TOTAL - 1) e de
-- linha (0 a V_TOTAL - 1), geram os sincronismos horizontal e vertical em nível
-- baixo (o_hs e o_vs) e as marcas de apagamento. O framebuffer de fb_width por
-- fb_height pixels é ampliado scale vezes em x e em y e centrado na área
-- visível; fora desse retângulo a imagem é preta (o_image = '0').
--
-- Dentro do retângulo, o_fb_x e o_fb_y valem as coordenadas do pixel do
-- framebuffer que cobre o pixel atual da tela. Os contadores de repetição
-- avançam as coordenadas a cada scale pixels (em x) e a cada scale linhas (em
-- y), e as coordenadas ficam retidas no último valor fora do retângulo, o que
-- mantém o endereço de leitura da memória sempre dentro da faixa.
--
-- Prioridade: i_rst = '1' (síncrono) leva os contadores ao canto superior
-- esquerdo do quadro. As saídas de estado o_vsync e o_vblank são registradas
-- para atravessarem o cruzamento de clock sem glitches de decodificação.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.utils_pkg.all;
use work.video_consts.all;

entity video_timing is
    generic (
        -- Largura do framebuffer em pixels.
        fb_width  : positive := 320;
        -- Altura do framebuffer em pixels.
        fb_height : positive := 200;
        -- Fator de ampliação do pixel do framebuffer em x e em y.
        scale     : positive := 2
    );
    port (
        -- Clock de pixel (25 MHz para 60 Hz).
        i_clk : in    std_logic;
        -- Reset síncrono em i_clk, ativo em '1'.
        i_rst : in    std_logic;

        -- Sincronismo horizontal, ativo em nível baixo.
        o_hs     : out   std_logic;
        -- Sincronismo vertical, ativo em nível baixo.
        o_vs     : out   std_logic;
        -- Pulso de sincronismo vertical em nível alto, registrado.
        o_vsync  : out   std_logic;
        -- Apagamento vertical em nível alto (linhas depois da última visível), registrado.
        o_vblank : out   std_logic;
        -- O pixel atual está dentro do retângulo do framebuffer ampliado ('1').
        o_image  : out   std_logic;
        -- Coluna do framebuffer que cobre o pixel atual.
        o_fb_x   : out   std_logic_vector(log2_ceil(fb_width + 1) - 1 downto 0);
        -- Linha do framebuffer que cobre o pixel atual.
        o_fb_y   : out   std_logic_vector(log2_ceil(fb_height + 1) - 1 downto 0)
    );
end entity video_timing;

architecture rtl of video_timing is

    -- Largura em pixels da imagem ampliada.
    constant IMAGE_W : natural := fb_width * scale;
    -- Altura em linhas da imagem ampliada.
    constant IMAGE_H : natural := fb_height * scale;
    -- Primeira coluna da imagem, que a centra na área visível.
    constant X_OFF   : natural := (H_VISIBLE - IMAGE_W) / 2;
    -- Primeira linha da imagem, que a centra na área visível.
    constant Y_OFF   : natural := (V_VISIBLE - IMAGE_H) / 2;
    -- Coluna em que o pulso de sincronismo horizontal começa.
    constant HS_BEGIN : natural := H_VISIBLE + H_FRONT;
    -- Linha em que o pulso de sincronismo vertical começa.
    constant VS_BEGIN : natural := V_VISIBLE + V_FRONT;

    -- Coluna atual, de 0 a H_TOTAL - 1.
    signal h_cnt  : natural range 0 to H_TOTAL - 1 := 0;
    -- Linha atual, de 0 a V_TOTAL - 1.
    signal v_cnt  : natural range 0 to V_TOTAL - 1 := 0;
    -- Coluna do framebuffer que cobre a coluna atual.
    signal fb_x   : natural range 0 to fb_width - 1 := 0;
    -- Pixels já emitidos da coluna atual do framebuffer (0 a scale - 1).
    signal x_sub  : natural range 0 to scale - 1 := 0;
    -- Linha do framebuffer que cobre a linha atual.
    signal fb_y   : natural range 0 to fb_height - 1 := 0;
    -- Linhas já emitidas da linha atual do framebuffer (0 a scale - 1).
    signal y_sub  : natural range 0 to scale - 1 := 0;
    -- A coluna atual está dentro do retângulo da imagem.
    signal in_x   : std_logic;
    -- A linha atual está dentro do retângulo da imagem.
    signal in_y   : std_logic;
    -- Pulso de sincronismo vertical registrado, em nível alto.
    signal vsync_q  : std_logic := '0';
    -- Apagamento vertical registrado, em nível alto.
    signal vblank_q : std_logic := '0';

begin

    assert IMAGE_W <= H_VISIBLE and IMAGE_H <= V_VISIBLE
        report "video_timing: a imagem ampliada deve caber em 640x480"
        severity failure;

    in_x <= '1' when h_cnt >= X_OFF and h_cnt < X_OFF + IMAGE_W else '0';
    in_y <= '1' when v_cnt >= Y_OFF and v_cnt < Y_OFF + IMAGE_H else '0';

    o_hs     <= '0' when h_cnt >= HS_BEGIN and h_cnt < HS_BEGIN + H_SYNC else '1';
    o_vs     <= '0' when v_cnt >= VS_BEGIN and v_cnt < VS_BEGIN + V_SYNC else '1';
    o_image  <= in_x and in_y;
    o_fb_x   <= std_logic_vector(to_unsigned(fb_x, o_fb_x'length));
    o_fb_y   <= std_logic_vector(to_unsigned(fb_y, o_fb_y'length));
    o_vsync  <= vsync_q;
    o_vblank <= vblank_q;

    -- Os contadores de coluna e de linha avançam a cada pixel; as coordenadas do framebuffer reiniciam na
    -- coluna (ou linha) anterior ao início da imagem e avançam uma unidade a cada scale pixels (ou linhas).
    p_count : process (i_clk) is

        -- Coluna que o contador assume na próxima borda.
        variable next_h : natural range 0 to H_TOTAL - 1;
        -- Linha que o contador assume na próxima borda.
        variable next_v : natural range 0 to V_TOTAL - 1;

    begin

        if rising_edge(i_clk) then
            if i_rst = '1' then
                h_cnt    <= 0;
                v_cnt    <= 0;
                fb_x     <= 0;
                x_sub    <= 0;
                fb_y     <= 0;
                y_sub    <= 0;
                vsync_q  <= '0';
                vblank_q <= '0';
            else
                next_h := pick(h_cnt = H_TOTAL - 1, 0, h_cnt + 1);
                next_v := v_cnt;
                if h_cnt = H_TOTAL - 1 then
                    next_v := pick(v_cnt = V_TOTAL - 1, 0, v_cnt + 1);
                end if;

                h_cnt    <= next_h;
                v_cnt    <= next_v;
                vsync_q  <= to_sl(v_cnt >= VS_BEGIN and v_cnt < VS_BEGIN + V_SYNC);
                vblank_q <= to_sl(v_cnt >= V_VISIBLE);

                -- Coordenada horizontal: reinicia antes da primeira coluna da imagem e avança dentro dela.
                if next_h = X_OFF then
                    fb_x  <= 0;
                    x_sub <= 0;
                elsif in_x = '1' then
                    if x_sub = scale - 1 then
                        x_sub <= 0;
                        if fb_x < fb_width - 1 then
                            fb_x <= fb_x + 1;
                        end if;
                    else
                        x_sub <= x_sub + 1;
                    end if;
                end if;

                -- Coordenada vertical: muda só no fim da linha, reiniciando antes da primeira linha da imagem.
                if h_cnt = H_TOTAL - 1 then
                    if next_v = Y_OFF then
                        fb_y  <= 0;
                        y_sub <= 0;
                    elsif in_y = '1' then
                        if y_sub = scale - 1 then
                            y_sub <= 0;
                            if fb_y < fb_height - 1 then
                                fb_y <= fb_y + 1;
                            end if;
                        else
                            y_sub <= y_sub + 1;
                        end if;
                    end if;
                end if;
            end if;
        end if;

    end process p_count;

end architecture rtl;
