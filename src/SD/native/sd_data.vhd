-- ==========================================================================
-- Controle dos dados do cartão SD no modo nativo
-- ==========================================================================
-- Transfere um bloco de 512 bytes pelas linhas DAT[3:0], com quatro linhas
-- (um nibble por clock, DAT3 é o bit mais significativo) ou com uma linha
-- (um bit por clock em DAT0), conforme i_wide. Cada linha ativa tem o seu
-- CRC16 de 16 bits. O bloco fica num buffer de 128 palavras de 32 bits, com o
-- primeiro byte do bloco nos bits 7 a 0 da palavra 0.
--
-- Leitura (i_write em 0): espera o bit de início em DAT0 por no máximo
-- i_timeout clocks, recebe os dados, o CRC16 de cada linha e o bit de fim, e
-- confere os CRC16 e os bits de início e de fim.
--
-- Escrita (i_write em 1): espera NWR_CLOCKS clocks, envia o bit de início, os
-- dados, o CRC16 de cada linha e o bit de fim, solta as linhas, recebe o
-- estado de CRC de 3 bits em DAT0 (010 aceito, 101 erro de CRC, 110 erro de
-- gravação) e espera DAT0 voltar a 1 (fim do ocupado) por no máximo i_timeout
-- clocks.
--
-- Os bits saem na borda de descida de SD_CLK e são amostrados na de subida.
-- o_done dura um ciclo, junto com o_busy em zero, e os erros e o estado de CRC
-- valem de o_done até o próximo i_start.
-- ==========================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.sd_native_pkg.all;

entity sd_data is
    port (
        -- Clock do módulo.
        i_clk           : in    std_logic;
        -- Reset síncrono, ativo em nível alto.
        i_rst           : in    std_logic;
        -- Interrompe a transferência em andamento sem sinalizar fim nem erro.
        i_abort         : in    std_logic;
        -- Pedido de início, aceito apenas com o_busy em zero.
        i_start         : in    std_logic;
        -- Sentido da transferência, 1 para escrita no cartão e 0 para leitura.
        i_write         : in    std_logic;
        -- Largura do barramento, 1 para quatro linhas e 0 para uma.
        i_wide          : in    std_logic;
        -- Limite das esperas por início de bloco e por ocupado, em clocks do cartão.
        i_timeout       : in    std_logic_vector(TIMEOUT_WIDTH - 1 downto 0);
        -- Pulso que antecede a borda de subida de SD_CLK.
        i_rise          : in    std_logic;
        -- Pulso que antecede a borda de descida de SD_CLK.
        i_fall          : in    std_logic;
        -- Linhas DAT[3:0] vistas pelo mestre, já registradas.
        i_dat           : in    std_logic_vector(3 downto 0);
        -- Valor que o mestre aplica às linhas DAT[3:0].
        o_dat           : out   std_logic_vector(3 downto 0);
        -- Habilitação da saída de cada linha DAT.
        o_dat_oe        : out   std_logic_vector(3 downto 0);
        -- Palavra do buffer em acesso.
        o_buf_address   : out   std_logic_vector(6 downto 0);
        -- Pedido de escrita no buffer, na leitura do bloco.
        o_buf_we        : out   std_logic;
        -- Palavra a escrever no buffer.
        o_buf_data      : out   std_logic_vector(31 downto 0);
        -- Palavra lida do buffer, uma borda depois do endereço.
        i_buf_data      : in    std_logic_vector(31 downto 0);
        -- Indica transferência em andamento, que pede o clock do cartão.
        o_busy          : out   std_logic;
        -- Pulso de um ciclo ao fim da transferência, com ou sem erro.
        o_done          : out   std_logic;
        -- Estado de CRC recebido do cartão depois de um bloco escrito.
        o_token         : out   std_logic_vector(2 downto 0);
        -- Início do bloco ou fim do ocupado fora do prazo.
        o_err_timeout   : out   std_logic;
        -- CRC16 do bloco lido não confere.
        o_err_crc       : out   std_logic;
        -- Bit de início ou de fim com valor errado.
        o_err_frame     : out   std_logic;
        -- O cartão recusou o bloco escrito por erro de CRC (estado 101).
        o_err_write_crc : out   std_logic;
        -- O cartão recusou o bloco escrito por outro motivo.
        o_err_write     : out   std_logic
    );
end entity sd_data;

architecture rtl of sd_data is

    -- Estados do controle de dados.
    type state_t is (
        S_IDLE, S_RD_WAIT, S_RD_DATA, S_RD_CRC, S_RD_END,
        S_WR_GAP, S_WR_START, S_WR_DATA, S_WR_CRC, S_WR_END, S_WR_RELEASE,
        S_WR_TOKEN_WAIT, S_WR_TOKEN, S_WR_TOKEN_END, S_WR_GUARD, S_WR_BUSY
    );

    -- Vetor com o CRC16 de cada linha.
    type crc_array_t is array (0 to 3) of std_logic_vector(15 downto 0);

    -- Estado atual.
    signal state       : state_t;
    -- Barramento largo (quatro linhas) na transferência em andamento.
    signal wide_r      : std_logic;
    -- Linhas ativas na transferência em andamento.
    signal lane_mask   : std_logic_vector(3 downto 0);
    -- Clocks de dados já passados no bloco.
    signal unit_cnt    : unsigned(12 downto 0);
    -- Bits de CRC já passados.
    signal crc_cnt     : unsigned(4 downto 0);
    -- Clocks já contados na espera atual.
    signal wait_cnt    : unsigned(TIMEOUT_WIDTH - 1 downto 0);
    -- Clock de dados dentro do byte atual.
    signal sub_cnt     : unsigned(2 downto 0);
    -- Byte dentro da palavra atual.
    signal byte_idx    : unsigned(1 downto 0);
    -- Palavra do buffer em acesso.
    signal word_idx    : unsigned(6 downto 0);
    -- Byte que está saindo (escrita) ou chegando (leitura).
    signal byte_sh     : std_logic_vector(7 downto 0);
    -- Palavra que está saindo (escrita) ou chegando (leitura).
    signal word_sh     : std_logic_vector(31 downto 0);
    -- CRC16 recebido de cada linha.
    signal rx_crc      : crc_array_t;
    -- Estado de CRC recebido.
    signal token       : std_logic_vector(2 downto 0);
    -- Pulso de fim de transferência.
    signal done        : std_logic;
    -- Pedido de escrita no buffer.
    signal buf_we      : std_logic;
    -- Palavra a escrever no buffer.
    signal buf_data    : std_logic_vector(31 downto 0);
    -- Erro de prazo da transferência em andamento.
    signal err_timeout : std_logic;
    -- Erro de CRC16 da transferência em andamento.
    signal err_crc     : std_logic;
    -- Erro de formato da transferência em andamento.
    signal err_frame   : std_logic;
    -- Erro de CRC16 acusado pelo cartão na transferência em andamento.
    signal err_wr_crc  : std_logic;
    -- Outro erro de gravação acusado pelo cartão.
    signal err_wr      : std_logic;
    -- Valor aplicado às linhas DAT.
    signal dat_out     : std_logic_vector(3 downto 0);
    -- Habilitação da saída das linhas DAT.
    signal dat_oe      : std_logic_vector(3 downto 0);

    -- Zera os CRC16.
    signal crc_clear   : std_logic;
    -- Incorpora um bit a cada CRC16.
    signal crc_enable  : std_logic_vector(3 downto 0);
    -- Bit incorporado a cada CRC16.
    signal crc_bit     : std_logic_vector(3 downto 0);
    -- CRC16 calculado de cada linha.
    signal crc_value   : crc_array_t;

    -- Quantidade de clocks de dados do bloco no modo escolhido.
    signal total_units : unsigned(12 downto 0);
    -- Byte que sai no clock de dados atual da escrita.
    signal tx_byte     : std_logic_vector(7 downto 0);
    -- Bits que saem no clock de dados atual da escrita, DAT3 no bit 3.
    signal tx_bits     : std_logic_vector(3 downto 0);

begin

    o_dat           <= dat_out;
    o_dat_oe        <= dat_oe;
    o_buf_address   <= std_logic_vector(word_idx);
    o_buf_we        <= buf_we;
    o_buf_data      <= buf_data;
    o_busy          <= '0' when state = S_IDLE else '1';
    o_done          <= done;
    o_token         <= token;
    o_err_timeout   <= err_timeout;
    o_err_crc       <= err_crc;
    o_err_frame     <= err_frame;
    o_err_write_crc <= err_wr_crc;
    o_err_write     <= err_wr;

    total_units <= to_unsigned(WIDE_UNITS, total_units'length) when wide_r = '1'
                   else to_unsigned(NARROW_UNITS, total_units'length);

    -- Os CRC16 ficam zerados em repouso e antes do primeiro bit de dado.
    crc_clear <= '1' when state = S_IDLE or state = S_RD_WAIT or state = S_WR_GAP or state = S_WR_START else '0';

    tx_byte <= word_sh(7 downto 0) when sub_cnt = 0 else byte_sh;

    tx_bits <= tx_byte(7 downto 4) when wide_r = '1' and sub_cnt = 0
               else tx_byte(3 downto 0) when wide_r = '1'
               else "111" & tx_byte(7 - to_integer(sub_cnt));

    crc_enable <= lane_mask when (state = S_RD_DATA and i_rise = '1') or (state = S_WR_DATA and i_fall = '1')
                  else "0000";
    crc_bit    <= i_dat when state = S_RD_DATA else tx_bits;

    g_crc : for line in 0 to 3 generate

        u_crc16 : entity work.sd_crc16
            port map (
                i_clk    => i_clk,
                i_rst    => i_rst,
                i_clear  => crc_clear,
                i_enable => crc_enable(line),
                i_bit    => crc_bit(line),
                o_crc    => crc_value(line)
            );

    end generate g_crc;

    p_control : process (i_clk) is

        -- Byte completo que acaba de chegar na leitura.
        variable new_byte  : std_logic_vector(7 downto 0);
        -- Último clock do byte, 1 com quatro linhas e 7 com uma.
        variable byte_last : natural;
        -- Erro de CRC16 do bloco que termina agora.
        variable crc_bad   : std_logic;
        -- Erro de formato do bloco que termina agora.
        variable frame_bad : std_logic;

    begin

        if rising_edge(i_clk) then
            done   <= '0';
            buf_we <= '0';

            if i_rst = '1' or i_abort = '1' then
                state       <= S_IDLE;
                wide_r      <= '0';
                lane_mask   <= "0001";
                unit_cnt    <= (others => '0');
                crc_cnt     <= (others => '0');
                wait_cnt    <= (others => '0');
                sub_cnt     <= (others => '0');
                byte_idx    <= (others => '0');
                word_idx    <= (others => '0');
                byte_sh     <= (others => '0');
                word_sh     <= (others => '0');
                buf_data    <= (others => '0');
                token       <= (others => '0');
                err_timeout <= '0';
                err_crc     <= '0';
                err_frame   <= '0';
                err_wr_crc  <= '0';
                err_wr      <= '0';
                dat_out     <= (others => '1');
                dat_oe      <= (others => '0');
                for line in 0 to 3 loop
                    rx_crc(line) <= (others => '0');
                end loop;
            else
                if buf_we = '1' then
                    word_idx <= word_idx + 1;
                end if;

                if wide_r = '1' then
                    byte_last := 1;
                else
                    byte_last := 7;
                end if;

                case state is

                    when S_IDLE =>

                        if i_start = '1' then
                            wide_r      <= i_wide;
                            unit_cnt    <= (others => '0');
                            crc_cnt     <= (others => '0');
                            wait_cnt    <= (others => '0');
                            sub_cnt     <= (others => '0');
                            byte_idx    <= (others => '0');
                            word_idx    <= (others => '0');
                            err_timeout <= '0';
                            err_crc     <= '0';
                            err_frame   <= '0';
                            err_wr_crc  <= '0';
                            err_wr      <= '0';

                            if i_wide = '1' then
                                lane_mask <= "1111";
                            else
                                lane_mask <= "0001";
                            end if;

                            if i_write = '1' then
                                state <= S_WR_GAP;
                            else
                                state <= S_RD_WAIT;
                            end if;
                        end if;

                    when S_RD_WAIT =>

                        if i_rise = '1' then
                            if i_dat(0) = '0' then
                                state <= S_RD_DATA;

                                if (i_dat and lane_mask) /= "0000" then
                                    err_frame <= '1';
                                end if;
                            elsif wait_cnt >= unsigned(i_timeout) then
                                err_timeout <= '1';
                                state       <= S_IDLE;
                                done        <= '1';
                            else
                                wait_cnt <= wait_cnt + 1;
                            end if;
                        end if;

                    when S_RD_DATA =>

                        if i_rise = '1' then
                            unit_cnt <= unit_cnt + 1;

                            if wide_r = '1' then
                                new_byte := byte_sh(3 downto 0) & i_dat;
                            else
                                new_byte := byte_sh(6 downto 0) & i_dat(0);
                            end if;

                            byte_sh <= new_byte;

                            if sub_cnt = byte_last then
                                sub_cnt  <= (others => '0');
                                word_sh  <= new_byte & word_sh(31 downto 8);
                                byte_idx <= byte_idx + 1;

                                if byte_idx = 3 then
                                    buf_we   <= '1';
                                    buf_data <= new_byte & word_sh(31 downto 8);
                                end if;
                            else
                                sub_cnt <= sub_cnt + 1;
                            end if;

                            if unit_cnt = total_units - 1 then
                                state   <= S_RD_CRC;
                                crc_cnt <= (others => '0');
                            end if;
                        end if;

                    when S_RD_CRC =>

                        if i_rise = '1' then
                            for line in 0 to 3 loop
                                rx_crc(line) <= rx_crc(line)(14 downto 0) & i_dat(line);
                            end loop;

                            crc_cnt <= crc_cnt + 1;

                            if crc_cnt = DATA_CRC_BITS - 1 then
                                state <= S_RD_END;
                            end if;
                        end if;

                    when S_RD_END =>

                        if i_rise = '1' then
                            crc_bad   := '0';
                            frame_bad := err_frame;

                            for line in 0 to 3 loop
                                if lane_mask(line) = '1' then
                                    if rx_crc(line) /= crc_value(line) then
                                        crc_bad := '1';
                                    end if;

                                    if i_dat(line) /= '1' then
                                        frame_bad := '1';
                                    end if;
                                end if;
                            end loop;

                            err_crc   <= crc_bad;
                            err_frame <= frame_bad;
                            state     <= S_IDLE;
                            done      <= '1';
                        end if;

                    when S_WR_GAP =>

                        if i_rise = '1' then
                            if wait_cnt = NWR_CLOCKS - 1 then
                                state <= S_WR_START;
                            else
                                wait_cnt <= wait_cnt + 1;
                            end if;
                        end if;

                    when S_WR_START =>

                        if i_fall = '1' then
                            dat_out  <= (others => '0');
                            dat_oe   <= lane_mask;
                            word_sh  <= i_buf_data;
                            word_idx <= word_idx + 1;
                            state    <= S_WR_DATA;
                        end if;

                    when S_WR_DATA =>

                        if i_fall = '1' then
                            dat_out  <= tx_bits;
                            byte_sh  <= tx_byte;
                            unit_cnt <= unit_cnt + 1;

                            if sub_cnt = byte_last then
                                sub_cnt  <= (others => '0');
                                byte_idx <= byte_idx + 1;

                                if byte_idx = 3 then
                                    word_sh  <= i_buf_data;
                                    word_idx <= word_idx + 1;
                                else
                                    word_sh <= x"00" & word_sh(31 downto 8);
                                end if;
                            else
                                sub_cnt <= sub_cnt + 1;
                            end if;

                            if unit_cnt = total_units - 1 then
                                state   <= S_WR_CRC;
                                crc_cnt <= (others => '0');
                            end if;
                        end if;

                    when S_WR_CRC =>

                        if i_fall = '1' then
                            for line in 0 to 3 loop
                                dat_out(line) <= crc_value(line)(15 - to_integer(crc_cnt));
                            end loop;

                            crc_cnt <= crc_cnt + 1;

                            if crc_cnt = DATA_CRC_BITS - 1 then
                                state <= S_WR_END;
                            end if;
                        end if;

                    when S_WR_END =>

                        if i_fall = '1' then
                            dat_out <= (others => '1');
                            state   <= S_WR_RELEASE;
                        end if;

                    when S_WR_RELEASE =>

                        if i_fall = '1' then
                            dat_oe   <= (others => '0');
                            wait_cnt <= (others => '0');
                            state    <= S_WR_TOKEN_WAIT;
                        end if;

                    when S_WR_TOKEN_WAIT =>

                        if i_rise = '1' then
                            if i_dat(0) = '0' then
                                state   <= S_WR_TOKEN;
                                crc_cnt <= (others => '0');
                            elsif wait_cnt = TOKEN_WAIT_CLOCKS - 1 then
                                err_timeout <= '1';
                                state       <= S_IDLE;
                                done        <= '1';
                            else
                                wait_cnt <= wait_cnt + 1;
                            end if;
                        end if;

                    when S_WR_TOKEN =>

                        if i_rise = '1' then
                            token   <= token(1 downto 0) & i_dat(0);
                            crc_cnt <= crc_cnt + 1;

                            if crc_cnt = 2 then
                                state <= S_WR_TOKEN_END;
                            end if;
                        end if;

                    when S_WR_TOKEN_END =>

                        if i_rise = '1' then
                            if i_dat(0) /= '1' then
                                err_frame <= '1';
                            end if;

                            if token = TOKEN_CRC_ERROR then
                                err_wr_crc <= '1';
                            elsif token /= TOKEN_ACCEPTED then
                                err_wr <= '1';
                            end if;

                            wait_cnt <= (others => '0');
                            state    <= S_WR_GUARD;
                        end if;

                    when S_WR_GUARD =>

                        if i_rise = '1' then
                            if wait_cnt = BUSY_GUARD_CLOCKS - 1 then
                                wait_cnt <= (others => '0');
                                state    <= S_WR_BUSY;
                            else
                                wait_cnt <= wait_cnt + 1;
                            end if;
                        end if;

                    when S_WR_BUSY =>

                        if i_rise = '1' then
                            if i_dat(0) = '1' then
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
