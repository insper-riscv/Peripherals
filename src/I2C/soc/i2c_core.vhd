-- =============================================================================
-- Máquina de estados de linha do mestre I2C
--
-- Gera as condições de início, de repetição de início e de parada e envia ou
-- recebe um byte com a fase de ACK, um comando por vez. Cada bit de SCL dura
-- cinco passos de relógio (três com SCL baixo e dois com SCL alto), de modo que
-- f_scl = f_clk / (5 * (divisor + 1)). O passo que libera SCL é seguido de um
-- passo que só avança quando a entrada i_scl, já sincronizada, vale '1', o que
-- trata o esticamento de clock pelo escravo. Os pinos são open-drain: o módulo
-- só diz quando puxar a linha para baixo (o_scl_low, o_sda_low).
--
-- Arbitragem: ao enviar um bit '1' (SDA solto) e ler SDA em '0', ao liberar SDA
-- antes de um início ou de uma parada e ler '0', o mestre perdeu o barramento,
-- solta as duas linhas e encerra o comando com o pulso o_arb_lost.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;

entity i2c_core is
    port (
        -- Clock do módulo.
        i_clk         : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst         : in    std_logic;
        -- Mestre ligado; em '0' as linhas ficam soltas e o comando é abandonado.
        i_enable      : in    std_logic;
        -- Pulso que abandona o comando em curso e solta as linhas.
        i_abort       : in    std_logic;
        -- Divisor do passo: um passo dura i_divider + 1 ciclos de i_clk.
        i_divider     : in    std_logic_vector(15 downto 0);
        -- Pulso que carrega o comando (só com o_busy em '0').
        i_cmd_valid   : in    std_logic;
        -- Comando com condição de início.
        i_cmd_start   : in    std_logic;
        -- Comando com condição de parada ao final.
        i_cmd_stop    : in    std_logic;
        -- Comando de recepção de um byte.
        i_cmd_read    : in    std_logic;
        -- Comando de envio de um byte.
        i_cmd_write   : in    std_logic;
        -- Resposta do mestre ao byte recebido: '1' envia NACK.
        i_cmd_nack    : in    std_logic;
        -- Byte a enviar.
        i_tx_data     : in    std_logic_vector(7 downto 0);
        -- Linha SCL sincronizada.
        i_scl         : in    std_logic;
        -- Linha SDA sincronizada.
        i_sda         : in    std_logic;
        -- Comando em execução.
        o_busy        : out   std_logic;
        -- O mestre gerou um início e ainda não gerou a parada.
        o_bus_active  : out   std_logic;
        -- Pulso de um ciclo no fim de um comando (com sucesso ou por arbitragem perdida).
        o_done        : out   std_logic;
        -- Pulso de um ciclo quando o byte enviado recebeu NACK.
        o_nack        : out   std_logic;
        -- Pulso de um ciclo quando a arbitragem foi perdida.
        o_arb_lost    : out   std_logic;
        -- Último byte recebido.
        o_rx_data     : out   std_logic_vector(7 downto 0);
        -- Puxa SCL para baixo quando '1'.
        o_scl_low     : out   std_logic;
        -- Puxa SDA para baixo quando '1'.
        o_sda_low     : out   std_logic
    );
end entity i2c_core;

architecture rtl of i2c_core is

    -- Fases de um comando.
    type state_t is (S_IDLE, S_START, S_BYTE, S_STOP);

    -- Fase atual.
    signal state      : state_t;
    -- Passo dentro da fase.
    signal step       : natural range 0 to 15;
    -- Índice do bit do byte (0 a 7 dados, 8 é o ACK).
    signal bit_idx    : natural range 0 to 8;
    -- Contador do divisor.
    signal count      : unsigned(15 downto 0);
    -- Pulso de passo.
    signal tick       : std_logic;
    -- Comando em execução.
    signal busy       : std_logic;
    -- Comando carregado: início.
    signal cmd_start  : std_logic;
    -- Comando carregado: parada.
    signal cmd_stop   : std_logic;
    -- Comando carregado: recepção.
    signal cmd_read   : std_logic;
    -- Comando carregado: envio.
    signal cmd_write  : std_logic;
    -- Comando carregado: NACK na resposta.
    signal cmd_nack   : std_logic;
    -- Registrador de deslocamento do byte.
    signal shift_reg  : std_logic_vector(7 downto 0);
    -- Último byte recebido.
    signal rx_data    : std_logic_vector(7 downto 0);
    -- Estado interno de SCL puxado para baixo.
    signal scl_low    : std_logic;
    -- Estado interno de SDA puxado para baixo.
    signal sda_low    : std_logic;
    -- O mestre está entre um início e uma parada.
    signal bus_active : std_logic;
    -- Pulso de fim de comando.
    signal done_pulse : std_logic;
    -- Pulso de NACK.
    signal nack_pulse : std_logic;
    -- Pulso de arbitragem perdida.
    signal arb_pulse  : std_logic;

    -- Fase que segue ao fim de início ou de byte, conforme o comando.
    function next_state (
        cur   : state_t;
        read  : std_logic;
        write : std_logic;
        stop  : std_logic
    ) return state_t is
    begin

        if cur = S_START and (read = '1' or write = '1') then
            return S_BYTE;
        elsif cur /= S_STOP and stop = '1' then
            return S_STOP;
        end if;

        return S_IDLE;

    end function next_state;

begin

    tick         <= '1' when busy = '1' and count >= unsigned(i_divider) else '0';
    o_busy       <= busy;
    o_bus_active <= bus_active;
    o_done       <= done_pulse;
    o_nack       <= nack_pulse;
    o_arb_lost   <= arb_pulse;
    o_rx_data    <= rx_data;
    o_scl_low    <= scl_low;
    o_sda_low    <= sda_low;

    -- Contador do divisor, parado quando não há comando.
    p_count : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            if busy = '0' or tick = '1' then
                count <= (others => '0');
            else
                count <= count + 1;
            end if;
        end if;

    end process p_count;

    -- Máquina de estados de linha.
    p_fsm : process (i_clk) is

        -- A fase atual terminou.
        variable v_finish : boolean;
        -- A arbitragem foi perdida neste passo.
        variable v_lose   : boolean;

    begin

        if rising_edge(i_clk) then
            done_pulse <= '0';
            nack_pulse <= '0';
            arb_pulse  <= '0';
            v_finish   := false;
            v_lose     := false;

            if i_rst = '1' or i_abort = '1' or i_enable = '0' then
                state      <= S_IDLE;
                step       <= 0;
                bit_idx    <= 0;
                busy       <= '0';
                scl_low    <= '0';
                sda_low    <= '0';
                bus_active <= '0';
                if i_rst = '1' then
                    rx_data   <= (others => '0');
                    cmd_start <= '0';
                    cmd_stop  <= '0';
                    cmd_read  <= '0';
                    cmd_write <= '0';
                    cmd_nack  <= '0';
                    shift_reg <= (others => '0');
                end if;
            else
                if i_cmd_valid = '1' and busy = '0' then
                    busy      <= '1';
                    cmd_start <= i_cmd_start;
                    cmd_stop  <= i_cmd_stop;
                    cmd_read  <= i_cmd_read;
                    cmd_write <= i_cmd_write;
                    cmd_nack  <= i_cmd_nack;
                    shift_reg <= i_tx_data;
                end if;

                if tick = '1' then

                    case state is

                        when S_IDLE =>
                            step    <= 0;
                            bit_idx <= 0;
                            if cmd_start = '1' then
                                state <= S_START;
                            elsif cmd_read = '1' or cmd_write = '1' then
                                state <= S_BYTE;
                            else
                                state <= S_STOP;
                            end if;

                        when S_START =>
                            step <= step + 1;
                            case step is

                                when 0 =>
                                    sda_low <= '0';
                                when 2 =>
                                    scl_low <= '0';
                                when 3 =>
                                    if i_scl = '0' then
                                        step <= 3;
                                    end if;
                                when 4 =>
                                    if i_sda = '0' then
                                        v_lose := true;
                                    end if;
                                when 5 =>
                                    sda_low    <= '1';
                                    bus_active <= '1';
                                when 8 =>
                                    scl_low  <= '1';
                                    v_finish := true;
                                when others =>
                                    null;

                            end case;

                        when S_BYTE =>
                            step <= step + 1;
                            case step is

                                when 0 =>
                                    if cmd_write = '1' and bit_idx < 8 then
                                        sda_low <= not shift_reg(7);
                                    elsif cmd_read = '1' and bit_idx = 8 then
                                        sda_low <= not cmd_nack;
                                    else
                                        sda_low <= '0';
                                    end if;
                                when 2 =>
                                    scl_low <= '0';
                                when 3 =>
                                    if i_scl = '0' then
                                        step <= 3;
                                    elsif cmd_write = '1' and bit_idx < 8 and sda_low = '0' and i_sda = '0' then
                                        v_lose := true;
                                    else
                                        if cmd_write = '1' and bit_idx = 8 and i_sda = '1' then
                                            nack_pulse <= '1';
                                        end if;
                                        if cmd_read = '1' and bit_idx < 8 then
                                            shift_reg <= shift_reg(6 downto 0) & i_sda;
                                        end if;
                                    end if;
                                when 4 =>
                                    scl_low <= '1';
                                    step    <= 0;
                                    if bit_idx = 8 then
                                        if cmd_read = '1' then
                                            rx_data <= shift_reg;
                                        end if;
                                        v_finish := true;
                                    else
                                        bit_idx <= bit_idx + 1;
                                        if cmd_write = '1' then
                                            shift_reg <= shift_reg(6 downto 0) & '0';
                                        end if;
                                    end if;
                                when others =>
                                    null;

                            end case;

                        when S_STOP =>
                            step <= step + 1;
                            case step is

                                when 0 =>
                                    sda_low <= '1';
                                when 2 =>
                                    scl_low <= '0';
                                when 3 =>
                                    if i_scl = '0' then
                                        step <= 3;
                                    end if;
                                when 6 =>
                                    sda_low <= '0';
                                when 7 =>
                                    if i_sda = '0' then
                                        v_lose := true;
                                    else
                                        bus_active <= '0';
                                        v_finish   := true;
                                    end if;
                                when others =>
                                    null;

                            end case;

                    end case;

                    if v_lose then
                        state      <= S_IDLE;
                        step       <= 0;
                        bit_idx    <= 0;
                        busy       <= '0';
                        scl_low    <= '0';
                        sda_low    <= '0';
                        bus_active <= '0';
                        arb_pulse  <= '1';
                        done_pulse <= '1';
                    elsif v_finish then
                        step    <= 0;
                        bit_idx <= 0;
                        state   <= next_state(state, cmd_read, cmd_write, cmd_stop);
                        if next_state(state, cmd_read, cmd_write, cmd_stop) = S_IDLE then
                            busy       <= '0';
                            done_pulse <= '1';
                        end if;
                    end if;
                end if;
            end if;
        end if;

    end process p_fsm;

end architecture rtl;
