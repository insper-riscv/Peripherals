-- =============================================================================
-- Controle da captura de um quadro de câmera MIPI CSI-2
--
-- Depois de um pedido de início, espera o pacote curto de início de quadro,
-- guarda na memória do quadro as linhas dos pacotes longos cujo tipo de dado
-- é o escolhido e termina no pacote curto de fim de quadro. Um início de
-- quadro no meio da captura aborta o quadro (resultado incompleto).
--
-- A memória do quadro tem fb_lines linhas de fb_line_bytes bytes, quatro bytes
-- por palavra. Os bytes de uma linha além de fb_line_bytes e as linhas além de
-- fb_lines são descartados (recorte do canto superior esquerdo do quadro), e o
-- passo de linhas guarda uma linha de cada y_step, contado sobre as linhas
-- do tipo de dado escolhido. Cada linha ou quadro descartado sai como evento
-- de descarte, e cada pacote de linha com CRC errado, como evento de CRC.
--
-- Os valores de configuração (tipo de dado e passo) devem ficar parados
-- durante a captura. O resultado (linhas guardadas, contagem de palavras da
-- última linha e se o quadro veio completo) fica parado depois do pulso de
-- fim, até o fim da captura seguinte.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.mipi_consts.all;
use work.utils_pkg.all;

entity mipi_capture is
    generic (
        -- Quantidade de lanes, largura em bytes de cada grupo de carga útil.
        lanes         : positive range 1 to 4 := 2;
        -- Bytes por linha da memória do quadro, múltiplo de quatro.
        fb_line_bytes : positive              := 256;
        -- Linhas da memória do quadro.
        fb_lines      : positive              := 128
    );
    port (
        -- Clock do receptor.
        i_clk       : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst       : in    std_logic;
        -- Pulso de pedido de captura.
        i_start     : in    std_logic;
        -- Tipo de dado das linhas guardadas.
        i_dt        : in    std_logic_vector(5 downto 0);
        -- Passo de linhas, uma de cada i_y_step (zero vale um).
        i_y_step    : in    std_logic_vector(7 downto 0);
        -- Cabeçalho com ECC correto.
        i_hdr_valid : in    std_logic;
        -- O pacote do cabeçalho é longo.
        i_hdr_long  : in    std_logic;
        -- Tipo de dado do cabeçalho.
        i_hdr_dt    : in    std_logic_vector(5 downto 0);
        -- Contagem de palavras do cabeçalho.
        i_hdr_wc    : in    std_logic_vector(15 downto 0);
        -- Grupo de bytes de carga útil.
        i_pix_valid : in    std_logic;
        -- Bytes do grupo.
        i_pix_data  : in    std_logic_vector(lanes * 8 - 1 downto 0);
        -- Bytes do grupo que fazem parte da carga útil.
        i_pix_mask  : in    std_logic_vector(lanes - 1 downto 0);
        -- Fim de um pacote.
        i_pkt_end   : in    std_logic;
        -- CRC do pacote correto.
        i_crc_ok    : in    std_logic;
        -- Captura em andamento (esperando o início de quadro ou guardando linhas).
        o_busy      : out   std_logic;
        -- Pulso de fim de captura.
        o_done      : out   std_logic;
        -- Resultado da captura ('1' quadro completo com ao menos uma linha), parado depois de o_done.
        o_ok        : out   std_logic;
        -- Linhas guardadas no quadro, parado depois de o_done.
        o_lines     : out   std_logic_vector(15 downto 0);
        -- Contagem de palavras da última linha do tipo escolhido, parada depois de o_done.
        o_last_wc   : out   std_logic_vector(15 downto 0);
        -- Pulso de pacote de linha com CRC errado.
        o_ev_crc    : out   std_logic;
        -- Pulso de linha ou bytes descartados.
        o_ev_drop   : out   std_logic;
        -- Habilitação de escrita de cada byte da palavra da memória.
        o_we        : out   std_logic_vector(3 downto 0);
        -- Endereço de palavra da escrita.
        o_waddr     : out   std_logic_vector(log2_ceil(frame_words(fb_line_bytes, fb_lines)) - 1 downto 0);
        -- Palavra de escrita.
        o_wdata     : out   std_logic_vector(31 downto 0)
    );
end entity mipi_capture;

architecture rtl of mipi_capture is

    -- Fases da captura.
    type state_t is (st_idle, st_armed, st_capture);

    -- Palavras de cada linha da memória do quadro.
    constant LINE_WORDS : positive := fb_line_bytes / 4;
    -- Maior posição de byte dentro de uma linha recebida, mais a largura de um grupo.
    constant MAX_X      : positive := 65535 + 4;

    -- Fase atual.
    signal state      : state_t                                    := st_idle;
    -- Linhas já guardadas no quadro.
    signal line_cnt   : natural range 0 to fb_lines                := 0;
    -- Endereço de palavra do começo da linha em curso.
    signal row_base   : natural range 0 to LINE_WORDS * fb_lines   := 0;
    -- Posição, em bytes, do próximo grupo dentro da linha em curso.
    signal x_pos      : natural range 0 to MAX_X                   := 0;
    -- Linhas do tipo escolhido vistas desde a última guardada, de 0 ao passo menos um.
    signal y_phase    : natural range 0 to 255                     := 0;
    -- O pacote em curso é uma linha do tipo escolhido.
    signal line_match : std_logic                                  := '0';
    -- A linha em curso é guardada na memória.
    signal line_store : std_logic                                  := '0';
    -- Algum byte da linha em curso foi descartado.
    signal dropped    : std_logic                                  := '0';
    -- Contagem de palavras da última linha do tipo escolhido.
    signal wc_last    : std_logic_vector(15 downto 0)              := (others => '0');
    -- Passo de linhas, de 0 a 255 (zero vale como um, porque a fase volta a zero a cada linha).
    signal step       : natural range 0 to 255;

begin

    step   <= to_integer(unsigned(i_y_step));
    o_busy <= '0' when state = st_idle else
              '1';

    p_capture : process (i_clk) is

        -- Posição do byte na palavra da memória.
        variable slot : natural range 0 to 7;

    begin

        if rising_edge(i_clk) then
            o_done    <= '0';
            o_ev_crc  <= '0';
            o_ev_drop <= '0';
            o_we      <= (others => '0');
            o_wdata   <= (others => '0');

            if state = st_idle and i_start = '1' then
                state <= st_armed;
            end if;

            if i_hdr_valid = '1' then
                if state = st_armed and i_hdr_long = '0' and i_hdr_dt = DT_FRAME_START then
                    state      <= st_capture;
                    line_cnt   <= 0;
                    row_base   <= 0;
                    y_phase    <= 0;
                    line_match <= '0';
                elsif state = st_capture then
                    if i_hdr_long = '0' and (i_hdr_dt = DT_FRAME_START or i_hdr_dt = DT_FRAME_END) then
                        state     <= st_idle;
                        o_done    <= '1';
                        o_ok      <= to_sl(i_hdr_dt = DT_FRAME_END and line_cnt > 0);
                        o_lines   <= std_logic_vector(to_unsigned(line_cnt, 16));
                        o_last_wc <= wc_last;
                    elsif i_hdr_long = '1' and i_hdr_dt = i_dt then
                        line_match <= '1';
                        x_pos      <= 0;
                        dropped    <= '0';
                        wc_last    <= i_hdr_wc;

                        if y_phase = 0 and line_cnt < fb_lines then
                            line_store <= '1';
                        else
                            line_store <= '0';

                            if y_phase = 0 then
                                o_ev_drop <= '1';
                            end if;
                        end if;
                    end if;
                end if;
            end if;

            if i_pix_valid = '1' and line_match = '1' then
                x_pos <= x_pos + lanes;

                if line_store = '1' then
                    if x_pos < fb_line_bytes then
                        o_waddr <= std_logic_vector(to_unsigned(row_base + x_pos / 4, o_waddr'length));

                        for lane in 0 to lanes - 1 loop

                            slot := x_pos mod 4 + lane;

                            if i_pix_mask(lane) = '1' then
                                o_we(slot)                            <= '1';
                                o_wdata(slot * 8 + 7 downto slot * 8) <= i_pix_data(lane * 8 + 7 downto lane * 8);
                            end if;

                        end loop;
                    else
                        dropped <= '1';
                    end if;
                end if;
            end if;

            if i_pkt_end = '1' and line_match = '1' then
                line_match <= '0';

                if i_crc_ok = '0' then
                    o_ev_crc <= '1';
                end if;

                if line_store = '1' then
                    line_cnt <= line_cnt + 1;
                    row_base <= row_base + LINE_WORDS;

                    if dropped = '1' then
                        o_ev_drop <= '1';
                    end if;
                end if;

                if y_phase + 1 >= step then
                    y_phase <= 0;
                else
                    y_phase <= y_phase + 1;
                end if;
            end if;

            if i_rst = '1' then
                state      <= st_idle;
                line_match <= '0';
                o_ok       <= '0';
                o_lines    <= (others => '0');
                o_last_wc  <= (others => '0');
                o_waddr    <= (others => '0');
            end if;
        end if;

    end process p_capture;

end architecture rtl;
