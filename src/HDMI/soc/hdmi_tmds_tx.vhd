-- =============================================================================
-- Periférico de saída de vídeo HDMI com TMDS direto pela FPGA
--
-- Liga o processador a um conector HDMI ligado direto aos pinos da FPGA, sem
-- transmissor externo (caso da MKR Vidor 4000). É um invólucro estrutural que
-- compõe duas entidades já verificadas e não tem lógica própria:
--   - hdmi_tx, sem o sequenciador do ADV7513, que traz os registradores do
--     vídeo e do HDMI, a paleta, o framebuffer, a temporização e a varredura, e
--     entrega o vídeo paralelo RGB de 24 bits com DE, HS e VS no clock de pixel;
--   - tmds_tx, que codifica esse vídeo em TMDS e serializa os três canais de
--     dados e o canal de clock com o clock de 5 vezes o de pixel.
--
-- O mapa de endereços, a temporização por generics, o formato do pixel e as
-- interrupções são os do hdmi_tx. Sem sequenciador, o bit de inicialização do
-- estado vale '0' e o reinício do sequenciador não tem efeito. O pino de
-- detecção de conexão (hot plug) ocupa o lugar do pino de interrupção do
-- transmissor: o bit 0 do estado do HDMI reflete i_hpd, e a subida de i_hpd
-- levanta a interrupção de bit 1 quando ela está habilitada. O canal DDC do
-- conector (SCL e SDA) não passa por este bloco; o topo o liga a um mestre I2C
-- de uso geral, que lê a EDID por software.
--
-- Domínios de clock:
--   - i_clk (sistema): registradores, janelas de escrita e interrupções;
--   - i_pixel_clk (pixel): temporização, varredura e codificação TMDS;
--   - i_serial_clk (serial): 5 vezes i_pixel_clk, do mesmo PLL, só para a
--     serialização dos pares.
-- O reset do sistema atravessa para o domínio de pixel por um sincronizador de
-- dois estágios e deve durar pelo menos três ciclos de i_pixel_clk.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.hdmi_consts.all;
use work.tmds_consts.all;

entity hdmi_tmds_tx is
    generic (
        -- Largura do framebuffer em pixels (uma linha deve ocupar um número inteiro de palavras de 32 bits).
        fb_width        : positive := 320;
        -- Altura do framebuffer em pixels.
        fb_height       : positive := 180;
        -- Formato do pixel do framebuffer: "indexed" (índice de paleta de 8 bits) ou "direct" (RGB565).
        pixel_format    : string   := "indexed";
        -- Fator de ampliação do pixel do framebuffer em x e em y (a imagem deve caber na área visível).
        scale           : positive := 4;
        -- Largura do endereço de palavra da janela do periférico (16 = janela de 256 KiB).
        addr_width      : positive := 16;
        -- Pixels visíveis por linha.
        h_visible       : positive := 1280;
        -- Pixels do pórtico frontal horizontal.
        h_front_porch   : natural  := 110;
        -- Pixels do pulso de sincronismo horizontal.
        h_sync          : positive := 40;
        -- Pixels do pórtico traseiro horizontal.
        h_back_porch    : natural  := 220;
        -- Polaridade do sincronismo horizontal: verdadeiro = nível alto durante o pulso.
        h_sync_positive : boolean  := true;
        -- Linhas visíveis por quadro.
        v_visible       : positive := 720;
        -- Linhas do pórtico frontal vertical.
        v_front_porch   : natural  := 5;
        -- Linhas do pulso de sincronismo vertical.
        v_sync          : positive := 5;
        -- Linhas do pórtico traseiro vertical.
        v_back_porch    : natural  := 20;
        -- Polaridade do sincronismo vertical: verdadeiro = nível alto durante o pulso.
        v_sync_positive : boolean  := true;
        -- Número do modo CEA-861 (VIC) da instância, ou zero para um modo próprio (só informativo).
        mode_id         : natural  := 4;
        -- Clock de pixel do modo em kHz (só informativo, o clock real vem do PLL do topo).
        pixel_clock_khz : natural  := 74250;
        -- Inversão de cada par diferencial, bit 0 azul, 1 verde, 2 vermelho e 3 clock; '1' inverte o par.
        lane_invert     : std_logic_vector(DATA_LANES downto 0) := (others => '0');
        -- Família da FPGA passada ao registrador DDR de saída da placa.
        device_family   : string   := "Cyclone 10 LP"
    );
    port (
        -- Clock do sistema.
        i_clk        : in    std_logic;
        -- Clock de pixel do modo, assíncrono em relação a i_clk.
        i_pixel_clk  : in    std_logic;
        -- Clock serial, cinco vezes mais rápido que o de pixel, do mesmo PLL.
        i_serial_clk : in    std_logic;
        -- Reset síncrono do sistema, ativo em '1'.
        i_rst        : in    std_logic;

        -- Dado de escrita vindo do processador.
        i_data_in    : in    std_logic_vector(31 downto 0);
        -- Endereço de palavra dentro do periférico.
        i_address    : in    std_logic_vector(addr_width - 1 downto 0);
        -- Habilitação de bytes da escrita, um bit por byte.
        i_byteena    : in    std_logic_vector(3 downto 0);
        -- Pulso de escrita do processador ('1' = escreve).
        i_write      : in    std_logic;
        -- Dado de leitura para o processador.
        o_data_out   : out   std_logic_vector(31 downto 0);
        -- Interrupção em nível (fim de quadro ou subida de i_hpd, conforme as máscaras).
        o_irq        : out   std_logic;

        -- Detecção de conexão do monitor (hot plug), ativa em '1', assíncrona.
        i_hpd        : in    std_logic;

        -- Canais de dados TMDS, lado positivo do par: 0 azul, 1 verde, 2 vermelho.
        o_tmds_d     : out   std_logic_vector(DATA_LANES - 1 downto 0);
        -- Canal de clock TMDS, lado positivo do par.
        o_tmds_clk   : out   std_logic
    );
end entity hdmi_tmds_tx;

architecture rtl of hdmi_tmds_tx is

    -- Reset do sistema levado ao domínio de pixel, em vetor de um bit.
    signal pix_rst_vec : std_logic_vector(0 downto 0);
    -- Reset no domínio de pixel.
    signal pix_rst     : std_logic;

    -- Vídeo RGB de 24 bits do periférico, vermelho em 23:16.
    signal video_rgb   : std_logic_vector(3 * OUT_CHANNEL_BITS - 1 downto 0);
    -- Habilitação de dados do vídeo.
    signal video_de    : std_logic;
    -- Sincronismo horizontal do vídeo, na polaridade do modo.
    signal video_hs    : std_logic;
    -- Sincronismo vertical do vídeo, na polaridade do modo.
    signal video_vs    : std_logic;

begin

    u_video : entity work.hdmi_tx
        generic map (
            fb_width        => fb_width,
            fb_height       => fb_height,
            pixel_format    => pixel_format,
            scale           => scale,
            addr_width      => addr_width,
            h_visible       => h_visible,
            h_front_porch   => h_front_porch,
            h_sync          => h_sync,
            h_back_porch    => h_back_porch,
            h_sync_positive => h_sync_positive,
            v_visible       => v_visible,
            v_front_porch   => v_front_porch,
            v_sync          => v_sync,
            v_back_porch    => v_back_porch,
            v_sync_positive => v_sync_positive,
            mode_id         => mode_id,
            pixel_clock_khz => pixel_clock_khz,
            init_enable     => false,
            int_active_low  => false
        )
        port map (
            i_clk         => i_clk,
            i_pixel_clk   => i_pixel_clk,
            i_rst         => i_rst,
            i_data_in     => i_data_in,
            i_address     => i_address,
            i_byteena     => i_byteena,
            i_write       => i_write,
            o_data_out    => o_data_out,
            o_irq         => o_irq,
            o_tx_d        => video_rgb,
            o_tx_clk      => open,
            o_tx_de       => video_de,
            o_tx_hs       => video_hs,
            o_tx_vs       => video_vs,
            i_tx_int      => i_hpd,
            i_i2c_sda     => '1',
            o_i2c_sda_out => open,
            o_i2c_sda_oe  => open,
            o_i2c_scl_out => open,
            o_i2c_scl_oe  => open
        );

    u_rst_sync : entity work.synchronizer
        port map (
            i_clk => i_pixel_clk,
            i_rst => '0',
            i_d   => (0 => i_rst),
            o_d   => pix_rst_vec
        );

    pix_rst <= pix_rst_vec(0);

    u_tmds : entity work.tmds_tx
        generic map (
            lane_invert   => lane_invert,
            device_family => device_family
        )
        port map (
            i_clk_pixel => i_pixel_clk,
            i_clk_x5    => i_serial_clk,
            i_rst       => pix_rst,
            i_rgb       => video_rgb,
            i_de        => video_de,
            i_hsync     => video_hs,
            i_vsync     => video_vs,
            o_data      => o_tmds_d,
            o_clk       => o_tmds_clk
        );

end architecture rtl;
