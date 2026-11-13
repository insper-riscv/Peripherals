-- =============================================================================
-- Gerador de temporização de vídeo e de coordenadas do framebuffer
--
-- Domínio do clock de pixel. A temporização do modo (área visível, pórticos e
-- sincronismo de cada direção, mais a polaridade) vem dos generics, de modo que
-- o mesmo bloco gera 640x480 a 60 Hz ou qualquer outro modo do catálogo da
-- placa. Dois contadores, de coluna (0 a H_TOTAL - 1) e de linha (0 a
-- V_TOTAL - 1), geram os sincronismos horizontal e vertical (o_hs e o_vs, em
-- nível alto durante o pulso se a polaridade é positiva e em nível baixo se é
-- negativa) e as marcas de apagamento. O framebuffer de fb_width por
-- fb_height pixels é ampliado scale vezes em x e em y e centrado na área
-- visível; fora desse retângulo a imagem é preta (o_image = '0'), e o_visible
-- marca a área visível inteira, com a imagem e as faixas pretas.
--
-- Dentro do retângulo, o_fb_x e o_fb_y valem as coordenadas do pixel do
-- framebuffer que cobre o pixel atual da tela. Os contadores de repetição
-- avançam as coordenadas a cada scale pixels (em x) e a cada scale linhas (em
-- y), e as coordenadas ficam retidas no último valor fora do retângulo, o que
-- mantém o endereço de leitura da memória sempre dentro da faixa.
--
-- Prioridade: i_rst = '1' (síncrono) leva os contadores ao canto superior
-- esquerdo do quadro. As saídas de estado o_vsync e o_vblank são registradas
-- para atravessarem o cruzamento de clock sem glitches de decodificação, e
-- valem '1' durante o pulso de sincronismo vertical e depois da última linha
-- visível, qualquer que seja a polaridade.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.utils_pkg.all;

entity video_timing is
    generic (
        -- Largura do framebuffer em pixels.
        fb_width        : positive := 320;
        -- Altura do framebuffer em pixels.
        fb_height       : positive := 200;
        -- Fator de ampliação do pixel do framebuffer em x e em y.
        scale           : positive := 2;
        -- Pixels visíveis por linha.
        h_visible       : positive := 640;
        -- Pixels do pórtico frontal horizontal, entre o fim da área visível e o pulso de sincronismo.
        h_front_porch   : natural  := 16;
        -- Pixels do pulso de sincronismo horizontal.
        h_sync          : positive := 96;
        -- Pixels do pórtico traseiro horizontal, entre o pulso de sincronismo e a área visível.
        h_back_porch    : natural  := 48;
        -- Polaridade do sincronismo horizontal: verdadeiro = nível alto durante o pulso.
        h_sync_positive : boolean  := false;
        -- Linhas visíveis por quadro.
        v_visible       : positive := 480;
        -- Linhas do pórtico frontal vertical, entre o fim da área visível e o pulso de sincronismo.
        v_front_porch   : natural  := 10;
        -- Linhas do pulso de sincronismo vertical.
        v_sync          : positive := 2;
        -- Linhas do pórtico traseiro vertical, entre o pulso de sincronismo e a área visível.
        v_back_porch    : natural  := 33;
        -- Polaridade do sincronismo vertical: verdadeiro = nível alto durante o pulso.
        v_sync_positive : boolean  := false
    );
    port (
        -- Clock de pixel.
        i_clk : in    std_logic;
        -- Reset síncrono em i_clk, ativo em '1'.
        i_rst : in    std_logic;

        -- Sincronismo horizontal, com a polaridade do generic h_sync_positive.
        o_hs      : out   std_logic;
        -- Sincronismo vertical, com a polaridade do generic v_sync_positive.
        o_vs      : out   std_logic;
        -- Pulso de sincronismo vertical em nível alto, registrado.
        o_vsync   : out   std_logic;
        -- Apagamento vertical em nível alto (linhas depois da última visível), registrado.
        o_vblank  : out   std_logic;
        -- O pixel atual está dentro da área visível do modo ('1').
        o_visible : out   std_logic;
        -- O pixel atual está dentro do retângulo do framebuffer ampliado ('1').
        o_image   : out   std_logic;
        -- Coluna do framebuffer que cobre o pixel atual.
        o_fb_x    : out   std_logic_vector(log2_ceil(fb_width + 1) - 1 downto 0);
        -- Linha do framebuffer que cobre o pixel atual.
        o_fb_y    : out   std_logic_vector(log2_ceil(fb_height + 1) - 1 downto 0)
    );
end entity video_timing;

architecture rtl of video_timing is

    -- Pixels totais por linha.
    constant H_TOTAL  : natural := h_visible + h_front_porch + h_sync + h_back_porch;
    -- Linhas totais por quadro.
    constant V_TOTAL  : natural := v_visible + v_front_porch + v_sync + v_back_porch;
    -- Largura em pixels da imagem ampliada.
    constant IMAGE_W  : natural := fb_width * scale;
    -- Altura em linhas da imagem ampliada.
    constant IMAGE_H  : natural := fb_height * scale;
    -- Primeira coluna da imagem, que a centra na área visível.
    constant X_OFF    : natural := (h_visible - IMAGE_W) / 2;
    -- Primeira linha da imagem, que a centra na área visível.
    constant Y_OFF    : natural := (v_visible - IMAGE_H) / 2;
    -- Coluna em que o pulso de sincronismo horizontal começa.
    constant HS_BEGIN : natural := h_visible + h_front_porch;
    -- Linha em que o pulso de sincronismo vertical começa.
    constant VS_BEGIN : natural := v_visible + v_front_porch;
    -- Nível da saída de sincronismo horizontal durante o pulso.
    constant HS_LEVEL : std_logic := to_sl(h_sync_positive);
    -- Nível da saída de sincronismo vertical durante o pulso.
    constant VS_LEVEL : std_logic := to_sl(v_sync_positive);

    -- Coluna atual, de 0 a H_TOTAL - 1.
    signal h_cnt    : natural range 0 to H_TOTAL - 1 := 0;
    -- Linha atual, de 0 a V_TOTAL - 1.
    signal v_cnt    : natural range 0 to V_TOTAL - 1 := 0;
    -- Coluna do framebuffer que cobre a coluna atual.
    signal fb_x     : natural range 0 to fb_width - 1 := 0;
    -- Pixels já emitidos da coluna atual do framebuffer (0 a scale - 1).
    signal x_sub    : natural range 0 to scale - 1 := 0;
    -- Linha do framebuffer que cobre a linha atual.
    signal fb_y     : natural range 0 to fb_height - 1 := 0;
    -- Linhas já emitidas da linha atual do framebuffer (0 a scale - 1).
    signal y_sub    : natural range 0 to scale - 1 := 0;
    -- A coluna atual está dentro do retângulo da imagem.
    signal in_x     : std_logic;
    -- A linha atual está dentro do retângulo da imagem.
    signal in_y     : std_logic;
    -- A coluna atual está dentro da área visível.
    signal vis_x    : std_logic;
    -- A linha atual está dentro da área visível.
    signal vis_y    : std_logic;
    -- O pulso de sincronismo horizontal está ativo na coluna atual.
    signal hs_pulse : std_logic;
    -- O pulso de sincronismo vertical está ativo na linha atual.
    signal vs_pulse : std_logic;
    -- Pulso de sincronismo vertical registrado, em nível alto.
    signal vsync_q  : std_logic := '0';
    -- Apagamento vertical registrado, em nível alto.
    signal vblank_q : std_logic := '0';

begin

    assert IMAGE_W <= h_visible and IMAGE_H <= v_visible
        report "video_timing: a imagem ampliada deve caber na área visível"
        severity failure;

    in_x     <= '1' when h_cnt >= X_OFF and h_cnt < X_OFF + IMAGE_W else '0';
    in_y     <= '1' when v_cnt >= Y_OFF and v_cnt < Y_OFF + IMAGE_H else '0';
    vis_x    <= '1' when h_cnt < h_visible else '0';
    vis_y    <= '1' when v_cnt < v_visible else '0';
    hs_pulse <= '1' when h_cnt >= HS_BEGIN and h_cnt < HS_BEGIN + h_sync else '0';
    vs_pulse <= '1' when v_cnt >= VS_BEGIN and v_cnt < VS_BEGIN + v_sync else '0';

    o_hs      <= HS_LEVEL when hs_pulse = '1' else not HS_LEVEL;
    o_vs      <= VS_LEVEL when vs_pulse = '1' else not VS_LEVEL;
    o_visible <= vis_x and vis_y;
    o_image   <= in_x and in_y;
    o_fb_x    <= std_logic_vector(to_unsigned(fb_x, o_fb_x'length));
    o_fb_y    <= std_logic_vector(to_unsigned(fb_y, o_fb_y'length));
    o_vsync   <= vsync_q;
    o_vblank  <= vblank_q;

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
                vsync_q  <= vs_pulse;
                vblank_q <= to_sl(v_cnt >= v_visible);

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
