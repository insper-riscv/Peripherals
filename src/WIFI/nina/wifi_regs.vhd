-- =============================================================================
-- Registradores de controle do módulo Wi-Fi NINA
--
-- Cuida dos pinos de controle do módulo que não são de dados: a linha de reset
-- (ativa em baixo), o pino GPIO0 que, mantido em baixo durante o reset, faz o
-- módulo entrar no modo de gravação do firmware, e a entrada ACK que o
-- módulo usa para avisar o mestre SPI de que terminou de preparar uma
-- resposta. A entrada passa por um sincronizador de dois estágios, as bordas
-- de subida e de descida ficam marcadas até o software limpá-las e cada uma
-- tem a sua máscara de interrupção.
--
-- O módulo fica em reset até o software soltar RUN (a menos que run_at_reset
-- seja verdadeiro). Um pulso de reset (RESET_PULSE) segura a linha em baixo por
-- reset_pulse_cycles ciclos e a devolve a RUN; o pino GPIO0 é sempre decidido
-- antes, pelo software, de modo que o módulo vê o nível certo quando o reset
-- termina. A saída de GPIO0 é um par (valor, habilitação), com o valor sempre
-- em baixo, de modo que o pino só puxa para baixo e solta o resto.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.config_pkg.all;
use work.utils_pkg.all;
use work.wifi_consts.all;

entity wifi_regs is
    generic (
        -- Ciclos de clock de um pulso de reset.
        reset_pulse_cycles : positive := 500_000;
        -- Módulo fora de reset logo depois do reset do sistema.
        run_at_reset       : boolean  := false
    );
    port (
        -- Clock do sistema.
        i_clk          : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst          : in    std_logic;
        -- Pulso de escrita do processador.
        i_write        : in    std_logic;
        -- Endereço de palavra dentro do bloco.
        i_address      : in    std_logic_vector(CTRL_ADDR_WIDTH - 1 downto 0);
        -- Dado de escrita vindo do processador.
        i_data_in      : in    word_t;
        -- Dado de leitura para o processador.
        o_data_out     : out   word_t;
        -- Requisição de interrupção de nível, ativa em '1'.
        o_irq          : out   std_logic;
        -- Pino ACK do módulo, assíncrono.
        i_wm_ack       : in    std_logic;
        -- Reset do módulo, ativo em '0'.
        o_wm_reset_n   : out   std_logic;
        -- Valor do pino GPIO0 do módulo, sempre em baixo, válido com a habilitação.
        o_wm_gpio0     : out   std_logic;
        -- Habilitação do driver de GPIO0, '1' enquanto o software força o modo de gravação.
        o_wm_gpio0_oe  : out   std_logic
    );
end entity wifi_regs;

architecture rtl of wifi_regs is

    -- Módulo fora de reset.
    signal run         : std_logic                                       := to_sl(run_at_reset);
    -- GPIO0 forçado em baixo.
    signal boot_low    : std_logic                                       := '0';
    -- Máscara da interrupção de borda de subida de ACK.
    signal rise_irq    : std_logic                                       := '0';
    -- Máscara da interrupção de borda de descida de ACK.
    signal fall_irq    : std_logic                                       := '0';
    -- Borda de subida de ACK vista.
    signal rise_flag   : std_logic                                       := '0';
    -- Borda de descida de ACK vista.
    signal fall_flag   : std_logic                                       := '0';
    -- ACK sincronizado.
    signal ack_sync    : std_logic_vector(0 downto 0);
    -- ACK do ciclo anterior.
    signal ack_prev    : std_logic                                       := '0';
    -- Ciclos que faltam ao pulso de reset.
    signal pulse_left  : natural range 0 to reset_pulse_cycles           := 0;
    -- Pulso de reset em curso.
    signal pulse_busy  : std_logic;
    -- Endereço de palavra do acesso.
    signal addr_idx    : natural range 0 to 2 ** CTRL_ADDR_WIDTH - 1;
    -- Borda de subida neste ciclo.
    signal rise_event  : std_logic;
    -- Borda de descida neste ciclo.
    signal fall_event  : std_logic;

begin

    u_ack_sync : entity work.synchronizer
        generic map (
            stages     => 2,
            data_width => 1
        )
        port map (
            i_clk => i_clk,
            i_rst => '0',
            i_d   => (0 => i_wm_ack),
            o_d   => ack_sync
        );

    addr_idx      <= to_integer(unsigned(i_address));
    pulse_busy    <= '1' when pulse_left /= 0 else
                     '0';
    rise_event    <= ack_sync(0) and not ack_prev;
    fall_event    <= ack_prev and not ack_sync(0);
    o_wm_reset_n  <= run and not pulse_busy;
    o_wm_gpio0    <= '0';
    o_wm_gpio0_oe <= boot_low;
    o_irq         <= (rise_irq and rise_flag) or (fall_irq and fall_flag);

    -- Leitura combinacional dos registradores.
    p_read : process (all) is
    begin

        o_data_out <= (others => '0');

        case addr_idx is
            when ADDR_CTRL =>
                o_data_out(CTRL_RUN_BIT)      <= run;
                o_data_out(CTRL_BOOT_LOW_BIT) <= boot_low;
                o_data_out(CTRL_RISE_IRQ_BIT) <= rise_irq;
                o_data_out(CTRL_FALL_IRQ_BIT) <= fall_irq;
            when ADDR_STATUS =>
                o_data_out(STATUS_ACK_BIT)   <= ack_sync(0);
                o_data_out(STATUS_RISE_BIT)  <= rise_flag;
                o_data_out(STATUS_FALL_BIT)  <= fall_flag;
                o_data_out(STATUS_PULSE_BIT) <= pulse_busy;
            when ADDR_RESET_PULSE =>
                o_data_out(PULSE_START_BIT) <= pulse_busy;
            when others =>
                null;
        end case;

    end process p_read;

    p_write : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            ack_prev <= ack_sync(0);

            if rise_event = '1' then
                rise_flag <= '1';
            end if;

            if fall_event = '1' then
                fall_flag <= '1';
            end if;

            if pulse_left /= 0 then
                pulse_left <= pulse_left - 1;
            end if;

            if i_write = '1' then
                case addr_idx is
                    when ADDR_CTRL =>
                        run       <= i_data_in(CTRL_RUN_BIT);
                        boot_low  <= i_data_in(CTRL_BOOT_LOW_BIT);
                        rise_irq  <= i_data_in(CTRL_RISE_IRQ_BIT);
                        fall_irq  <= i_data_in(CTRL_FALL_IRQ_BIT);
                    when ADDR_STATUS =>
                        if i_data_in(STATUS_RISE_BIT) = '1' and rise_event = '0' then
                            rise_flag <= '0';
                        end if;

                        if i_data_in(STATUS_FALL_BIT) = '1' and fall_event = '0' then
                            fall_flag <= '0';
                        end if;
                    when ADDR_RESET_PULSE =>
                        if i_data_in(PULSE_START_BIT) = '1' then
                            pulse_left <= reset_pulse_cycles;
                        end if;
                    when others =>
                        null;
                end case;
            end if;

            if i_rst = '1' then
                run        <= to_sl(run_at_reset);
                boot_low   <= '0';
                rise_irq   <= '0';
                fall_irq   <= '0';
                rise_flag  <= '0';
                fall_flag  <= '0';
                pulse_left <= 0;
            end if;
        end if;

    end process p_write;

end architecture rtl;
