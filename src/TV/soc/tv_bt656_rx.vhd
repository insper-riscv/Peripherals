-- =============================================================================
-- Receptor de fluxo ITU-R BT.656 de 8 bits
--
-- Domínio do clock do decodificador (TD_CLK27). Reconhece as referências de
-- temporização FF 00 00 XY, confere os bits de proteção da palavra XY (quando
-- check_protection = true), separa o início (SAV) e o fim (EAV) do vídeo ativo
-- e acompanha o campo e o apagamento vertical. Os bytes de vídeo ativo
-- (Cb Y Cr Y) passam por uma linha de atraso de quatro bytes, e os três bytes
-- que antecedem o EAV, que só se revelam prefixo na palavra XY, são
-- descartados nela; assim nenhum byte de prefixo vira pixel. Cada par Cb Y Cr
-- Y vira dois pixels YCbCr 4:4:4 em ciclos consecutivos, com a crominância
-- repetida.
--
-- Eventos de um ciclo, todos registrados:
--   - o_line_start: SAV de uma linha de vídeo ativo (V = 0);
--   - o_field_start: primeira linha ativa de um campo (V = 0 depois de V = 1);
--   - o_field_end: primeiro código com V = 1 depois de vídeo ativo;
--   - o_error: código com proteção inválida, SAV dentro de linha, EAV fora de
--     linha ou EAV no meio de um grupo Cb Y Cr Y.
-- O_present vale '1' enquanto o último código válido tem menos de
-- present_cycles ciclos.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.utils_pkg.all;
use work.tv_consts.all;

entity tv_bt656_rx is
    generic (
        -- Confere os quatro bits de proteção da palavra XY.
        check_protection : boolean  := true;
        -- Ciclos sem código válido depois dos quais o vídeo é dado como ausente.
        present_cycles   : positive := 4096
    );
    port (
        -- Clock do decodificador (TD_CLK27).
        i_clk         : in    std_logic;
        -- Reset síncrono em i_clk, ativo em '1'.
        i_rst         : in    std_logic;
        -- Byte do fluxo BT.656 (TD_DATA).
        i_data        : in    std_logic_vector(7 downto 0);
        -- Pulso do SAV de uma linha de vídeo ativo.
        o_line_start  : out   std_logic := '0';
        -- Pulso da primeira linha ativa de um campo.
        o_field_start : out   std_logic := '0';
        -- Pulso do fim do vídeo ativo de um campo.
        o_field_end   : out   std_logic := '0';
        -- Pulso de erro de sincronismo.
        o_error       : out   std_logic := '0';
        -- Campo do último código válido ('0' primeiro campo, '1' segundo).
        o_field       : out   std_logic;
        -- Vídeo presente: houve código válido nos últimos present_cycles ciclos.
        o_present     : out   std_logic;
        -- Pulso de pixel válido em o_y, o_cb e o_cr.
        o_pix_valid   : out   std_logic := '0';
        -- Luminância do pixel.
        o_y           : out   std_logic_vector(7 downto 0) := (others => '0');
        -- Crominância azul do pixel.
        o_cb          : out   std_logic_vector(7 downto 0) := (others => '0');
        -- Crominância vermelha do pixel.
        o_cr          : out   std_logic_vector(7 downto 0) := (others => '0')
    );
end entity tv_bt656_rx;

architecture rtl of tv_bt656_rx is

    -- Byte recebido, registrado uma vez.
    signal d0 : std_logic_vector(7 downto 0) := (others => '0');
    -- Byte anterior a d0.
    signal h1 : std_logic_vector(7 downto 0) := (others => '0');
    -- Segundo byte anterior a d0.
    signal h2 : std_logic_vector(7 downto 0) := (others => '0');
    -- Terceiro byte anterior a d0.
    signal h3 : std_logic_vector(7 downto 0) := (others => '0');

    -- d0 é a palavra XY de uma referência de temporização (prefixo FF 00 00 antes dela).
    signal ref_hit   : std_logic;
    -- Bits de proteção que a palavra d0 deveria ter.
    signal protect   : std_logic_vector(3 downto 0);
    -- Os bits de proteção de d0 estão corretos (ou a conferência está desligada).
    signal prot_ok   : std_logic;
    -- A referência tem o bit fixo e a proteção corretos.
    signal ref_ok    : std_logic;
    -- A referência é inválida.
    signal ref_bad   : std_logic;
    -- Campo, apagamento e SAV/EAV da palavra d0.
    signal xy_field  : std_logic;
    -- Apagamento vertical da palavra d0.
    signal xy_vblank : std_logic;
    -- Palavra d0 é de EAV ('1') ou de SAV ('0').
    signal xy_eav    : std_logic;

    -- Dentro de uma linha, entre o SAV e o EAV.
    signal in_line   : std_logic := '0';
    -- Os bytes que chegam são vídeo ativo.
    signal active    : std_logic := '0';
    -- Apagamento vertical da referência anterior.
    signal v_prev    : std_logic := '0';
    -- Campo do último código válido.
    signal field_reg : std_logic := '0';
    -- Já houve um código válido, e v_prev vale o apagamento dele.
    signal v_known   : std_logic := '0';
    -- Código EAV válido do ciclo anterior, para conferir o alinhamento.
    signal eav_q     : std_logic := '0';

    -- Byte da linha de atraso, estágio 1.
    signal s1 : std_logic_vector(7 downto 0) := (others => '0');
    -- Byte da linha de atraso, estágio 2.
    signal s2 : std_logic_vector(7 downto 0) := (others => '0');
    -- Byte da linha de atraso, estágio 3.
    signal s3 : std_logic_vector(7 downto 0) := (others => '0');
    -- Byte da linha de atraso consumido, estágio 4.
    signal s4 : std_logic_vector(7 downto 0) := (others => '0');
    -- Validade do estágio 1.
    signal v1 : std_logic := '0';
    -- Validade do estágio 2.
    signal v2 : std_logic := '0';
    -- Validade do estágio 3.
    signal v3 : std_logic := '0';
    -- Validade do estágio 4.
    signal v4 : std_logic := '0';

    -- Posição do byte no grupo Cb Y Cr Y.
    signal phase  : unsigned(1 downto 0)         := (others => '0');
    -- Cb do grupo corrente.
    signal cb_reg : std_logic_vector(7 downto 0) := (others => '0');
    -- Y do primeiro pixel do grupo corrente.
    signal y0_reg : std_logic_vector(7 downto 0) := (others => '0');
    -- Cr do grupo corrente.
    signal cr_reg : std_logic_vector(7 downto 0) := (others => '0');

    -- Ciclos desde o último código válido, saturado em present_cycles.
    signal silence : natural range 0 to present_cycles := present_cycles;

begin

    ref_hit <= '1' when h3 = BT656_PREFIX_0 and h2 = BT656_PREFIX_1 and h1 = BT656_PREFIX_1 else '0';

    xy_field  <= d0(XY_FIELD_BIT);
    xy_vblank <= d0(XY_VBLANK_BIT);
    xy_eav    <= d0(XY_EAV_BIT);

    protect(3) <= xy_vblank xor xy_eav;
    protect(2) <= xy_field xor xy_eav;
    protect(1) <= xy_field xor xy_vblank;
    protect(0) <= xy_field xor xy_vblank xor xy_eav;

    prot_ok <= '1' when not check_protection or d0(3 downto 0) = protect else '0';
    ref_ok  <= ref_hit and d0(XY_FIXED_BIT) and prot_ok;
    ref_bad <= ref_hit and not ref_ok;

    o_field <= field_reg;

    p_stream : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            d0 <= i_data;
            h1 <= d0;
            h2 <= h1;
            h3 <= h2;

            -- Linha de atraso: os três bytes antes da palavra XY de uma referência saem da fila.
            s1 <= d0;
            s2 <= s1;
            s3 <= s2;
            s4 <= s3;
            v1 <= active and not ref_hit;
            v2 <= v1 and not ref_hit;
            v3 <= v2 and not ref_hit;
            v4 <= v3 and not ref_hit;

            o_line_start  <= '0';
            o_field_start <= '0';
            o_field_end   <= '0';
            o_error       <= ref_bad;
            o_pix_valid   <= '0';
            eav_q         <= ref_ok and xy_eav;

            if eav_q = '1' and phase /= 0 then
                o_error <= '1';
            end if;

            -- Byte de vídeo consumido: o grupo Cb Y Cr Y gera um pixel em Cr e outro no segundo Y.
            if v4 = '1' then
                phase <= phase + 1;

                case phase is
                    when "00" =>
                        cb_reg <= s4;
                    when "01" =>
                        y0_reg <= s4;
                    when "10" =>
                        cr_reg      <= s4;
                        o_pix_valid <= '1';
                        o_y         <= y0_reg;
                        o_cb        <= cb_reg;
                        o_cr        <= s4;
                    when others =>
                        o_pix_valid <= '1';
                        o_y         <= s4;
                        o_cb        <= cb_reg;
                        o_cr        <= cr_reg;
                end case;
            end if;

            if ref_ok = '1' then
                field_reg <= xy_field;
                v_prev    <= xy_vblank;
                v_known   <= '1';
                silence   <= 0;

                if xy_eav = '0' then
                    -- SAV: abre a linha; só há vídeo ativo com V = 0.
                    in_line <= '1';
                    active  <= not xy_vblank;
                    phase   <= (others => '0');

                    if in_line = '1' then
                        o_error <= '1';
                    end if;

                    o_line_start  <= not xy_vblank;
                    o_field_start <= not xy_vblank and v_prev;
                else
                    -- EAV: fecha a linha.
                    in_line <= '0';
                    active  <= '0';

                    if in_line = '0' then
                        o_error <= '1';
                    end if;
                end if;

                o_field_end <= xy_vblank and not v_prev and v_known;
            elsif silence < present_cycles then
                silence <= silence + 1;
            end if;

            if i_rst = '1' then
                in_line       <= '0';
                active        <= '0';
                v_prev        <= '0';
                v_known       <= '0';
                eav_q         <= '0';
                v1            <= '0';
                v2            <= '0';
                v3            <= '0';
                v4            <= '0';
                phase         <= (others => '0');
                silence       <= present_cycles;
                o_line_start  <= '0';
                o_field_start <= '0';
                o_field_end   <= '0';
                o_error       <= '0';
                o_pix_valid   <= '0';
            end if;
        end if;

    end process p_stream;

    o_present <= '1' when silence < present_cycles else '0';

end architecture rtl;
