-- ==========================================================================
-- Controlador de cartão SD no modo nativo mapeado em memória
-- ==========================================================================
-- Conduz um cartão SD ou micro SD pelo modo nativo, com a linha de comando
-- CMD, o clock SD_CLK e as linhas de dados DAT[3:0] (uma ou quatro). O
-- software escreve o argumento em ARG e o comando em CMD; o controle de
-- comando envia o quadro de 48 bits com CRC7, recebe a resposta e a confere.
-- Um comando com DATA_EN transfere também um bloco de 512 bytes entre o
-- cartão e o buffer de bloco, com o CRC16 de cada linha. Cada pino do cartão
-- sai em três portas (valor, habilitação e entrada), e o tristate fica no
-- topo da plataforma.
--
-- Mapa de registradores, em endereços de palavra:
--
--    0 ARG      R/W    argumento do próximo comando
--    1 CMD      R/W    escrever inicia o comando (bits abaixo)
--    2 RESP0    R      bits 31:0 da resposta (argumento, ou CID/CSD bits 39:8)
--    3 RESP1    R      resposta curta: bits 5:0 índice; longa: CID/CSD 71:40
--    4 RESP2    R      longa: CID/CSD bits 103:72
--    5 RESP3    R      longa: CID/CSD bits 127:104 nos bits 23:0
--    6 STATUS   R/W1C  bit 0 CMD_BUSY, 1 DATA_BUSY, 2 CMD_DONE, 3 DATA_DONE,
--                      4 CARD_BUSY (DAT0 baixo), 5 CMD_LINE, 11:8 DAT_LINES,
--                      18:16 WRITE_TOKEN
--    7 ERROR    R/W1C  bit 0 CMD_TIMEOUT, 1 CMD_CRC, 2 CMD_INDEX, 3 CMD_FRAME,
--                      4 DATA_TIMEOUT, 5 DATA_CRC, 6 DATA_FRAME,
--                      7 WRITE_CRC, 8 WRITE_ERROR, 9 DROPPED
--    8 CONTROL  R/W    bit 0 CLK_ENABLE, 1 WIDE_BUS, 2 CMD_IRQ_ENABLE,
--                      3 DATA_IRQ_ENABLE, 4 ERROR_IRQ_ENABLE, 8 ABORT (só escrita)
--    9 DIVIDER  R/W    bits 15:0, SD_CLK = clock / (2 * (DIVIDER + 1))
--   10 TIMEOUT  R/W    bits 23:0, prazo de dado e de ocupado, em clocks do cartão
--   11 DATA     R/W    palavra do buffer apontada por PTR; o acesso avança PTR
--   12 PTR      R/W    bits 6:0, palavra do buffer apontada
--
-- Bits de CMD: 5:0 índice, 7:6 formato da resposta (0 nenhuma, 1 curta com
-- CRC7, 2 curta sem CRC7, 3 longa), 8 WAIT_BUSY (R1b), 9 DATA_EN, 10 DATA_WRITE.
-- Os eventos novos têm prioridade sobre a limpeza W1C. A saída o_irq é de nível
-- e soma três causas, cada uma com a sua habilitação (zero no reset).
-- ==========================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.config_pkg.all;
use work.sd_native_pkg.all;

entity sd_native is
    generic (
        -- Frequência do clock do módulo, em hertz.
        clock_hz           : positive := 50_000_000;
        -- Frequência de SD_CLK no reset, em hertz (a inicialização exige no máximo 400 kHz).
        init_clk_hz        : positive := 400_000;
        -- Prazo inicial de dado e de ocupado, em clocks do cartão.
        default_timeout    : positive := 2_500_000;
        -- Flip-flops em série nas linhas CMD e DAT de entrada (um a mais exige divisor mínimo maior).
        input_sync_stages  : positive := 1
    );
    port (
        -- Clock do módulo.
        i_clk         : in    std_logic;
        -- Reset síncrono, ativo em nível alto.
        i_rst         : in    std_logic;
        -- Dado de escrita vindo do processador.
        i_data_in     : in    word_t;
        -- Endereço de palavra do registrador, entre zero e doze.
        i_address     : in    std_logic_vector(3 downto 0);
        -- Pulso de escrita do processador.
        i_write       : in    std_logic;
        -- Pulso de leitura do processador.
        i_read        : in    std_logic;
        -- Dado de leitura devolvido ao processador.
        o_data_out    : out   word_t;
        -- Requisição de interrupção de nível.
        o_irq         : out   std_logic;
        -- Clock do cartão (SD_CLK).
        o_sd_clk      : out   std_logic;
        -- Valor aplicado à linha de comando (SD_CMD).
        o_sd_cmd      : out   std_logic;
        -- Habilitação da saída da linha de comando.
        o_sd_cmd_oe   : out   std_logic;
        -- Nível da linha de comando.
        i_sd_cmd      : in    std_logic;
        -- Valores aplicados às linhas de dados (SD_DATA[3:0] ou SD_DAT[3:0]).
        o_sd_dat      : out   std_logic_vector(3 downto 0);
        -- Habilitação da saída de cada linha de dados.
        o_sd_dat_oe   : out   std_logic_vector(3 downto 0);
        -- Nível das linhas de dados.
        i_sd_dat      : in    std_logic_vector(3 downto 0)
    );
end entity sd_native;

architecture rtl of sd_native is

    -- Largura do divisor em bits.
    constant DIVIDER_WIDTH : positive := 16;
    -- Divisor do reset, que mantém SD_CLK em init_clk_hz ou abaixo.
    constant RESET_DIVIDER : natural := (clock_hz + 2 * init_clk_hz - 1) / (2 * init_clk_hz) - 1;

    -- Cadeia de sincronização das linhas de entrada, CMD no bit 4 e DAT[3:0] nos bits 3 a 0.
    type sync_chain_t is array (0 to input_sync_stages - 1) of std_logic_vector(4 downto 0);

    -- Linhas de entrada em cada estágio da cadeia.
    signal sync_chain : sync_chain_t;
    -- Linha CMD registrada.
    signal cmd_q      : std_logic;
    -- Linhas DAT registradas.
    signal dat_q      : std_logic_vector(3 downto 0);

    -- Argumento do próximo comando.
    signal arg_reg      : std_logic_vector(31 downto 0);
    -- Índice do comando escrito em CMD.
    signal cmd_index    : std_logic_vector(5 downto 0);
    -- Formato de resposta do comando escrito em CMD.
    signal cmd_response : std_logic_vector(1 downto 0);
    -- Espera por ocupado do comando escrito em CMD.
    signal cmd_wait_busy : std_logic;
    -- Comando com transferência de bloco.
    signal cmd_data_en  : std_logic;
    -- Sentido da transferência de bloco, 1 para escrita no cartão.
    signal cmd_data_wr  : std_logic;
    -- Clock do cartão sempre ligado.
    signal clk_enable   : std_logic;
    -- Barramento de quatro linhas.
    signal wide_bus     : std_logic;
    -- Habilitação da interrupção por fim de comando.
    signal cmd_irq_en   : std_logic;
    -- Habilitação da interrupção por fim de transferência de dados.
    signal data_irq_en  : std_logic;
    -- Habilitação da interrupção por erro.
    signal err_irq_en   : std_logic;
    -- Divisor de clock de SD_CLK.
    signal divider      : std_logic_vector(DIVIDER_WIDTH - 1 downto 0);
    -- Prazo de dado e de ocupado.
    signal timeout      : std_logic_vector(TIMEOUT_WIDTH - 1 downto 0);
    -- Marca persistente de fim de comando.
    signal cmd_done_flag  : std_logic;
    -- Marca persistente de fim de transferência de dados.
    signal data_done_flag : std_logic;
    -- Transferência de dados à espera do fim da resposta do comando.
    signal data_pending : std_logic;
    -- Erros persistentes.
    signal errors       : std_logic_vector(9 downto 0);
    -- Estado de CRC da última escrita de bloco.
    signal write_token  : std_logic_vector(2 downto 0);
    -- Ponteiro da janela do buffer.
    signal ptr          : unsigned(6 downto 0);
    -- Valor do ponteiro no próximo ciclo.
    signal ptr_next     : unsigned(6 downto 0);

    -- Pedido de clock do cartão.
    signal run          : std_logic;
    -- Pulso que antecede a borda de subida de SD_CLK.
    signal sclk_rise    : std_logic;
    -- Pulso que antecede a borda de descida de SD_CLK.
    signal sclk_fall    : std_logic;
    -- Pedido de aborto das duas máquinas.
    signal abort        : std_logic;

    -- Pedido de início de comando.
    signal cmd_start    : std_logic;
    -- Comando em andamento.
    signal cmd_busy     : std_logic;
    -- Pulso de fim de comando.
    signal cmd_done     : std_logic;
    -- Pulso de resposta válida.
    signal cmd_resp_ok  : std_logic;
    -- Resposta do cartão.
    signal response     : std_logic_vector(127 downto 0);
    -- Erros do comando, na ordem dos bits 3 a 0 de ERROR.
    signal cmd_errors   : std_logic_vector(3 downto 0);

    -- Pedido de início de transferência de dados.
    signal data_start   : std_logic;
    -- Transferência de dados em andamento.
    signal data_busy    : std_logic;
    -- Pulso de fim de transferência de dados.
    signal data_done    : std_logic;
    -- Estado de CRC devolvido pelo controle de dados.
    signal data_token   : std_logic_vector(2 downto 0);
    -- Erros dos dados, na ordem dos bits 8 a 4 de ERROR.
    signal data_errors  : std_logic_vector(4 downto 0);

    -- Buffer de bloco: o controle de dados é dono dele durante a transferência.
    -- Controle de dados escreve no buffer (leitura do cartão).
    signal engine_writes_buf : std_logic;
    -- Controle de dados lê o buffer (escrita no cartão).
    signal engine_reads_buf  : std_logic;
    -- Endereço de palavra pedido pelo controle de dados.
    signal engine_address    : std_logic_vector(6 downto 0);
    -- Pedido de escrita do controle de dados.
    signal engine_we         : std_logic;
    -- Palavra de escrita do controle de dados.
    signal engine_wdata      : std_logic_vector(31 downto 0);
    -- Pedido de escrita no buffer.
    signal buf_we            : std_logic;
    -- Endereço de escrita no buffer.
    signal buf_waddr         : std_logic_vector(6 downto 0);
    -- Palavra de escrita no buffer.
    signal buf_wdata         : std_logic_vector(31 downto 0);
    -- Endereço de leitura do buffer.
    signal buf_raddr         : std_logic_vector(6 downto 0);
    -- Palavra lida do buffer.
    signal buf_rdata         : std_logic_vector(31 downto 0);

    -- Pedido do software de escrever em CMD.
    signal write_cmd         : std_logic;
    -- A escrita em CMD é recusada porque uma operação ainda está em andamento.
    signal cmd_refused       : std_logic;
    -- Pedido do software de escrever em DATA.
    signal write_data        : std_logic;
    -- Pedido do software de escrever em PTR.
    signal write_ptr         : std_logic;
    -- Acesso do software à janela DATA.
    signal access_data       : std_logic;
    -- Algum erro persistente está marcado.
    signal any_error         : std_logic;

begin

    assert RESET_DIVIDER < 2 ** DIVIDER_WIDTH
        report "sd_native: clock_hz / init_clk_hz does not fit in the 16-bit divider"
        severity failure;

    assert default_timeout < 2 ** TIMEOUT_WIDTH
        report "sd_native: default_timeout does not fit in the 24-bit timeout"
        severity failure;

    write_cmd    <= '1' when i_write = '1' and i_address = CMD_ADDRESS else '0';
    cmd_refused  <= write_cmd and (cmd_busy or data_busy or data_pending);
    cmd_start    <= write_cmd and not (cmd_busy or data_busy or data_pending);
    abort        <= '1' when i_write = '1' and i_address = CONTROL_ADDRESS and i_data_in(8) = '1' else '0';
    run          <= clk_enable or cmd_busy or data_busy;
    data_start   <= cmd_resp_ok and data_pending;
    write_data   <= '1' when i_write = '1' and i_address = DATA_ADDRESS else '0';
    write_ptr    <= '1' when i_write = '1' and i_address = PTR_ADDRESS else '0';
    access_data  <= '1' when (i_write = '1' or i_read = '1') and i_address = DATA_ADDRESS else '0';

    cmd_q <= sync_chain(input_sync_stages - 1)(4);
    dat_q <= sync_chain(input_sync_stages - 1)(3 downto 0);

    ptr_next <= unsigned(i_data_in(6 downto 0)) when write_ptr = '1'
                else ptr + 1 when access_data = '1'
                else ptr;

    engine_writes_buf <= data_busy and not cmd_data_wr;
    engine_reads_buf  <= data_busy and cmd_data_wr;
    buf_we            <= engine_we when engine_writes_buf = '1' else write_data;
    buf_waddr         <= engine_address when engine_writes_buf = '1' else std_logic_vector(ptr);
    buf_wdata         <= engine_wdata when engine_writes_buf = '1' else i_data_in(31 downto 0);
    buf_raddr         <= engine_address when engine_reads_buf = '1' else std_logic_vector(ptr_next);

    any_error <= '0' when errors = "0000000000" else '1';

    o_irq <= (cmd_irq_en and cmd_done_flag) or (data_irq_en and data_done_flag) or (err_irq_en and any_error);

    u_clock : entity work.sd_clock_gen
        generic map (
            divider_width => DIVIDER_WIDTH
        )
        port map (
            i_clk     => i_clk,
            i_rst     => i_rst,
            i_divider => divider,
            i_run     => run,
            o_sclk    => o_sd_clk,
            o_rise    => sclk_rise,
            o_fall    => sclk_fall
        );

    u_cmd : entity work.sd_cmd
        port map (
            i_clk         => i_clk,
            i_rst         => i_rst,
            i_abort       => abort,
            i_start       => cmd_start,
            i_index       => i_data_in(5 downto 0),
            i_argument    => arg_reg,
            i_response    => i_data_in(7 downto 6),
            i_wait_busy   => i_data_in(8),
            i_timeout     => timeout,
            i_rise        => sclk_rise,
            i_fall        => sclk_fall,
            i_cmd         => cmd_q,
            i_dat0        => dat_q(0),
            o_cmd         => o_sd_cmd,
            o_cmd_oe      => o_sd_cmd_oe,
            o_busy        => cmd_busy,
            o_done        => cmd_done,
            o_resp_ok     => cmd_resp_ok,
            o_response    => response,
            o_err_timeout => cmd_errors(0),
            o_err_crc     => cmd_errors(1),
            o_err_index   => cmd_errors(2),
            o_err_frame   => cmd_errors(3)
        );

    u_data : entity work.sd_data
        port map (
            i_clk           => i_clk,
            i_rst           => i_rst,
            i_abort         => abort,
            i_start         => data_start,
            i_write         => cmd_data_wr,
            i_wide          => wide_bus,
            i_timeout       => timeout,
            i_rise          => sclk_rise,
            i_fall          => sclk_fall,
            i_dat           => dat_q,
            o_dat           => o_sd_dat,
            o_dat_oe        => o_sd_dat_oe,
            o_buf_address   => engine_address,
            o_buf_we        => engine_we,
            o_buf_data      => engine_wdata,
            i_buf_data      => buf_rdata,
            o_busy          => data_busy,
            o_done          => data_done,
            o_token         => data_token,
            o_err_timeout   => data_errors(0),
            o_err_crc       => data_errors(1),
            o_err_frame     => data_errors(2),
            o_err_write_crc => data_errors(3),
            o_err_write     => data_errors(4)
        );

    u_buffer : entity work.sd_block_buffer
        port map (
            i_clk           => i_clk,
            i_write_enable  => buf_we,
            i_write_address => buf_waddr,
            i_write_data    => buf_wdata,
            i_read_address  => buf_raddr,
            o_read_data     => buf_rdata
        );

    p_sync : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            if i_rst = '1' then
                for stage in 0 to input_sync_stages - 1 loop
                    sync_chain(stage) <= (others => '1');
                end loop;
            else
                sync_chain(0) <= i_sd_cmd & i_sd_dat;

                for stage in 1 to input_sync_stages - 1 loop
                    sync_chain(stage) <= sync_chain(stage - 1);
                end loop;
            end if;
        end if;

    end process p_sync;

    p_registers : process (i_clk) is

        -- Erros persistentes no próximo ciclo, com a limpeza e os eventos aplicados.
        variable next_errors : std_logic_vector(9 downto 0);

    begin

        if rising_edge(i_clk) then
            if i_rst = '1' then
                arg_reg        <= (others => '0');
                cmd_index      <= (others => '0');
                cmd_response   <= RSP_NONE;
                cmd_wait_busy  <= '0';
                cmd_data_en    <= '0';
                cmd_data_wr    <= '0';
                clk_enable     <= '0';
                wide_bus       <= '0';
                cmd_irq_en     <= '0';
                data_irq_en    <= '0';
                err_irq_en     <= '0';
                divider        <= std_logic_vector(to_unsigned(RESET_DIVIDER, DIVIDER_WIDTH));
                timeout        <= std_logic_vector(to_unsigned(default_timeout, TIMEOUT_WIDTH));
                cmd_done_flag  <= '0';
                data_done_flag <= '0';
                data_pending   <= '0';
                errors         <= (others => '0');
                write_token    <= (others => '0');
                ptr            <= (others => '0');
            else
                ptr <= ptr_next;

                if i_write = '1' and i_address = ARG_ADDRESS then
                    arg_reg <= i_data_in(31 downto 0);
                end if;

                if i_write = '1' and i_address = CONTROL_ADDRESS then
                    clk_enable  <= i_data_in(0);
                    wide_bus    <= i_data_in(1);
                    cmd_irq_en  <= i_data_in(2);
                    data_irq_en <= i_data_in(3);
                    err_irq_en  <= i_data_in(4);
                end if;

                if i_write = '1' and i_address = DIVIDER_ADDRESS then
                    divider <= i_data_in(DIVIDER_WIDTH - 1 downto 0);
                end if;

                if i_write = '1' and i_address = TIMEOUT_ADDRESS then
                    timeout <= i_data_in(TIMEOUT_WIDTH - 1 downto 0);
                end if;

                -- Os eventos novos têm prioridade sobre uma limpeza simultânea.
                if i_write = '1' and i_address = STATUS_ADDRESS then
                    cmd_done_flag  <= cmd_done_flag and not i_data_in(2);
                    data_done_flag <= data_done_flag and not i_data_in(3);
                end if;

                next_errors := errors;

                if i_write = '1' and i_address = ERROR_ADDRESS then
                    next_errors := errors and not i_data_in(9 downto 0);
                end if;

                if cmd_done = '1' then
                    next_errors(3 downto 0) := next_errors(3 downto 0) or cmd_errors;
                end if;

                if data_done = '1' then
                    next_errors(8 downto 4) := next_errors(8 downto 4) or data_errors;
                end if;

                if cmd_refused = '1' then
                    next_errors(9) := '1';
                end if;

                if cmd_start = '1' then
                    cmd_index     <= i_data_in(5 downto 0);
                    cmd_response  <= i_data_in(7 downto 6);
                    cmd_wait_busy <= i_data_in(8);
                    cmd_data_en   <= i_data_in(9);
                    cmd_data_wr   <= i_data_in(10);
                    data_pending  <= i_data_in(9);
                    cmd_done_flag <= '0';

                    if i_data_in(9) = '1' then
                        data_done_flag <= '0';
                    end if;
                end if;

                if data_start = '1' then
                    data_pending <= '0';
                end if;

                if cmd_done = '1' then
                    cmd_done_flag <= '1';

                    -- Uma resposta recusada cancela o bloco, que então também termina.
                    if data_pending = '1' and data_start = '0' then
                        data_pending   <= '0';
                        data_done_flag <= '1';
                    end if;
                end if;

                if data_done = '1' then
                    data_done_flag <= '1';

                    if cmd_data_wr = '1' then
                        write_token <= data_token;
                    end if;
                end if;

                if abort = '1' then
                    data_pending <= '0';
                end if;

                errors <= next_errors;
            end if;
        end if;

    end process p_registers;

    p_readback : process (
                          i_address, response, errors, clk_enable, wide_bus, cmd_irq_en, data_irq_en, err_irq_en, divider,
                          timeout, buf_rdata, ptr, arg_reg, cmd_data_wr, cmd_data_en, cmd_wait_busy, cmd_response,
                          cmd_index, cmd_busy, data_busy, data_pending, cmd_done_flag, data_done_flag, dat_q, cmd_q,
                          write_token
                         ) is

        -- Valor montado para o registrador selecionado.
        variable value : word_t;

    begin

        value := (others => '0');

        case i_address is

            when ARG_ADDRESS =>

                value(31 downto 0) := arg_reg;

            when CMD_ADDRESS =>

                value(10 downto 0) := cmd_data_wr & cmd_data_en & cmd_wait_busy & cmd_response & cmd_index;

            when RESP0_ADDRESS =>

                value(31 downto 0) := response(31 downto 0);

            when RESP1_ADDRESS =>

                value(31 downto 0) := response(63 downto 32);

            when RESP2_ADDRESS =>

                value(31 downto 0) := response(95 downto 64);

            when RESP3_ADDRESS =>

                value(31 downto 0) := response(127 downto 96);

            when STATUS_ADDRESS =>

                value(0)            := cmd_busy;
                value(1)            := data_busy or data_pending;
                value(2)            := cmd_done_flag;
                value(3)            := data_done_flag;
                value(4)            := not dat_q(0);
                value(5)            := cmd_q;
                value(11 downto 8)  := dat_q;
                value(18 downto 16) := write_token;

            when ERROR_ADDRESS =>

                value(9 downto 0) := errors;

            when CONTROL_ADDRESS =>

                value(0) := clk_enable;
                value(1) := wide_bus;
                value(2) := cmd_irq_en;
                value(3) := data_irq_en;
                value(4) := err_irq_en;

            when DIVIDER_ADDRESS =>

                value(DIVIDER_WIDTH - 1 downto 0) := divider;

            when TIMEOUT_ADDRESS =>

                value(TIMEOUT_WIDTH - 1 downto 0) := timeout;

            when DATA_ADDRESS =>

                value(31 downto 0) := buf_rdata;

            when PTR_ADDRESS =>

                value(6 downto 0) := std_logic_vector(ptr);

            when others =>

                null;

        end case;

        o_data_out <= value;

    end process p_readback;

end architecture rtl;
