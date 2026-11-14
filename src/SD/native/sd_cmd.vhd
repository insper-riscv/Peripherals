-- ==========================================================================
-- Controle de comando do cartão SD no modo nativo
-- ==========================================================================
-- Envia um comando de 48 bits pela linha CMD (início 0, transmissão 1, índice
-- de 6 bits, argumento de 32 bits, CRC7 e fim 1), recebe a resposta e confere
-- o que o formato define. Os bits do comando saem na borda de descida de
-- SD_CLK e os da resposta são amostrados na borda de subida.
--
-- Respostas (i_response):
--   RSP_NONE         nenhuma; depois do comando só vêm os clocks de intervalo.
--   RSP_SHORT        48 bits (R1, R1b, R6, R7): CRC7 sobre os 40 primeiros bits,
--                    índice igual ao do comando e bit de fim em 1.
--   RSP_SHORT_NO_CRC 48 bits (R3): só o bit de fim, pois o CRC7 e o índice não
--                    têm valor definido.
--   RSP_LONG         136 bits (R2): CRC7 sobre os 120 bits de CID ou CSD.
-- o_response guarda o corpo da resposta, com o bit 31 a 0 do argumento (curta)
-- ou os bits 127 a 8 do CID ou CSD (longa) nas quatro palavras de 32 bits, e o
-- índice da resposta curta nos bits 37 a 32.
--
-- Depois da resposta (ou do comando, sem resposta) passam gap_clocks clocks;
-- com i_wait_busy o controle ainda espera DAT0 voltar a 1 (R1b) por no máximo
-- i_timeout clocks. o_done dura um ciclo no fim, junto com o_busy em zero, e
-- os erros valem de o_done até o próximo i_start. o_resp_ok dura um ciclo no
-- bit de fim de uma resposta sem erro.
-- ==========================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.sd_native_pkg.all;

entity sd_cmd is
    generic (
        -- Máximo de clocks entre o fim do comando e o bit de início da resposta (NCR).
        ncr_clocks : positive := NCR_CLOCKS;
        -- Clocks que seguem o fim do comando antes do próximo (NCC).
        gap_clocks : positive := GAP_CLOCKS
    );
    port (
        -- Clock do módulo.
        i_clk         : in    std_logic;
        -- Reset síncrono, ativo em nível alto.
        i_rst         : in    std_logic;
        -- Interrompe o comando em andamento sem sinalizar fim nem erro.
        i_abort       : in    std_logic;
        -- Pedido de início, aceito apenas com o_busy em zero.
        i_start       : in    std_logic;
        -- Índice do comando.
        i_index       : in    std_logic_vector(5 downto 0);
        -- Argumento do comando.
        i_argument    : in    std_logic_vector(31 downto 0);
        -- Formato da resposta esperada (RSP_NONE, RSP_SHORT, RSP_SHORT_NO_CRC ou RSP_LONG).
        i_response    : in    std_logic_vector(1 downto 0);
        -- Espera DAT0 voltar a 1 depois da resposta (R1b).
        i_wait_busy   : in    std_logic;
        -- Limite da espera por DAT0, em clocks do cartão.
        i_timeout     : in    std_logic_vector(TIMEOUT_WIDTH - 1 downto 0);
        -- Pulso que antecede a borda de subida de SD_CLK.
        i_rise        : in    std_logic;
        -- Pulso que antecede a borda de descida de SD_CLK.
        i_fall        : in    std_logic;
        -- Linha CMD vista pelo mestre, já registrada.
        i_cmd         : in    std_logic;
        -- Linha DAT0 vista pelo mestre, já registrada.
        i_dat0        : in    std_logic;
        -- Valor que o mestre aplica à linha CMD.
        o_cmd         : out   std_logic;
        -- Habilitação da saída da linha CMD.
        o_cmd_oe      : out   std_logic;
        -- Indica comando em andamento, que pede o clock do cartão.
        o_busy        : out   std_logic;
        -- Pulso de um ciclo ao fim do comando, com ou sem erro.
        o_done        : out   std_logic;
        -- Pulso de um ciclo no bit de fim de uma resposta sem erro.
        o_resp_ok     : out   std_logic;
        -- Corpo da resposta (120 bits úteis), válido a partir de o_done.
        o_response    : out   std_logic_vector(127 downto 0);
        -- Resposta não chegou no prazo, ou DAT0 ficou ocupado além do prazo.
        o_err_timeout : out   std_logic;
        -- CRC7 da resposta não confere.
        o_err_crc     : out   std_logic;
        -- Índice da resposta diferente do índice do comando.
        o_err_index   : out   std_logic;
        -- Bit de transmissão ou bit de fim da resposta com valor errado.
        o_err_frame   : out   std_logic
    );
end entity sd_cmd;

architecture rtl of sd_cmd is

    -- Estados do controle de comando.
    type state_t is (S_IDLE, S_SEND, S_SEND_END, S_WAIT_RSP, S_RECV, S_GAP, S_BUSY);

    -- Estado atual.
    signal state      : state_t;
    -- Quadro a enviar: início, transmissão, índice e argumento, bit 39 primeiro.
    signal frame      : std_logic_vector(CMD_HEADER_BITS - 1 downto 0);
    -- Posição do bit em andamento no comando ou na resposta.
    signal bit_cnt    : unsigned(7 downto 0);
    -- Clocks já contados na espera atual.
    signal wait_cnt   : unsigned(TIMEOUT_WIDTH - 1 downto 0);
    -- Corpo da resposta, deslocado a cada bit.
    signal rsp_shift  : std_logic_vector(119 downto 0);
    -- CRC7 recebido, deslocado a cada bit.
    signal rx_crc     : std_logic_vector(6 downto 0);
    -- Índice do comando em andamento.
    signal index_r    : std_logic_vector(5 downto 0);
    -- Formato da resposta do comando em andamento.
    signal response_r : std_logic_vector(1 downto 0);
    -- Espera por ocupado do comando em andamento.
    signal busy_r     : std_logic;
    -- Pulso de fim de comando.
    signal done       : std_logic;
    -- Pulso de resposta válida.
    signal resp_ok    : std_logic;
    -- Erro de prazo do comando em andamento.
    signal err_timeout : std_logic;
    -- Erro de CRC7 do comando em andamento.
    signal err_crc    : std_logic;
    -- Erro de índice do comando em andamento.
    signal err_index  : std_logic;
    -- Erro de formato do comando em andamento.
    signal err_frame  : std_logic;
    -- Valor aplicado à linha CMD.
    signal cmd_out    : std_logic;
    -- Habilitação da saída da linha CMD.
    signal cmd_oe     : std_logic;

    -- Zera o CRC7.
    signal crc_clear  : std_logic;
    -- Incorpora um bit ao CRC7.
    signal crc_enable : std_logic;
    -- Bit incorporado ao CRC7.
    signal crc_bit    : std_logic;
    -- CRC7 calculado.
    signal crc_value  : std_logic_vector(6 downto 0);

    -- Indica a resposta longa.
    signal is_long    : std_logic;

begin

    o_cmd         <= cmd_out;
    o_cmd_oe      <= cmd_oe;
    o_busy        <= '0' when state = S_IDLE else '1';
    o_done        <= done;
    o_resp_ok     <= resp_ok;
    o_response    <= x"00" & rsp_shift;
    o_err_timeout <= err_timeout;
    o_err_crc     <= err_crc;
    o_err_index   <= err_index;
    o_err_frame   <= err_frame;

    is_long <= '1' when response_r = RSP_LONG else '0';

    -- O CRC7 fica zerado em repouso e entre o fim do comando e a resposta.
    crc_clear <= '1' when state = S_IDLE or state = S_SEND_END else '0';

    p_crc_input : process (state, i_fall, i_rise, i_cmd, bit_cnt, frame, is_long) is
    begin

        crc_enable <= '0';
        crc_bit    <= '0';

        if state = S_SEND and i_fall = '1' and bit_cnt < CMD_HEADER_BITS then
            crc_enable <= '1';
            crc_bit    <= frame(CMD_HEADER_BITS - 1);
        elsif state = S_RECV and i_rise = '1' then
            crc_bit <= i_cmd;

            if is_long = '0' and bit_cnt >= SHORT_FIRST_POS and bit_cnt <= SHORT_HEAD_LAST then
                crc_enable <= '1';
            elsif is_long = '1' and bit_cnt >= LONG_FIRST_POS and bit_cnt <= LONG_HEAD_LAST then
                crc_enable <= '1';
            end if;
        end if;

    end process p_crc_input;

    u_crc7 : entity work.sd_crc7
        port map (
            i_clk    => i_clk,
            i_rst    => i_rst,
            i_clear  => crc_clear,
            i_enable => crc_enable,
            i_bit    => crc_bit,
            o_crc    => crc_value
        );

    p_control : process (i_clk) is

        -- Último bit da resposta em curso.
        variable last_pos  : natural;
        -- Posição do último bit do CRC7 da resposta em curso.
        variable crc_last  : natural;
        -- Posição do último bit do corpo da resposta em curso.
        variable body_last : natural;
        -- Posição do primeiro bit do corpo da resposta em curso.
        variable body_first : natural;
        -- Erro de CRC7 da resposta que termina agora.
        variable crc_bad   : std_logic;
        -- Erro de índice da resposta que termina agora.
        variable index_bad : std_logic;
        -- Erro de formato da resposta que termina agora.
        variable frame_bad : std_logic;
        -- Posição do bit em andamento, como natural.
        variable pos       : natural;

    begin

        if rising_edge(i_clk) then
            done    <= '0';
            resp_ok <= '0';

            if i_rst = '1' or i_abort = '1' then
                state       <= S_IDLE;
                frame       <= (others => '0');
                bit_cnt     <= (others => '0');
                wait_cnt    <= (others => '0');
                rsp_shift   <= (others => '0');
                rx_crc      <= (others => '0');
                index_r     <= (others => '0');
                response_r  <= RSP_NONE;
                busy_r      <= '0';
                err_timeout <= '0';
                err_crc     <= '0';
                err_index   <= '0';
                err_frame   <= '0';
                cmd_out     <= '1';
                cmd_oe      <= '0';
            else
                pos := to_integer(bit_cnt);

                case state is

                    when S_IDLE =>

                        if i_start = '1' then
                            state       <= S_SEND;
                            frame       <= "01" & i_index & i_argument;
                            index_r     <= i_index;
                            response_r  <= i_response;
                            busy_r      <= i_wait_busy;
                            bit_cnt     <= (others => '0');
                            wait_cnt    <= (others => '0');
                            err_timeout <= '0';
                            err_crc     <= '0';
                            err_index   <= '0';
                            err_frame   <= '0';
                        end if;

                    when S_SEND =>

                        if i_fall = '1' then
                            cmd_oe  <= '1';
                            bit_cnt <= bit_cnt + 1;

                            if pos < CMD_HEADER_BITS then
                                cmd_out <= frame(CMD_HEADER_BITS - 1);
                                frame   <= frame(CMD_HEADER_BITS - 2 downto 0) & '0';
                            elsif pos < CMD_LAST_POS then
                                cmd_out <= crc_value(CMD_LAST_POS - 1 - pos);
                            else
                                cmd_out <= '1';
                                state   <= S_SEND_END;
                            end if;
                        end if;

                    when S_SEND_END =>

                        if i_fall = '1' then
                            cmd_oe   <= '0';
                            cmd_out  <= '1';
                            wait_cnt <= (others => '0');

                            if response_r = RSP_NONE then
                                state <= S_GAP;
                            else
                                state <= S_WAIT_RSP;
                            end if;
                        end if;

                    when S_WAIT_RSP =>

                        if i_rise = '1' then
                            if i_cmd = '0' then
                                state     <= S_RECV;
                                bit_cnt   <= to_unsigned(1, bit_cnt'length);
                                rsp_shift <= (others => '0');
                                rx_crc    <= (others => '0');
                            elsif wait_cnt = ncr_clocks - 1 then
                                err_timeout <= '1';
                                state       <= S_GAP;
                                wait_cnt    <= (others => '0');
                            else
                                wait_cnt <= wait_cnt + 1;
                            end if;
                        end if;

                    when S_RECV =>

                        if i_rise = '1' then
                            bit_cnt <= bit_cnt + 1;

                            if is_long = '1' then
                                last_pos   := LONG_LAST_POS;
                                crc_last   := LONG_CRC_LAST;
                                body_last  := LONG_HEAD_LAST;
                                body_first := LONG_FIRST_POS;
                            else
                                last_pos   := SHORT_LAST_POS;
                                crc_last   := SHORT_CRC_LAST;
                                body_last  := SHORT_HEAD_LAST;
                                body_first := SHORT_FIRST_POS;
                            end if;

                            if pos = 1 and i_cmd /= '0' then
                                err_frame <= '1';
                            end if;

                            if pos >= body_first and pos <= body_last then
                                rsp_shift <= rsp_shift(118 downto 0) & i_cmd;
                            end if;

                            if pos > body_last and pos <= crc_last then
                                rx_crc <= rx_crc(5 downto 0) & i_cmd;
                            end if;

                            if pos = last_pos then
                                crc_bad   := '0';
                                index_bad := '0';
                                frame_bad := err_frame;

                                if i_cmd /= '1' then
                                    frame_bad := '1';
                                end if;

                                if response_r /= RSP_SHORT_NO_CRC and rx_crc /= crc_value then
                                    crc_bad := '1';
                                end if;

                                if response_r = RSP_SHORT and rsp_shift(37 downto 32) /= index_r then
                                    index_bad := '1';
                                end if;

                                err_crc   <= crc_bad;
                                err_index <= index_bad;
                                err_frame <= frame_bad;
                                resp_ok   <= not (crc_bad or index_bad or frame_bad);
                                state     <= S_GAP;
                                wait_cnt  <= (others => '0');
                            end if;
                        end if;

                    when S_GAP =>

                        if i_rise = '1' then
                            wait_cnt <= wait_cnt + 1;

                            if wait_cnt = gap_clocks - 1 then
                                wait_cnt <= (others => '0');

                                if busy_r = '1' and err_timeout = '0' then
                                    state <= S_BUSY;
                                else
                                    state <= S_IDLE;
                                    done  <= '1';
                                end if;
                            end if;
                        end if;

                    when S_BUSY =>

                        if i_rise = '1' then
                            if i_dat0 = '1' then
                                state <= S_IDLE;
                                done  <= '1';
                            elsif wait_cnt >= unsigned(i_timeout) then
                                err_timeout <= '1';
                                state       <= S_IDLE;
                                done        <= '1';
                            else
                                wait_cnt <= wait_cnt + 1;
                            end if;
                        end if;

                end case;
            end if;
        end if;

    end process p_control;

end architecture rtl;
