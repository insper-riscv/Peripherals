-- =============================================================================
-- Mestre I2C de uso geral mapeado em memória
--
-- Liga o processador a um barramento I2C de dois fios (SCL e SDA, open-drain).
-- O processador escreve um comando (início, parada, envio ou recepção de um
-- byte) e acompanha o fim pelo bit de ocupado ou pela interrupção. A máquina de
-- linha fica em i2c_core; este topo guarda os registradores, decide se um
-- comando é aceito, mantém os bits de estado e sincroniza as entradas SCL e
-- SDA. Os pinos saem como par entrada e saída-baixa: o topo da plataforma liga
-- o tristate (linha em 'Z' quando o_*_low vale '0', em '0' quando vale '1').
--
-- Frequência de SCL: f_scl = f_clk / (5 * (divisor + 1)). O divisor reinicia
-- em clk_freq / (5 * scl_freq) - 1.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.config_pkg.all;
use work.i2c_consts.all;

entity i2c_master is
    generic (
        -- Frequência de i_clk em Hz.
        clk_freq : positive := 100_000_000;
        -- Frequência de SCL em Hz que o divisor tem ao sair do reset (100 kHz padrão, 400 kHz no modo rápido).
        scl_freq : positive := 100_000
    );
    port (
        -- Clock do módulo.
        i_clk      : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst      : in    std_logic;
        -- Pulso de escrita do processador.
        i_write    : in    std_logic;
        -- Pulso de leitura do processador.
        i_read     : in    std_logic;
        -- Endereço de palavra do registrador.
        i_address  : in    std_logic_vector(I2C_ADDR_BITS - 1 downto 0);
        -- Dado de escrita do processador.
        i_data_in  : in    word_t;
        -- Dado de leitura para o processador (zero fora de uma leitura).
        o_data_out : out   word_t;
        -- Requisição de interrupção, ativa em '1'.
        o_irq      : out   std_logic;
        -- Puxa SCL para baixo quando '1' (o topo liga o tristate).
        o_scl_low  : out   std_logic;
        -- Puxa SDA para baixo quando '1' (o topo liga o tristate).
        o_sda_low  : out   std_logic;
        -- Nível lido do pino SCL.
        i_scl      : in    std_logic;
        -- Nível lido do pino SDA.
        i_sda      : in    std_logic
    );
end entity i2c_master;

architecture rtl of i2c_master is

    -- Divisor de reset calculado dos generics, nunca abaixo do mínimo aceito.
    function default_divider return natural is
        variable v_div : natural;
    begin

        v_div := clk_freq / (5 * scl_freq);
        if v_div < MIN_DIVIDER + 1 then
            return MIN_DIVIDER;
        end if;

        return v_div - 1;

    end function default_divider;

    -- Divisor de reset como vetor de 16 bits.
    constant RESET_DIVIDER : std_logic_vector(15 downto 0) := std_logic_vector(to_unsigned(default_divider, 16));

    -- Mestre ligado.
    signal ctrl_enable   : std_logic;
    -- Habilita a interrupção de fim de comando.
    signal irq_done_en   : std_logic;
    -- Habilita a interrupção de erro.
    signal irq_err_en    : std_logic;
    -- Divisor de clock.
    signal divider       : std_logic_vector(15 downto 0);
    -- Byte a transmitir.
    signal tx_data       : std_logic_vector(7 downto 0);
    -- Bit sticky de comando terminado.
    signal st_done       : std_logic;
    -- Bit sticky de NACK.
    signal st_nack       : std_logic;
    -- Bit sticky de arbitragem perdida.
    signal st_arb_lost   : std_logic;
    -- Bit sticky de comando recusado.
    signal st_rejected   : std_logic;
    -- Entradas SCL (bit 0) e SDA (bit 1) sincronizadas.
    signal bus_sync      : std_logic_vector(1 downto 0);
    -- Escrita no registrador de comando.
    signal cmd_write     : std_logic;
    -- O comando escrito é aceito.
    signal cmd_ok        : std_logic;
    -- Pulso de aborto.
    signal abort_pulse   : std_logic;
    -- Comando em execução.
    signal core_busy     : std_logic;
    -- Mestre entre início e parada.
    signal core_active   : std_logic;
    -- Fim de comando.
    signal core_done     : std_logic;
    -- NACK do byte enviado.
    signal core_nack     : std_logic;
    -- Arbitragem perdida.
    signal core_arb_lost : std_logic;
    -- Último byte recebido.
    signal core_rx       : std_logic_vector(7 downto 0);
    -- Palavra do registrador de estado.
    signal status_word   : word_t;
    -- Palavra lida no endereço atual.
    signal read_word     : word_t;

begin

    u_sync : entity work.synchronizer
        generic map (
            stages     => 2,
            data_width => 2
        )
        port map (
            i_clk => i_clk,
            i_rst => i_rst,
            i_d   => i_sda & i_scl,
            o_d   => bus_sync
        );

    cmd_write   <= i_write when i_address = ADDR_CMD else '0';
    abort_pulse <= i_write and i_data_in(CTRL_ABORT_BIT) when i_address = ADDR_CTRL else '0';

    -- Um comando exige o mestre ligado e livre, ao menos uma ação, não pede envio e recepção juntos e, sem
    -- início próprio, segue um início já dado.
    cmd_ok <= '1' when ctrl_enable = '1' and core_busy = '0'
                       and (i_data_in(CMD_START_BIT) = '1' or i_data_in(CMD_STOP_BIT) = '1'
                            or i_data_in(CMD_READ_BIT) = '1' or i_data_in(CMD_WRITE_BIT) = '1')
                       and not (i_data_in(CMD_READ_BIT) = '1' and i_data_in(CMD_WRITE_BIT) = '1')
                       and (i_data_in(CMD_START_BIT) = '1' or core_active = '1')
              else '0';

    u_core : entity work.i2c_core
        port map (
            i_clk        => i_clk,
            i_rst        => i_rst,
            i_enable     => ctrl_enable,
            i_abort      => abort_pulse,
            i_divider    => divider,
            i_cmd_valid  => cmd_write and cmd_ok,
            i_cmd_start  => i_data_in(CMD_START_BIT),
            i_cmd_stop   => i_data_in(CMD_STOP_BIT),
            i_cmd_read   => i_data_in(CMD_READ_BIT),
            i_cmd_write  => i_data_in(CMD_WRITE_BIT),
            i_cmd_nack   => i_data_in(CMD_NACK_BIT),
            i_tx_data    => tx_data,
            i_scl        => bus_sync(0),
            i_sda        => bus_sync(1),
            o_busy       => core_busy,
            o_bus_active => core_active,
            o_done       => core_done,
            o_nack       => core_nack,
            o_arb_lost   => core_arb_lost,
            o_rx_data    => core_rx,
            o_scl_low    => o_scl_low,
            o_sda_low    => o_sda_low
        );

    -- Registradores de configuração e bits sticky de estado.
    p_regs : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            if i_rst = '1' then
                ctrl_enable <= '0';
                irq_done_en <= '0';
                irq_err_en  <= '0';
                divider     <= RESET_DIVIDER;
                tx_data     <= (others => '0');
                st_done     <= '0';
                st_nack     <= '0';
                st_arb_lost <= '0';
                st_rejected <= '0';
            else
                -- Escrita em STATUS limpa os bits sticky em que vale '1'; um evento do mesmo ciclo prevalece.
                if i_write = '1' and i_address = ADDR_STATUS then
                    st_done     <= st_done and not i_data_in(ST_DONE_BIT);
                    st_nack     <= st_nack and not i_data_in(ST_NACK_BIT);
                    st_arb_lost <= st_arb_lost and not i_data_in(ST_ARB_LOST_BIT);
                    st_rejected <= st_rejected and not i_data_in(ST_REJECTED_BIT);
                end if;

                if core_done = '1' then
                    st_done <= '1';
                end if;
                if core_nack = '1' then
                    st_nack <= '1';
                end if;
                if core_arb_lost = '1' then
                    st_arb_lost <= '1';
                end if;
                if cmd_write = '1' and cmd_ok = '0' then
                    st_rejected <= '1';
                end if;

                if i_write = '1' then
                    case i_address is

                        when ADDR_CTRL =>
                            ctrl_enable <= i_data_in(CTRL_ENABLE_BIT);
                            irq_done_en <= i_data_in(CTRL_IRQ_DONE_BIT);
                            irq_err_en  <= i_data_in(CTRL_IRQ_ERR_BIT);
                        when ADDR_DIVIDER =>
                            if unsigned(i_data_in(15 downto 0)) < MIN_DIVIDER then
                                divider <= std_logic_vector(to_unsigned(MIN_DIVIDER, 16));
                            else
                                divider <= i_data_in(15 downto 0);
                            end if;
                        when ADDR_TX =>
                            tx_data <= i_data_in(7 downto 0);
                        when others =>
                            null;

                    end case;
                end if;
            end if;
        end if;

    end process p_regs;

    status_word(ST_BUSY_BIT)       <= core_busy or core_done;
    status_word(ST_BUS_ACTIVE_BIT) <= core_active;
    status_word(ST_DONE_BIT)       <= st_done;
    status_word(ST_NACK_BIT)       <= st_nack;
    status_word(ST_ARB_LOST_BIT)   <= st_arb_lost;
    status_word(ST_REJECTED_BIT)   <= st_rejected;
    status_word(word_t'high downto ST_REJECTED_BIT + 1) <= (others => '0');

    -- Leitura combinacional por endereço.
    p_read : process (all) is
    begin

        read_word <= (others => '0');
        case i_address is

            when ADDR_CTRL =>
                read_word(CTRL_ENABLE_BIT)   <= ctrl_enable;
                read_word(CTRL_IRQ_DONE_BIT) <= irq_done_en;
                read_word(CTRL_IRQ_ERR_BIT)  <= irq_err_en;
            when ADDR_DIVIDER =>
                read_word(15 downto 0) <= divider;
            when ADDR_TX =>
                read_word(7 downto 0) <= tx_data;
            when ADDR_RX =>
                read_word(7 downto 0) <= core_rx;
            when ADDR_STATUS =>
                read_word <= status_word;
            when others =>
                null;

        end case;

    end process p_read;

    o_data_out <= read_word when i_read = '1' else (others => '0');

    o_irq <= '1' when (st_done = '1' and irq_done_en = '1')
                      or ((st_nack = '1' or st_arb_lost = '1' or st_rejected = '1') and irq_err_en = '1')
             else '0';

end architecture rtl;
