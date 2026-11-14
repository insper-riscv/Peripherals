-- =============================================================================
-- Registradores do periférico de captura de TV (lado do processador)
--
-- Domínio do clock do sistema. Decodifica o barramento de periférico em nove
-- registradores (ver tv_consts): controle, estado, contador de quadros,
-- decimação, formato, geometria, ponteiro e dado de leitura da memória do
-- quadro e área de origem. A leitura é combinacional no endereço; só o
-- registrador de dado tem efeito colateral, o incremento do ponteiro, e só
-- com i_read em '1'.
--
-- A captura é pedida por um toggle (o_start_tog) e respondida por outro
-- (i_done_tog, já sincronizado em i_clk), o que mantém um pedido em
-- andamento por vez; o bit de ocupado vale de um pedido aceito até a resposta.
-- A configuração de decimação, formato e campo só aceita escrita com a captura
-- parada, de modo que o domínio do decodificador a lê estável. Um evento
-- de fim de captura soma ao contador de quadros e levanta o quadro pronto se o
-- quadro veio completo; uma captura abortada levanta o erro de sincronismo.
-- Eventos de erro do receptor chegam como toggle (i_err_tog) e também
-- levantam o erro de sincronismo. A saída o_irq é um nível: quadro pronto ou
-- erro de sincronismo, cada um com a sua máscara.
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
use work.tv_consts.all;

entity tv_regs is
    generic (
        -- Largura da memória do quadro em pixels.
        fb_width   : positive := 160;
        -- Altura da memória do quadro em pixels.
        fb_height  : positive := 120;
        -- Largura em pixels da área de origem capturada.
        src_width  : positive := 720;
        -- Altura em linhas da área de origem capturada.
        src_height : positive := 480
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
        i_address     : in    std_logic_vector(TV_ADDR_WIDTH - 1 downto 0);
        -- Dado de escrita vindo do processador.
        i_data_in     : in    word_t;
        -- Dado de leitura para o processador.
        o_data_out    : out   word_t;
        -- Requisição de interrupção, ativa em '1'.
        o_irq         : out   std_logic;
        -- Vídeo presente, já sincronizado em i_clk.
        i_present     : in    std_logic;
        -- Toggle de fim de captura, já sincronizado em i_clk.
        i_done_tog    : in    std_logic;
        -- Resultado da captura ('1' quadro completo), estável quando o toggle de fim chega.
        i_cap_ok      : in    std_logic;
        -- Toggle de erro do receptor, já sincronizado em i_clk.
        i_err_tog     : in    std_logic;
        -- Toggle de pedido de captura, a sincronizar no domínio do decodificador.
        o_start_tog   : out   std_logic;
        -- Fator de decimação em x.
        o_x_div       : out   std_logic_vector(7 downto 0);
        -- Fator de decimação em y.
        o_y_div       : out   std_logic_vector(7 downto 0);
        -- Seletor de campo.
        o_field_sel   : out   std_logic_vector(1 downto 0);
        -- Formato do pixel.
        o_format      : out   std_logic;
        -- Reset do decodificador liberado (TD_RESET_N).
        o_decoder_run : out   std_logic;
        -- Endereço de palavra da leitura da memória do quadro, adiantado de um ciclo.
        o_rd_addr     : out   std_logic_vector(log2_ceil(frame_words(fb_width, fb_height)) - 1 downto 0);
        -- Palavra lida da memória do quadro, registrada.
        i_rd_data     : in    std_logic_vector(31 downto 0)
    );
end entity tv_regs;

architecture rtl of tv_regs is

    -- Palavras da memória do quadro.
    constant DEPTH     : positive := frame_words(fb_width, fb_height);
    -- Largura do endereço de palavra da memória do quadro.
    constant ADDR_BITS : positive := log2_ceil(DEPTH);

    -- Toggle de pedido de captura.
    signal start_tog   : std_logic := '0';
    -- Último valor visto do toggle de fim de captura.
    signal done_seen   : std_logic := '0';
    -- Último valor visto do toggle de erro do receptor.
    signal err_seen    : std_logic := '0';
    -- Captura em andamento.
    signal busy        : std_logic := '0';
    -- Quadro pronto.
    signal frame_ready : std_logic := '0';
    -- Erro de sincronismo.
    signal sync_error  : std_logic := '0';
    -- Contador de quadros capturados.
    signal frame_count : unsigned(31 downto 0) := (others => '0');
    -- Máscara da interrupção de quadro pronto.
    signal frame_irq   : std_logic := '0';
    -- Máscara da interrupção de erro de sincronismo.
    signal error_irq   : std_logic := '0';
    -- Reset do decodificador liberado.
    signal decoder_run : std_logic := '0';
    -- Fator de decimação em x.
    signal x_div       : std_logic_vector(7 downto 0) := x"01";
    -- Fator de decimação em y.
    signal y_div       : std_logic_vector(7 downto 0) := x"01";
    -- Formato do pixel.
    signal format      : std_logic := FORMAT_RGB565;
    -- Seletor de campo.
    signal field_sel   : std_logic_vector(1 downto 0) := FIELD_BOTH;
    -- Ponteiro de leitura da memória do quadro.
    signal rd_ptr      : unsigned(ADDR_BITS - 1 downto 0) := (others => '0');
    -- Valor do ponteiro no próximo ciclo.
    signal rd_next     : unsigned(ADDR_BITS - 1 downto 0);

    -- Fim de captura visto neste ciclo.
    signal done_event  : std_logic;
    -- Erro do receptor visto neste ciclo.
    signal err_event   : std_logic;
    -- Endereço de palavra do acesso.
    signal addr_idx    : natural range 0 to 2 ** TV_ADDR_WIDTH - 1;
    -- Escrita de um endereço dado.
    signal rd_data_hit : std_logic;
    -- Escrita no ponteiro de leitura.
    signal rd_addr_wr  : std_logic;

begin

    addr_idx    <= to_integer(unsigned(i_address));
    done_event  <= busy and (i_done_tog xor done_seen);
    err_event   <= i_err_tog xor err_seen;
    rd_data_hit <= i_read when addr_idx = ADDR_RD_DATA else '0';
    rd_addr_wr  <= i_write when addr_idx = ADDR_RD_ADDR else '0';

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

    o_rd_addr     <= std_logic_vector(rd_next);
    o_start_tog   <= start_tog;
    o_x_div       <= x_div;
    o_y_div       <= y_div;
    o_field_sel   <= field_sel;
    o_format      <= format;
    o_decoder_run <= decoder_run;
    o_irq         <= (frame_irq and frame_ready) or (error_irq and sync_error);

    -- Leitura combinacional dos registradores.
    p_read : process (all) is
    begin

        o_data_out <= (others => '0');

        case addr_idx is
            when ADDR_CTRL =>
                o_data_out(CTRL_FRAME_IRQ)   <= frame_irq;
                o_data_out(CTRL_ERROR_IRQ)   <= error_irq;
                o_data_out(CTRL_DECODER_RUN) <= decoder_run;
            when ADDR_STATUS =>
                o_data_out(STATUS_BUSY_BIT)    <= busy;
                o_data_out(STATUS_READY_BIT)   <= frame_ready;
                o_data_out(STATUS_ERROR_BIT)   <= sync_error;
                o_data_out(STATUS_PRESENT_BIT) <= i_present;
            when ADDR_FRAME_COUNT =>
                o_data_out(31 downto 0) <= std_logic_vector(frame_count);
            when ADDR_DECIMATION =>
                o_data_out(15 downto 0) <= y_div & x_div;
            when ADDR_FORMAT =>
                o_data_out(0)          <= format;
                o_data_out(2 downto 1) <= field_sel;
            when ADDR_GEOMETRY =>
                o_data_out(31 downto 0) <= std_logic_vector(to_unsigned(fb_height, 16)) &
                                           std_logic_vector(to_unsigned(fb_width, 16));
            when ADDR_RD_ADDR =>
                o_data_out(ADDR_BITS - 1 downto 0) <= std_logic_vector(rd_ptr);
            when ADDR_RD_DATA =>
                o_data_out(31 downto 0) <= i_rd_data;
            when ADDR_SOURCE =>
                o_data_out(31 downto 0) <= std_logic_vector(to_unsigned(src_height, 16)) &
                                           std_logic_vector(to_unsigned(src_width, 16));
            when others =>
                null;
        end case;

    end process p_read;

    p_write : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            rd_ptr    <= rd_next;
            done_seen <= i_done_tog;
            err_seen  <= i_err_tog;

            if err_event = '1' then
                sync_error <= '1';
            end if;

            if done_event = '1' then
                busy        <= '0';
                frame_ready <= i_cap_ok;
                sync_error  <= sync_error or not i_cap_ok or err_event;

                if i_cap_ok = '1' then
                    frame_count <= frame_count + 1;
                end if;
            end if;

            if i_write = '1' then
                case addr_idx is
                    when ADDR_CTRL =>
                        frame_irq   <= i_data_in(CTRL_FRAME_IRQ);
                        error_irq   <= i_data_in(CTRL_ERROR_IRQ);
                        decoder_run <= i_data_in(CTRL_DECODER_RUN);

                        if i_data_in(CTRL_START_BIT) = '1' and busy = '0' then
                            start_tog   <= not start_tog;
                            busy        <= '1';
                            frame_ready <= '0';
                        end if;
                    when ADDR_STATUS =>
                        if i_data_in(STATUS_READY_BIT) = '1' and done_event = '0' then
                            frame_ready <= '0';
                        end if;

                        if i_data_in(STATUS_ERROR_BIT) = '1' and err_event = '0' and done_event = '0' then
                            sync_error <= '0';
                        end if;
                    when ADDR_DECIMATION =>
                        if busy = '0' then
                            x_div <= i_data_in(7 downto 0);
                            y_div <= i_data_in(15 downto 8);

                            if unsigned(i_data_in(7 downto 0)) = 0 then
                                x_div <= x"01";
                            end if;

                            if unsigned(i_data_in(15 downto 8)) = 0 then
                                y_div <= x"01";
                            end if;
                        end if;
                    when ADDR_FORMAT =>
                        if busy = '0' then
                            format    <= i_data_in(0);
                            field_sel <= i_data_in(2 downto 1);
                        end if;
                    when others =>
                        null;
                end case;
            end if;

            if i_rst = '1' then
                busy        <= '0';
                frame_ready <= '0';
                sync_error  <= '0';
                frame_count <= (others => '0');
                frame_irq   <= '0';
                error_irq   <= '0';
                decoder_run <= '0';
                x_div       <= x"01";
                y_div       <= x"01";
                format      <= FORMAT_RGB565;
                field_sel   <= FIELD_BOTH;
                rd_ptr      <= (others => '0');
            end if;
        end if;

    end process p_write;

end architecture rtl;
