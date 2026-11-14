-- =============================================================================
-- Conversão de cor e empacotamento do pixel na palavra da memória
--
-- Domínio do clock do decodificador. Em dois estágios de pipeline, converte um
-- pixel YCbCr da norma ITU-R BT.601 (luminância de 16 a 235) em RGB de 8 bits
-- por canal, com coeficientes inteiros de oito bits fracionários, e o reduz a
-- RGB565; no formato de luminância, o byte Y passa direto. Devolve a palavra
-- de 32 bits, o endereço de palavra e a habilitação por byte que a memória de
-- dois clocks espera:
--   - RGB565: dois pixels por palavra, o de índice par nos bits 15:0;
--   - luminância: quatro pixels por palavra, o de índice 4k + n no byte n.
-- A latência é de dois ciclos entre i_we e o_we.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.tv_consts.all;

entity tv_color is
    generic (
        -- Largura em bits do índice de pixel.
        idx_bits : positive := 15
    );
    port (
        -- Clock do decodificador (TD_CLK27).
        i_clk    : in    std_logic;
        -- Pulso de pixel a gravar.
        i_we     : in    std_logic;
        -- Índice do pixel na memória.
        i_index  : in    std_logic_vector(idx_bits - 1 downto 0);
        -- Formato do pixel (FORMAT_RGB565 ou FORMAT_LUMA).
        i_format : in    std_logic;
        -- Luminância do pixel.
        i_y      : in    std_logic_vector(7 downto 0);
        -- Crominância azul do pixel.
        i_cb     : in    std_logic_vector(7 downto 0);
        -- Crominância vermelha do pixel.
        i_cr     : in    std_logic_vector(7 downto 0);
        -- Habilitação de escrita por byte da palavra.
        o_we     : out   std_logic_vector(3 downto 0) := (others => '0');
        -- Endereço de palavra da memória.
        o_waddr  : out   std_logic_vector(idx_bits - 2 downto 0) := (others => '0');
        -- Palavra a gravar, com o pixel repetido em todas as posições.
        o_wdata  : out   std_logic_vector(31 downto 0) := (others => '0')
    );
end entity tv_color;

architecture rtl of tv_color is

    -- Largura dos produtos e das somas com sinal.
    constant ACC_BITS : natural := 22;

    -- Pulso de pixel do estágio 1.
    signal we1     : std_logic := '0';
    -- Índice do pixel do estágio 1.
    signal index1  : std_logic_vector(idx_bits - 1 downto 0) := (others => '0');
    -- Formato do pixel do estágio 1.
    signal format1 : std_logic := '0';
    -- Luminância original do estágio 1.
    signal luma1   : std_logic_vector(7 downto 0) := (others => '0');
    -- Termo de luminância das três equações.
    signal term_y  : signed(ACC_BITS - 1 downto 0) := (others => '0');
    -- Termo de Cr do vermelho.
    signal term_rv : signed(ACC_BITS - 1 downto 0) := (others => '0');
    -- Soma dos termos de Cb e de Cr do verde.
    signal term_gv : signed(ACC_BITS - 1 downto 0) := (others => '0');
    -- Termo de Cb do azul.
    signal term_bu : signed(ACC_BITS - 1 downto 0) := (others => '0');

    -- Vermelho do pixel do estágio 2, 8 bits.
    signal red   : std_logic_vector(7 downto 0);
    -- Verde do pixel do estágio 2, 8 bits.
    signal green : std_logic_vector(7 downto 0);
    -- Azul do pixel do estágio 2, 8 bits.
    signal blue  : std_logic_vector(7 downto 0);
    -- Pixel RGB565 do estágio 2.
    signal rgb   : std_logic_vector(15 downto 0);

    -- Limita um valor com sinal ao intervalo de 0 a 255 depois do deslocamento fracionário.

    function clamp8 (v : signed(ACC_BITS - 1 downto 0)) return std_logic_vector;

    function clamp8 (v : signed(ACC_BITS - 1 downto 0)) return std_logic_vector is

        -- Valor sem os bits fracionários.
        variable s : signed(ACC_BITS - 1 downto 0);

    begin

        s := shift_right(v + to_signed(2 ** (COEF_SHIFT - 1), ACC_BITS), COEF_SHIFT);

        if s < 0 then
            return x"00";
        elsif s > 255 then
            return x"FF";
        else
            return std_logic_vector(s(7 downto 0));
        end if;

    end function clamp8;

begin

    p_stage1 : process (i_clk) is

        -- Luminância menos o preto, com piso em zero.
        variable luma_off : natural range 0 to 255;
        -- Crominância azul menos o ponto neutro.
        variable cb_off   : signed(9 downto 0);
        -- Crominância vermelha menos o ponto neutro.
        variable cr_off   : signed(9 downto 0);

    begin

        if rising_edge(i_clk) then
            luma_off := 0;
            if unsigned(i_y) >= LUMA_BLACK then
                luma_off := to_integer(unsigned(i_y)) - LUMA_BLACK;
            end if;

            cb_off := to_signed(to_integer(unsigned(i_cb)), 10) - to_signed(CHROMA_MID, 10);
            cr_off := to_signed(to_integer(unsigned(i_cr)), 10) - to_signed(CHROMA_MID, 10);

            we1     <= i_we;
            index1  <= i_index;
            format1 <= i_format;
            luma1   <= i_y;
            term_y  <= to_signed(COEF_Y * luma_off, ACC_BITS);
            term_rv <= resize(cr_off * to_signed(COEF_CR_R, 11), ACC_BITS);
            term_gv <= resize(cb_off * to_signed(COEF_CB_G, 11) + cr_off * to_signed(COEF_CR_G, 11), ACC_BITS);
            term_bu <= resize(cb_off * to_signed(COEF_CB_B, 11), ACC_BITS);
        end if;

    end process p_stage1;

    red   <= clamp8(term_y + term_rv);
    green <= clamp8(term_y - term_gv);
    blue  <= clamp8(term_y + term_bu);
    rgb   <= red(7 downto 3) & green(7 downto 2) & blue(7 downto 3);

    p_stage2 : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            o_we <= (others => '0');

            if we1 = '1' then
                if format1 = FORMAT_LUMA then
                    o_waddr <= '0' & index1(idx_bits - 1 downto 2);
                    o_wdata <= luma1 & luma1 & luma1 & luma1;
                    o_we(to_integer(unsigned(index1(1 downto 0)))) <= '1';
                else
                    o_waddr <= index1(idx_bits - 1 downto 1);
                    o_wdata <= rgb & rgb;
                    if index1(0) = '1' then
                        o_we <= "1100";
                    else
                        o_we <= "0011";
                    end if;
                end if;
            end if;
        end if;

    end process p_stage2;

end architecture rtl;
