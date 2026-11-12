-- =============================================================================
-- Registradores e janelas do periférico de vídeo (lado do processador)
--
-- Domínio do clock do sistema. Decodifica o barramento de periférico em três
-- regiões do endereço de palavra:
--   - bit mais significativo de i_address em '1': janela do framebuffer, só de
--     escrita, na ordem do barramento (índice de palavra da janela);
--   - bit mais significativo em '0' e bits acima do bit 8 zerados: espaço de
--     registradores (palavra 0 a 4) e paleta (palavra 256 a 511);
--   - qualquer outro endereço lê zero e ignora a escrita.
-- Registradores (palavra): 0 controle (bit 0 liga a exibição, L/E), 1 estado
-- (bit 0 sincronismo vertical, bit 1 apagamento vertical, L), 2 contador de
-- quadros (L), 3 geometria (largura nos bits 15:0, altura nos 31:16, L),
-- 4 formato (bits por pixel nos bits 7:0, ampliação nos 15:8, L).
--
-- A leitura é combinacional no endereço e não tem efeito colateral. A escrita
-- no framebuffer e na paleta sai registrada, um ciclo depois do pulso de
-- escrita, com a habilitação por faixa de byte copiada de i_byteena; a escrita
-- fora da janela útil do framebuffer é descartada. A escrita na paleta exige as
-- duas faixas baixas (meia palavra ou palavra) e só existe com pixel_bits = 8.
--
-- O contador de quadros conta as bordas de subida de i_vblank, e o reset
-- síncrono (i_rst = '1') zera os registradores.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.utils_pkg.all;
use work.video_consts.all;

entity video_regs is
    generic (
        -- Largura do framebuffer em pixels.
        fb_width   : positive := 320;
        -- Altura do framebuffer em pixels.
        fb_height  : positive := 200;
        -- Bits por pixel do framebuffer (16 = RGB444, 8 = índice de paleta).
        pixel_bits : positive := 16;
        -- Fator de ampliação do pixel do framebuffer.
        scale      : positive := 2;
        -- Largura do endereço de palavra da janela do periférico.
        addr_width : positive := 16
    );
    port (
        -- Clock do sistema.
        i_clk : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst : in    std_logic;

        -- Dado de escrita vindo do processador.
        i_data_in  : in    std_logic_vector(31 downto 0);
        -- Endereço de palavra dentro do periférico.
        i_address  : in    std_logic_vector(addr_width - 1 downto 0);
        -- Habilitação de bytes da escrita, um bit por byte.
        i_byteena  : in    std_logic_vector(3 downto 0);
        -- Pulso de escrita do processador ('1' = escreve).
        i_write    : in    std_logic;
        -- Dado de leitura para o processador.
        o_data_out : out   std_logic_vector(31 downto 0);

        -- Sincronismo vertical em nível alto, já sincronizado em i_clk.
        i_vsync  : in    std_logic;
        -- Apagamento vertical em nível alto, já sincronizado em i_clk.
        i_vblank : in    std_logic;

        -- Exibição do framebuffer habilitada ('1').
        o_enable   : out   std_logic;
        -- Dado de escrita registrado, comum ao framebuffer e à paleta.
        o_wdata    : out   std_logic_vector(31 downto 0);
        -- Habilitação de escrita por faixa de byte do framebuffer, registrada.
        o_fb_we    : out   std_logic_vector(3 downto 0);
        -- Endereço de palavra de escrita do framebuffer, registrado.
        o_fb_addr  : out   std_logic_vector(log2_ceil(fb_words(fb_width, fb_height, pixel_bits)) - 1 downto 0);
        -- Habilitação de escrita da paleta, registrada.
        o_pal_we   : out   std_logic;
        -- Índice de escrita da paleta, registrado.
        o_pal_addr : out   std_logic_vector(PALETTE_ADDR_BITS - 1 downto 0)
    );
end entity video_regs;

architecture rtl of video_regs is

    -- Palavras do framebuffer.
    constant FB_DEPTH     : positive := fb_words(fb_width, fb_height, pixel_bits);
    -- Largura do endereço de palavra do framebuffer.
    constant FB_ADDR_BITS : positive := log2_ceil(FB_DEPTH);
    -- A paleta existe só com 8 bits por pixel.
    constant HAS_PALETTE  : boolean  := pixel_bits = 8;

    -- Exibição habilitada.
    signal enable_reg  : std_logic                     := '0';
    -- Contador de quadros.
    signal frame_count : unsigned(31 downto 0)         := (others => '0');
    -- Valor anterior de i_vblank, para detectar a borda de subida.
    signal vblank_prev : std_logic                     := '0';
    -- Dado de escrita registrado.
    signal wdata_q     : std_logic_vector(31 downto 0) := (others => '0');
    -- Habilitação de escrita do framebuffer registrada.
    signal fb_we_q     : std_logic_vector(3 downto 0)  := (others => '0');
    -- Endereço de escrita do framebuffer registrado.
    signal fb_addr_q   : std_logic_vector(FB_ADDR_BITS - 1 downto 0) := (others => '0');
    -- Habilitação de escrita da paleta registrada.
    signal pal_we_q    : std_logic                     := '0';
    -- Índice de escrita da paleta registrado.
    signal pal_addr_q  : std_logic_vector(PALETTE_ADDR_BITS - 1 downto 0) := (others => '0');

    -- O endereço está na janela do framebuffer.
    signal in_window   : std_logic;
    -- Índice de palavra dentro da janela do framebuffer.
    signal window_idx  : natural;
    -- O endereço está no espaço de registradores e da paleta.
    signal in_space    : std_logic;
    -- Palavra dentro do espaço de registradores e da paleta.
    signal space_idx   : natural range 0 to 2 ** REG_SPACE_BITS - 1;
    -- O endereço é de um registrador.
    signal reg_hit     : std_logic;
    -- O endereço é de uma entrada da paleta.
    signal palette_hit : std_logic;
    -- A escrita acerta o framebuffer.
    signal fb_hit      : std_logic;

begin

    assert addr_width >= VIDEO_MIN_ADDR_WIDTH and addr_width > FB_ADDR_BITS
        report "video_regs: addr_width deve conter o espaço de registradores e o framebuffer"
        severity failure;

    in_window  <= i_address(addr_width - 1);
    window_idx <= to_integer(unsigned(i_address(addr_width - 2 downto 0)));
    in_space   <= '1' when in_window = '0' and unsigned(i_address(addr_width - 2 downto REG_SPACE_BITS)) = 0 else '0';
    space_idx  <= to_integer(unsigned(i_address(REG_SPACE_BITS - 1 downto 0)));

    reg_hit     <= '1' when in_space = '1' and space_idx < ADDR_PALETTE else '0';
    palette_hit <= '1' when in_space = '1' and space_idx >= ADDR_PALETTE and HAS_PALETTE else '0';
    fb_hit      <= '1' when in_window = '1' and window_idx < FB_DEPTH else '0';

    o_enable   <= enable_reg;
    o_wdata    <= wdata_q;
    o_fb_we    <= fb_we_q;
    o_fb_addr  <= fb_addr_q;
    o_pal_we   <= pal_we_q;
    o_pal_addr <= pal_addr_q;

    -- Leitura combinacional dos registradores; o framebuffer e a paleta não são legíveis.
    p_read : process (reg_hit, space_idx, enable_reg, i_vsync, i_vblank, frame_count) is
    begin

        o_data_out <= (others => '0');

        if reg_hit = '1' then
            case space_idx is
                when ADDR_CTRL =>
                    o_data_out(0) <= enable_reg;
                when ADDR_STATUS =>
                    o_data_out(0) <= i_vsync;
                    o_data_out(1) <= i_vblank;
                when ADDR_FRAME_COUNT =>
                    o_data_out <= std_logic_vector(frame_count);
                when ADDR_GEOMETRY =>
                    o_data_out <= std_logic_vector(to_unsigned(fb_height, 16)) & std_logic_vector(to_unsigned(fb_width, 16));
                when ADDR_FORMAT =>
                    o_data_out <= x"0000" & std_logic_vector(to_unsigned(scale, 8)) & std_logic_vector(to_unsigned(pixel_bits, 8));
                when others =>
                    null;
            end case;
        end if;

    end process p_read;

    -- Escritas: o controle muda no ciclo do pulso; o framebuffer e a paleta saem registrados.
    p_write : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            vblank_prev <= i_vblank;
            fb_we_q     <= (others => '0');
            pal_we_q    <= '0';

            if i_vblank = '1' and vblank_prev = '0' then
                frame_count <= frame_count + 1;
            end if;

            if i_write = '1' then
                wdata_q    <= i_data_in;
                fb_addr_q  <= std_logic_vector(to_unsigned(window_idx mod 2 ** FB_ADDR_BITS, FB_ADDR_BITS));
                pal_addr_q <= i_address(PALETTE_ADDR_BITS - 1 downto 0);

                if fb_hit = '1' then
                    fb_we_q <= i_byteena;
                end if;

                if palette_hit = '1' and i_byteena(1 downto 0) = "11" then
                    pal_we_q <= '1';
                end if;

                if reg_hit = '1' and space_idx = ADDR_CTRL and i_byteena(0) = '1' then
                    enable_reg <= i_data_in(0);
                end if;
            end if;

            if i_rst = '1' then
                enable_reg  <= '0';
                frame_count <= (others => '0');
                vblank_prev <= '0';
                fb_we_q     <= (others => '0');
                pal_we_q    <= '0';
            end if;
        end if;

    end process p_write;

end architecture rtl;
