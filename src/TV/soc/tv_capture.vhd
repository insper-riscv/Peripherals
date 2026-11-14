-- =============================================================================
-- Controle da captura de um quadro e geometria da decimação
--
-- Domínio do clock do decodificador (TD_CLK27). Recebe do receptor BT.656 os
-- eventos de linha e de campo e os pixels YCbCr, e decide qual pixel vai à
-- memória e em que posição. Uma captura espera o primeiro campo pedido, segue
-- as linhas ativas e termina no fim do último campo:
--   - i_field_sel = "00": os dois campos, entrelaçados num quadro (a linha n
--     do campo F ocupa a linha 2n + F do quadro de origem);
--   - "01" ou "10": só o primeiro ou só o segundo campo (a linha n é a n).
-- A decimação mantém o pixel de coluna e de linha de origem múltiplas dos
-- fatores i_x_div e i_y_div (amostragem pontual, sem média), e a posição na
-- memória é a coluna e a linha de origem divididas pelos fatores. Os pixels
-- fora de src_width por src_height, de fb_width por fb_height ou de linhas de
-- outro campo são descartados. A captura é abortada, sem quadro pronto, se o
-- vídeo some ou se um campo chega fora da ordem esperada.
--
-- A configuração (fatores, formato e campo) é lida no pulso i_start e deve
-- ficar parada durante a captura. A saída o_we e os dados seguem o pixel
-- aceito com um ciclo de atraso; o_index é o índice do pixel na memória, linha
-- a linha, com fb_width pixels por linha.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.utils_pkg.all;
use work.tv_consts.all;

entity tv_capture is
    generic (
        -- Largura da memória do quadro em pixels.
        fb_width   : positive := 160;
        -- Altura da memória do quadro em pixels.
        fb_height  : positive := 120;
        -- Largura em pixels da área de origem capturada a partir do canto superior esquerdo.
        src_width  : positive := 720;
        -- Altura em linhas da área de origem capturada, contando os dois campos.
        src_height : positive := 480
    );
    port (
        -- Clock do decodificador (TD_CLK27).
        i_clk         : in    std_logic;
        -- Reset síncrono em i_clk, ativo em '1'.
        i_rst         : in    std_logic;
        -- Pulso de início de uma captura.
        i_start       : in    std_logic;
        -- Fator de decimação em x (0 vale 1), parado durante a captura.
        i_x_div       : in    std_logic_vector(7 downto 0);
        -- Fator de decimação em y (0 vale 1), parado durante a captura.
        i_y_div       : in    std_logic_vector(7 downto 0);
        -- Seletor de campo, parado durante a captura.
        i_field_sel   : in    std_logic_vector(1 downto 0);
        -- Formato do pixel, parado durante a captura.
        i_format      : in    std_logic;
        -- Pulso do SAV de uma linha ativa, do receptor.
        i_line_start  : in    std_logic;
        -- Pulso da primeira linha ativa de um campo, do receptor.
        i_field_start : in    std_logic;
        -- Pulso do fim do vídeo ativo de um campo, do receptor.
        i_field_end   : in    std_logic;
        -- Campo do último código, do receptor.
        i_field       : in    std_logic;
        -- Vídeo presente, do receptor.
        i_present     : in    std_logic;
        -- Pulso de pixel válido, do receptor.
        i_pix_valid   : in    std_logic;
        -- Luminância do pixel.
        i_y           : in    std_logic_vector(7 downto 0);
        -- Crominância azul do pixel.
        i_cb          : in    std_logic_vector(7 downto 0);
        -- Crominância vermelha do pixel.
        i_cr          : in    std_logic_vector(7 downto 0);
        -- Captura em andamento.
        o_busy        : out   std_logic := '0';
        -- Pulso de fim de captura, concluída ou abortada.
        o_done        : out   std_logic := '0';
        -- Resultado da captura, válido a partir de o_done e até o próximo início ('1' quadro completo).
        o_ok          : out   std_logic := '0';
        -- Pixel aceito para a memória.
        o_we          : out   std_logic := '0';
        -- Índice do pixel na memória, linha a linha.
        o_index       : out   std_logic_vector(log2_ceil(fb_width * fb_height) - 1 downto 0) := (others => '0');
        -- Formato do pixel da captura em curso.
        o_format      : out   std_logic;
        -- Luminância do pixel aceito.
        o_y           : out   std_logic_vector(7 downto 0) := (others => '0');
        -- Crominância azul do pixel aceito.
        o_cb          : out   std_logic_vector(7 downto 0) := (others => '0');
        -- Crominância vermelha do pixel aceito.
        o_cr          : out   std_logic_vector(7 downto 0) := (others => '0')
    );
end entity tv_capture;

architecture rtl of tv_capture is

    -- Estados da captura de um quadro.
    type state_t is (ST_IDLE, ST_ARM, ST_RUN);

    -- Maior linha de origem contada (a contagem para aqui).
    constant COORD_MAX : natural := 4095;
    -- Largura em bits do índice de pixel.
    constant IDX_BITS  : natural := log2_ceil(fb_width * fb_height);

    -- Estado da captura.
    signal state     : state_t := ST_IDLE;
    -- Fator de decimação em x da captura em curso.
    signal x_div     : natural range 1 to 255 := 1;
    -- Fator de decimação em y da captura em curso.
    signal y_div     : natural range 1 to 255 := 1;
    -- Seletor de campo da captura em curso.
    signal field_sel : std_logic_vector(1 downto 0) := FIELD_BOTH;
    -- Formato do pixel da captura em curso.
    signal format    : std_logic := FORMAT_RGB565;
    -- Captura dos dois campos, na etapa do segundo campo.
    signal second    : std_logic := '0';
    -- Um campo está aberto: o início dele foi visto e o fim ainda não.
    signal in_field  : std_logic := '0';
    -- Resultado da última captura.
    signal ok_reg    : std_logic := '0';

    -- Linha de origem corrente, contando os dois campos.
    signal src_y     : natural range 0 to COORD_MAX := 0;
    -- Resto da linha de origem pelo fator em y.
    signal y_phase   : natural range 0 to 255 := 0;
    -- Linha da memória da linha corrente.
    signal row       : natural range 0 to COORD_MAX := 0;
    -- A linha corrente começou e falta decidir se é capturada.
    signal line_pend : std_logic := '0';
    -- A linha corrente é capturada.
    signal line_ok   : std_logic := '0';
    -- Índice do primeiro pixel da linha corrente na memória.
    signal row_base  : natural range 0 to 2 ** IDX_BITS - 1 := 0;

    -- Coluna de origem do próximo pixel.
    signal src_x     : natural range 0 to src_width := 0;
    -- Resto da coluna de origem pelo fator em x.
    signal x_phase   : natural range 0 to 255 := 0;
    -- Coluna da memória do próximo pixel.
    signal col       : natural range 0 to fb_width := 0;

    -- O campo do código atual é o primeiro campo da captura.
    signal field_match : std_logic;
    -- O campo do código atual é um dos campos capturados.
    signal field_wanted : std_logic;

begin

    field_match <= '1' when (field_sel = FIELD_FIRST and i_field = '0') or
                            (field_sel = FIELD_SECOND and i_field = '1') or
                            (field_sel /= FIELD_FIRST and field_sel /= FIELD_SECOND and i_field = '0') else '0';

    field_wanted <= '1' when (field_sel /= FIELD_FIRST and field_sel /= FIELD_SECOND) or
                             (field_sel = FIELD_FIRST and i_field = '0') or
                             (field_sel = FIELD_SECOND and i_field = '1') else '0';

    o_busy   <= '1' when state /= ST_IDLE else '0';
    o_ok     <= ok_reg;
    o_format <= format;

    p_capture : process (i_clk) is

        -- Captura dos dois campos entrelaçados.
        variable both : boolean;
        -- Linha e resto da linha de origem depois de um passo.
        variable step_y : natural range 0 to COORD_MAX + 2;
        -- Resto em y depois do passo.
        variable step_p : natural range 0 to 257;
        -- Linha da memória depois do passo.
        variable step_r : natural range 0 to COORD_MAX + 2;
        -- Linhas de origem avançadas entre duas linhas de um campo.
        variable stride : natural range 1 to 2;
        -- Índice do pixel na memória.
        variable index  : natural range 0 to 2 ** (IDX_BITS + 1) - 1;
        -- Pixel aceito.
        variable accept : boolean;

    begin

        if rising_edge(i_clk) then
            both   := field_sel /= FIELD_FIRST and field_sel /= FIELD_SECOND;
            stride := 1;
            if both then
                stride := 2;
            end if;

            o_done <= '0';
            o_we   <= '0';

            -- Posição vertical: avança a cada linha de um campo e reinicia no primeiro campo.
            if i_line_start = '1' then
                src_x   <= 0;
                x_phase <= 0;
                col     <= 0;

                line_pend <= '1';

                if i_field_start = '1' then
                    if both and i_field = '1' then
                        src_y <= 1;
                        if y_div = 1 then
                            y_phase <= 0;
                            row     <= 1;
                        else
                            y_phase <= 1;
                            row     <= 0;
                        end if;
                    else
                        src_y   <= 0;
                        y_phase <= 0;
                        row     <= 0;
                    end if;
                else
                    step_y := src_y;
                    if src_y < COORD_MAX then
                        step_y := src_y + stride;
                    end if;
                    step_p := y_phase + stride;
                    step_r := row;
                    if step_p >= y_div then
                        step_p := step_p - y_div;
                        step_r := step_r + 1;
                    end if;
                    if step_p >= y_div then
                        step_p := step_p - y_div;
                        step_r := step_r + 1;
                    end if;
                    src_y   <= step_y mod (COORD_MAX + 1);
                    y_phase <= step_p;
                    row     <= step_r mod (COORD_MAX + 1);
                end if;
            end if;

            -- Decisão da linha, um ciclo depois do SAV.
            if line_pend = '1' then
                line_pend <= '0';
                line_ok   <= '0';
                row_base  <= 0;

                if state = ST_RUN and field_wanted = '1' and y_phase = 0 and src_y < src_height and row < fb_height then
                    line_ok  <= '1';
                    row_base <= row * fb_width;
                end if;
            end if;

            -- Posição horizontal e aceitação do pixel.
            if i_pix_valid = '1' then
                accept := line_ok = '1' and x_phase = 0 and src_x < src_width and col < fb_width;
                index  := row_base + col;

                if src_x < src_width then
                    src_x <= src_x + 1;
                end if;

                if x_phase = x_div - 1 then
                    x_phase <= 0;
                    if col < fb_width then
                        col <= col + 1;
                    end if;
                else
                    x_phase <= x_phase + 1;
                end if;

                if accept then
                    o_we    <= '1';
                    o_index <= std_logic_vector(to_unsigned(index mod 2 ** IDX_BITS, IDX_BITS));
                    o_y     <= i_y;
                    o_cb    <= i_cb;
                    o_cr    <= i_cr;
                end if;
            end if;

            -- Controle da captura.
            case state is
                when ST_IDLE =>
                    if i_start = '1' then
                        x_div     <= 1;
                        y_div     <= 1;
                        if unsigned(i_x_div) /= 0 then
                            x_div <= to_integer(unsigned(i_x_div));
                        end if;
                        if unsigned(i_y_div) /= 0 then
                            y_div <= to_integer(unsigned(i_y_div));
                        end if;
                        field_sel <= i_field_sel;
                        format    <= i_format;
                        in_field  <= '0';
                        second    <= '0';
                        ok_reg    <= '0';
                        state     <= ST_ARM;
                    end if;
                when ST_ARM =>
                    if i_present = '0' then
                        state  <= ST_IDLE;
                        o_done <= '1';
                    elsif i_field_start = '1' and field_match = '1' then
                        state    <= ST_RUN;
                        in_field <= '1';
                    end if;
                when ST_RUN =>
                    if i_present = '0' or (i_field_start = '1' and not (second = '1' and i_field = '1')) then
                        state     <= ST_IDLE;
                        o_done    <= '1';
                        line_ok   <= '0';
                        line_pend <= '0';
                    elsif i_field_start = '1' then
                        in_field <= '1';
                    elsif i_field_end = '1' and in_field = '1' then
                        in_field <= '0';
                        if both and second = '0' and i_field = '0' then
                            second <= '1';
                        elsif (both and second = '1' and i_field = '1') or (not both and field_wanted = '1') then
                            state     <= ST_IDLE;
                            o_done    <= '1';
                            ok_reg    <= '1';
                            line_ok   <= '0';
                            line_pend <= '0';
                        else
                            state     <= ST_IDLE;
                            o_done    <= '1';
                            line_ok   <= '0';
                            line_pend <= '0';
                        end if;
                    end if;
            end case;

            if i_rst = '1' then
                state     <= ST_IDLE;
                line_ok   <= '0';
                line_pend <= '0';
                o_we      <= '0';
                o_done    <= '0';
                ok_reg    <= '0';
                src_x     <= 0;
                x_phase   <= 0;
                col       <= 0;
            end if;
        end if;

    end process p_capture;

end architecture rtl;
