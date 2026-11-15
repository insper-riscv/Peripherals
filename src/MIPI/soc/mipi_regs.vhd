-- =============================================================================
-- Registradores do receptor de câmera MIPI (lado do processador)
--
-- Domínio do clock do sistema. Decodifica o barramento de periférico em dez
-- registradores (ver mipi_consts): controle, estado, contador de quadros,
-- configuração, geometria, ponteiro e dado de leitura da memória do quadro,
-- resultado do último quadro, contadores de erro e informação do receptor.
-- A leitura é combinacional no endereço; só o registrador de dado tem efeito
-- colateral, o incremento do ponteiro, e só com i_read em '1'.
--
-- A captura é pedida por um toggle (o_start_tog) e respondida por outro
-- (i_done_tog, já sincronizado em i_clk), o que mantém um pedido em andamento
-- por vez. A configuração só aceita escrita com a captura parada, de modo que
-- o domínio do clock da câmera a lê estável. Os eventos de ECC, de CRC e de
-- descarte chegam como toggles e somam nos contadores de erro, que saturam em
-- 255. Um evento de ECC ou de CRC, ou um quadro que termina incompleto,
-- levanta o erro. A saída o_irq é um nível: quadro pronto ou erro, cada um com
-- a sua máscara. Desabilitar o receptor zera o ocupado e reinicia o domínio
-- do clock da câmera na borda seguinte desse clock.
--
-- A leitura da memória usa um ponteiro de palavra: o_rd_addr é o valor que o
-- ponteiro vai ter no próximo ciclo, de modo que a memória, que registra o
-- endereço, mostra no ciclo seguinte a palavra do ponteiro atual.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.config_pkg.all;
use work.utils_pkg.all;
use work.mipi_consts.all;

entity mipi_regs is
    generic (
        -- Quantidade de lanes de dados do receptor, informada em INFO.
        lanes         : positive range 1 to 4 := 2;
        -- Bytes por linha da memória do quadro.
        fb_line_bytes : positive              := 256;
        -- Linhas da memória do quadro.
        fb_lines      : positive              := 128;
        -- Tipo de dado das linhas guardadas depois do reset.
        default_dt    : natural range 0 to 63 := DT_RAW8
    );
    port (
        -- Clock do sistema.
        i_clk         : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst         : in    std_logic;
        -- Pulso de escrita do processador.
        i_write       : in    std_logic;
        -- Pulso de leitura do processador.
        i_read        : in    std_logic;
        -- Endereço de palavra dentro do periférico.
        i_address     : in    std_logic_vector(MIPI_ADDR_WIDTH - 1 downto 0);
        -- Dado de escrita vindo do processador.
        i_data_in     : in    word_t;
        -- Dado de leitura para o processador.
        o_data_out    : out   word_t;
        -- Requisição de interrupção, ativa em '1'.
        o_irq         : out   std_logic;
        -- Cabeçalho válido visto desde a habilitação, já sincronizado em i_clk.
        i_seen        : in    std_logic;
        -- Toggle de fim de captura, já sincronizado em i_clk.
        i_done_tog    : in    std_logic;
        -- Resultado da captura ('1' quadro completo), estável quando o toggle de fim chega.
        i_cap_ok      : in    std_logic;
        -- Linhas guardadas, estável quando o toggle de fim chega.
        i_cap_lines   : in    std_logic_vector(15 downto 0);
        -- Contagem de palavras da última linha, estável quando o toggle de fim chega.
        i_cap_wc      : in    std_logic_vector(15 downto 0);
        -- Toggle de erro de ECC, já sincronizado em i_clk.
        i_ecc_tog     : in    std_logic;
        -- Toggle de erro de CRC, já sincronizado em i_clk.
        i_crc_tog     : in    std_logic;
        -- Toggle de descarte, já sincronizado em i_clk.
        i_drop_tog    : in    std_logic;
        -- Toggle de pedido de captura, a sincronizar no domínio do clock da câmera.
        o_start_tog   : out   std_logic;
        -- Tipo de dado das linhas guardadas.
        o_dt          : out   std_logic_vector(5 downto 0);
        -- Passo de linhas.
        o_y_step      : out   std_logic_vector(7 downto 0);
        -- Receptor habilitado, a sincronizar no domínio do clock da câmera.
        o_enable      : out   std_logic;
        -- Endereço de palavra da leitura da memória do quadro, adiantado de um ciclo.
        o_rd_addr     : out   std_logic_vector(log2_ceil(frame_words(fb_line_bytes, fb_lines)) - 1 downto 0);
        -- Palavra lida da memória do quadro, registrada.
        i_rd_data     : in    std_logic_vector(31 downto 0)
    );
end entity mipi_regs;

architecture rtl of mipi_regs is

    -- Palavras da memória do quadro.
    constant DEPTH     : positive := frame_words(fb_line_bytes, fb_lines);
    -- Largura do endereço de palavra da memória do quadro.
    constant ADDR_BITS : positive := log2_ceil(DEPTH);

    -- Toggle de pedido de captura.
    signal start_tog   : std_logic                          := '0';
    -- Último valor visto do toggle de fim de captura.
    signal done_seen   : std_logic                          := '0';
    -- Último valor visto do toggle de erro de ECC.
    signal ecc_seen    : std_logic                          := '0';
    -- Último valor visto do toggle de erro de CRC.
    signal crc_seen    : std_logic                          := '0';
    -- Último valor visto do toggle de descarte.
    signal drop_seen   : std_logic                          := '0';
    -- Captura em andamento.
    signal busy        : std_logic                          := '0';
    -- Quadro pronto.
    signal frame_ready : std_logic                          := '0';
    -- Erro de ECC, de CRC ou quadro incompleto.
    signal error_flag  : std_logic                          := '0';
    -- Receptor habilitado.
    signal enable      : std_logic                          := '0';
    -- Máscara da interrupção de quadro pronto.
    signal frame_irq   : std_logic                          := '0';
    -- Máscara da interrupção de erro.
    signal error_irq   : std_logic                          := '0';
    -- Contador de quadros capturados.
    signal frame_count : unsigned(31 downto 0)              := (others => '0');
    -- Tipo de dado das linhas guardadas.
    signal data_type   : std_logic_vector(5 downto 0)       := std_logic_vector(to_unsigned(default_dt, 6));
    -- Passo de linhas.
    signal y_step      : std_logic_vector(7 downto 0)       := x"01";
    -- Linhas guardadas no último quadro.
    signal last_lines  : std_logic_vector(15 downto 0)      := (others => '0');
    -- Contagem de palavras da última linha do último quadro.
    signal last_wc     : std_logic_vector(15 downto 0)      := (others => '0');
    -- Contador de erros de ECC.
    signal ecc_count   : unsigned(7 downto 0)               := (others => '0');
    -- Contador de erros de CRC.
    signal crc_count   : unsigned(7 downto 0)               := (others => '0');
    -- Contador de descartes.
    signal drop_count  : unsigned(7 downto 0)               := (others => '0');
    -- Ponteiro de leitura da memória do quadro.
    signal rd_ptr      : unsigned(ADDR_BITS - 1 downto 0)   := (others => '0');
    -- Valor do ponteiro no próximo ciclo.
    signal rd_next     : unsigned(ADDR_BITS - 1 downto 0);

    -- Fim de captura visto neste ciclo.
    signal done_event  : std_logic;
    -- Erro de ECC visto neste ciclo.
    signal ecc_event   : std_logic;
    -- Erro de CRC visto neste ciclo.
    signal crc_event   : std_logic;
    -- Descarte visto neste ciclo.
    signal drop_event  : std_logic;
    -- Endereço de palavra do acesso.
    signal addr_idx    : natural range 0 to 2 ** MIPI_ADDR_WIDTH - 1;
    -- Leitura do dado da memória do quadro.
    signal rd_data_hit : std_logic;
    -- Escrita no ponteiro de leitura.
    signal rd_addr_wr  : std_logic;

begin

    addr_idx    <= to_integer(unsigned(i_address));
    done_event  <= busy and (i_done_tog xor done_seen);
    ecc_event   <= i_ecc_tog xor ecc_seen;
    crc_event   <= i_crc_tog xor crc_seen;
    drop_event  <= i_drop_tog xor drop_seen;
    rd_data_hit <= i_read when addr_idx = ADDR_RD_DATA else
                   '0';
    rd_addr_wr  <= i_write when addr_idx = ADDR_RD_ADDR else
                   '0';

    -- Próximo valor do ponteiro: escrita válida carrega, leitura do dado avança com volta ao início.
    p_pointer : process (all) is
    begin

        rd_next <= rd_ptr;

        if rd_addr_wr = '1' and unsigned(i_data_in) < DEPTH then
            rd_next <= resize(unsigned(i_data_in), ADDR_BITS);
        elsif rd_data_hit = '1' then
            if rd_ptr = DEPTH - 1 then
                rd_next <= (others => '0');
            else
                rd_next <= rd_ptr + 1;
            end if;
        end if;

    end process p_pointer;

    o_rd_addr   <= std_logic_vector(rd_next);
    o_start_tog <= start_tog;
    o_dt        <= data_type;
    o_y_step    <= y_step;
    o_enable    <= enable;
    o_irq       <= (frame_irq and frame_ready) or (error_irq and error_flag);

    -- Leitura combinacional dos registradores.
    p_read : process (all) is
    begin

        o_data_out <= (others => '0');

        case addr_idx is
            when ADDR_CTRL =>
                o_data_out(CTRL_FRAME_IRQ) <= frame_irq;
                o_data_out(CTRL_ERROR_IRQ) <= error_irq;
                o_data_out(CTRL_ENABLE)    <= enable;
            when ADDR_STATUS =>
                o_data_out(STATUS_BUSY_BIT)  <= busy;
                o_data_out(STATUS_READY_BIT) <= frame_ready;
                o_data_out(STATUS_ERROR_BIT) <= error_flag;
                o_data_out(STATUS_SEEN_BIT)  <= i_seen;
            when ADDR_FRAME_COUNT =>
                o_data_out(31 downto 0) <= std_logic_vector(frame_count);
            when ADDR_CONFIG =>
                o_data_out(5 downto 0)  <= data_type;
                o_data_out(15 downto 8) <= y_step;
            when ADDR_GEOMETRY =>
                o_data_out(31 downto 0) <= std_logic_vector(to_unsigned(fb_lines, 16)) &
                                           std_logic_vector(to_unsigned(fb_line_bytes, 16));
            when ADDR_RD_ADDR =>
                o_data_out(ADDR_BITS - 1 downto 0) <= std_logic_vector(rd_ptr);
            when ADDR_RD_DATA =>
                o_data_out(31 downto 0) <= i_rd_data;
            when ADDR_LAST_FRAME =>
                o_data_out(31 downto 0) <= last_wc & last_lines;
            when ADDR_ERRORS =>
                o_data_out(23 downto 0) <= std_logic_vector(drop_count) & std_logic_vector(crc_count) &
                                           std_logic_vector(ecc_count);
            when ADDR_INFO =>
                o_data_out(3 downto 0) <= std_logic_vector(to_unsigned(lanes, 4));
            when others =>
                null;
        end case;

    end process p_read;

    p_write : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            rd_ptr    <= rd_next;
            done_seen <= i_done_tog;
            ecc_seen  <= i_ecc_tog;
            crc_seen  <= i_crc_tog;
            drop_seen <= i_drop_tog;

            if ecc_event = '1' then
                error_flag <= '1';

                if ecc_count /= 255 then
                    ecc_count <= ecc_count + 1;
                end if;
            end if;

            if crc_event = '1' then
                error_flag <= '1';

                if crc_count /= 255 then
                    crc_count <= crc_count + 1;
                end if;
            end if;

            if drop_event = '1' and drop_count /= 255 then
                drop_count <= drop_count + 1;
            end if;

            if done_event = '1' then
                busy        <= '0';
                frame_ready <= i_cap_ok;
                last_lines  <= i_cap_lines;
                last_wc     <= i_cap_wc;

                if i_cap_ok = '1' then
                    frame_count <= frame_count + 1;
                else
                    error_flag <= '1';
                end if;
            end if;

            if i_write = '1' then
                case addr_idx is
                    when ADDR_CTRL =>
                        frame_irq <= i_data_in(CTRL_FRAME_IRQ);
                        error_irq <= i_data_in(CTRL_ERROR_IRQ);
                        enable    <= i_data_in(CTRL_ENABLE);

                        if i_data_in(CTRL_ENABLE) = '0' then
                            busy <= '0';
                        elsif i_data_in(CTRL_START_BIT) = '1' and busy = '0' and enable = '1' then
                            start_tog   <= not start_tog;
                            busy        <= '1';
                            frame_ready <= '0';
                        end if;
                    when ADDR_STATUS =>
                        if i_data_in(STATUS_READY_BIT) = '1' and done_event = '0' then
                            frame_ready <= '0';
                        end if;

                        if i_data_in(STATUS_ERROR_BIT) = '1' and ecc_event = '0' and crc_event = '0' and
                           done_event = '0' then
                            error_flag <= '0';
                        end if;
                    when ADDR_CONFIG =>
                        if busy = '0' then
                            data_type <= i_data_in(5 downto 0);
                            y_step    <= i_data_in(15 downto 8);

                            if unsigned(i_data_in(15 downto 8)) = 0 then
                                y_step <= x"01";
                            end if;
                        end if;
                    when ADDR_ERRORS =>
                        if ecc_event = '0' then
                            ecc_count <= (others => '0');
                        end if;

                        if crc_event = '0' then
                            crc_count <= (others => '0');
                        end if;

                        if drop_event = '0' then
                            drop_count <= (others => '0');
                        end if;
                    when others =>
                        null;
                end case;
            end if;

            if i_rst = '1' then
                busy        <= '0';
                frame_ready <= '0';
                error_flag  <= '0';
                enable      <= '0';
                frame_irq   <= '0';
                error_irq   <= '0';
                frame_count <= (others => '0');
                data_type   <= std_logic_vector(to_unsigned(default_dt, 6));
                y_step      <= x"01";
                last_lines  <= (others => '0');
                last_wc     <= (others => '0');
                ecc_count   <= (others => '0');
                crc_count   <= (others => '0');
                drop_count  <= (others => '0');
                rd_ptr      <= (others => '0');
            end if;
        end if;

    end process p_write;

end architecture rtl;
