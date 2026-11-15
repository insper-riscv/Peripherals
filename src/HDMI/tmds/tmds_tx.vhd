-- =============================================================================
-- Transmissor TMDS direto para o conector HDMI (saída diferencial sem chip externo)
--
-- Recebe vídeo digital paralelo RGB de 24 bits com DE, HS e VS (o mesmo
-- barramento que o periférico hdmi_tx entrega ao ADV7513) e gera os quatro
-- canais TMDS de um conector HDMI ligado direto à FPGA, sem transmissor
-- externo: três canais de dados e o de clock. É um sinal DVI 1.0, sem ilhas de
-- dados, áudio nem InfoFrames, que os monitores aceitam como vídeo HDMI.
--
-- Estrutura, sem lógica própria além da fiação:
--   - um codificador (tmds_encoder) por canal de dados, no clock de pixel; o
--     azul leva HS e VS nos bits de controle do apagamento, o verde e o
--     vermelho levam zero;
--   - um serializador (tmds_serializer) por canal, incluindo o canal de clock,
--     cujo símbolo é constante;
--   - um registrador DDR de saída (tmds_ddr_out) de quatro bits, que põe dois
--     bits por ciclo do clock de 5 vezes nos pinos.
--
-- Canais: o_data(0) azul, o_data(1) verde e o_data(2) vermelho; o_clk é o
-- canal de clock. As saídas são o lado positivo de cada par; a polaridade de um
-- par ligado ao contrário se corrige com lane_invert, e o lado negativo vem da
-- atribuição de pino diferencial do Quartus.
--
-- Clocks: i_clk_pixel é o clock de pixel do modo e i_clk_x5 vale cinco vezes
-- esse, do mesmo PLL. Com 720p60 são 74,25 MHz e 371,25 MHz, com 480p60 são
-- 27 MHz e 135 MHz.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.tmds_consts.all;

entity tmds_tx is
    generic (
        -- Inversão de cada par diferencial, bit 0 azul, 1 verde, 2 vermelho e 3 clock; '1' inverte o par.
        lane_invert : std_logic_vector(DATA_LANES downto 0) := (others => '0');
        -- Família da FPGA passada ao registrador DDR de saída da placa.
        device_family : string := "Cyclone 10 LP"
    );
    port (
        -- Clock de pixel.
        i_clk_pixel : in    std_logic;
        -- Clock cinco vezes mais rápido que o de pixel, do mesmo PLL.
        i_clk_x5    : in    std_logic;
        -- Reset síncrono ao clock de pixel, ativo em '1'.
        i_rst       : in    std_logic;
        -- Pixel RGB de 24 bits, vermelho em 23:16, verde em 15:8 e azul em 7:0.
        i_rgb       : in    std_logic_vector(DATA_LANES * PIXEL_BITS - 1 downto 0);
        -- Habilitação de dados, '1' durante a área visível.
        i_de        : in    std_logic;
        -- Sincronismo horizontal, já na polaridade do modo.
        i_hsync     : in    std_logic;
        -- Sincronismo vertical, já na polaridade do modo.
        i_vsync     : in    std_logic;
        -- Canais de dados, lado positivo do par: 0 azul, 1 verde, 2 vermelho.
        o_data      : out   std_logic_vector(DATA_LANES - 1 downto 0);
        -- Canal de clock, lado positivo do par.
        o_clk       : out   std_logic
    );
end entity tmds_tx;

architecture rtl of tmds_tx is

    -- Símbolos dos quatro canais, no domínio de pixel; o índice 3 é o canal de clock.
    type token_array_t is array (0 to DATA_LANES) of std_logic_vector(TOKEN_BITS - 1 downto 0);

    -- Símbolo de cada canal.
    signal tokens : token_array_t;
    -- Bit da metade alta de cada canal, antes da inversão de polaridade.
    signal lane_h : std_logic_vector(DATA_LANES downto 0);
    -- Bit da metade baixa de cada canal, antes da inversão de polaridade.
    signal lane_l : std_logic_vector(DATA_LANES downto 0);
    -- Bit da metade alta de cada canal, com a polaridade corrigida.
    signal drive_h : std_logic_vector(DATA_LANES downto 0);
    -- Bit da metade baixa de cada canal, com a polaridade corrigida.
    signal drive_l : std_logic_vector(DATA_LANES downto 0);
    -- Pinos dos quatro canais, na saída do registrador DDR.
    signal pins   : std_logic_vector(DATA_LANES downto 0);

begin

    gen_lanes : for lane in 0 to DATA_LANES - 1 generate

        -- Bit de controle C0 do canal, o sincronismo horizontal no azul e zero nos outros.
        signal c0 : std_logic;
        -- Bit de controle C1 do canal, o sincronismo vertical no azul e zero nos outros.
        signal c1 : std_logic;

    begin

        -- O azul leva os sincronismos no apagamento; os outros canais enviam zero.
        c0 <= i_hsync when lane = 0 else '0';
        c1 <= i_vsync when lane = 0 else '0';

        u_encoder : entity work.tmds_encoder
            port map (
                i_clk => i_clk_pixel,
                i_rst => i_rst,
                i_de  => i_de,
                i_c0  => c0,
                i_c1  => c1,
                i_d   => i_rgb((lane + 1) * PIXEL_BITS - 1 downto lane * PIXEL_BITS),
                o_q   => tokens(lane)
            );

    end generate gen_lanes;

    tokens(DATA_LANES) <= TOKEN_CLOCK;

    gen_serializers : for lane in 0 to DATA_LANES generate
    begin

        u_serializer : entity work.tmds_serializer
            port map (
                i_clk_pixel => i_clk_pixel,
                i_clk_x5    => i_clk_x5,
                i_token     => tokens(lane),
                o_h         => lane_h(lane),
                o_l         => lane_l(lane)
            );

    end generate gen_serializers;

    drive_h <= lane_h xor lane_invert;
    drive_l <= lane_l xor lane_invert;

    u_ddr : entity work.tmds_ddr_out
        generic map (
            width         => DATA_LANES + 1,
            device_family => device_family
        )
        port map (
            i_clk => i_clk_x5,
            i_d_h => drive_h,
            i_d_l => drive_l,
            o_q   => pins
        );

    o_data <= pins(DATA_LANES - 1 downto 0);
    o_clk  <= pins(DATA_LANES);

end architecture rtl;
