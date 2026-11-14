-- =============================================================================
-- Registradores do controlador do LCD 16x2
-- =============================================================================
-- Decodifica o barramento de palavras do periférico. A escrita em COMMAND ou em
-- DATA entrega um pedido de inserção à fila de escrita; a fila cheia descarta o
-- pedido e acende DROPPED. STATUS reúne os níveis e as flags (DROPPED e TIMEOUT
-- ficam acesos até a escrita de 1 no bit), CONTROL guarda a interrupção, o modo
-- de espera e os pinos LCD_ON e LCD_BLON, e DELAY e DELAY_LONG guardam os
-- atrasos usados quando a espera não lê o flag de ocupado. Os acessos
-- terminam em um ciclo e a leitura não tem efeito colateral.
-- Mapa, em endereços de palavra: 0 COMMAND, 1 DATA, 2 STATUS, 3 CONTROL,
-- 4 DELAY e 5 DELAY_LONG (ver lcd_consts).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.lcd_consts.all;

entity lcd_regs is
    generic (
        -- Largura do barramento de dados em bits.
        data_width       : natural  := 32;
        -- Profundidade da fila de escrita.
        fifo_depth       : positive := 16;
        -- Verdadeiro quando o pino RW da placa é ligado ao periférico.
        has_rw           : boolean  := true;
        -- Valor de reset de DELAY, em ciclos.
        delay_reset      : natural  := 2500;
        -- Valor de reset de DELAY_LONG, em ciclos.
        delay_long_reset : natural  := 100000
    );
    port (
        -- Clock do módulo.
        i_clk            : in    std_logic;
        -- Reset síncrono, ativo em nível alto.
        i_rst            : in    std_logic;
        -- Dado de escrita vindo do processador.
        i_data_in        : in    std_logic_vector(data_width - 1 downto 0);
        -- Endereço de palavra do registrador.
        i_address        : in    std_logic_vector(2 downto 0);
        -- Pulso de escrita do processador.
        i_write          : in    std_logic;
        -- Dado de leitura devolvido ao processador.
        o_data_out       : out   std_logic_vector(data_width - 1 downto 0);
        -- Requisição de interrupção de nível (fila de escrita vazia).
        o_irq            : out   std_logic;
        -- Pedido de inserção de uma palavra na fila de escrita.
        o_push           : out   std_logic;
        -- Valor de RS da palavra inserida.
        o_push_rs        : out   std_logic;
        -- Byte da palavra inserida.
        o_push_data      : out   std_logic_vector(7 downto 0);
        -- A fila aceitou a inserção pedida.
        i_push_accepted  : in    std_logic;
        -- A fila está cheia.
        i_fifo_full      : in    std_logic;
        -- A fila está vazia.
        i_fifo_empty     : in    std_logic;
        -- Quantidade de palavras na fila.
        i_fifo_level     : in    natural range 0 to fifo_depth;
        -- Há operação em andamento no barramento do LCD.
        i_phy_busy       : in    std_logic;
        -- A inicialização em hardware está em andamento.
        i_init_busy      : in    std_logic;
        -- Pulso de flag de ocupado que não baixou a tempo.
        i_timeout        : in    std_logic;
        -- Espera pelo flag de ocupado em vez de um atraso fixo.
        o_poll_enable    : out   std_logic;
        -- Atraso dos comandos comuns, em ciclos.
        o_delay          : out   std_logic_vector(DELAY_BITS - 1 downto 0);
        -- Atraso dos comandos lentos, em ciclos.
        o_delay_long     : out   std_logic_vector(DELAY_BITS - 1 downto 0);
        -- Nível do pino LCD_ON.
        o_lcd_on         : out   std_logic;
        -- Nível do pino LCD_BLON.
        o_lcd_blon       : out   std_logic
    );
end entity lcd_regs;

architecture rtl of lcd_regs is

    -- Valor de reset do bit de espera pelo flag de ocupado.
    function poll_reset return std_logic is
    begin

        if has_rw then
            return '1';
        end if;

        return '0';

    end function poll_reset;

    -- Habilitação da interrupção de fila vazia.
    signal irq_enable  : std_logic;
    -- Espera pelo flag de ocupado habilitada.
    signal poll_enable : std_logic;
    -- Nível do pino LCD_ON.
    signal lcd_on      : std_logic;
    -- Nível do pino LCD_BLON.
    signal lcd_blon    : std_logic;
    -- Erro persistente de escrita com a fila cheia.
    signal dropped     : std_logic;
    -- Erro persistente de flag de ocupado que não baixou.
    signal timed_out   : std_logic;
    -- Atraso dos comandos comuns.
    signal delay_reg   : unsigned(DELAY_BITS - 1 downto 0);
    -- Atraso dos comandos lentos.
    signal delay_long  : unsigned(DELAY_BITS - 1 downto 0);
    -- Pedido de inserção decodificado.
    signal push        : std_logic;

begin

    assert data_width >= DELAY_BITS
        report "lcd data_width must be at least DELAY_BITS"
        severity failure;

    assert fifo_depth < 2 ** LEVEL_BITS
        report "lcd fifo_depth must fit in the 8-bit level field"
        severity failure;

    push <= '1' when i_write = '1' and (i_address = COMMAND_ADDRESS or i_address = DATA_ADDRESS) else '0';

    o_push        <= push;
    o_push_rs     <= '1' when i_address = DATA_ADDRESS else '0';
    o_push_data   <= i_data_in(7 downto 0);
    o_poll_enable <= poll_enable;
    o_delay       <= std_logic_vector(delay_reg);
    o_delay_long  <= std_logic_vector(delay_long);
    o_lcd_on      <= lcd_on;
    o_lcd_blon    <= lcd_blon;
    o_irq         <= irq_enable and i_fifo_empty and not i_init_busy;

    p_registers : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            if i_rst = '1' then
                irq_enable  <= '0';
                poll_enable <= poll_reset;
                lcd_on      <= '1';
                lcd_blon    <= '0';
                dropped     <= '0';
                timed_out   <= '0';
                delay_reg   <= to_unsigned(delay_reset, DELAY_BITS);
                delay_long  <= to_unsigned(delay_long_reset, DELAY_BITS);
            else
                if i_write = '1' and i_address = CONTROL_ADDRESS then
                    irq_enable <= i_data_in(CONTROL_IRQ_ENABLE);
                    if has_rw then
                        poll_enable <= i_data_in(CONTROL_POLL_ENABLE);
                    end if;
                    lcd_on   <= i_data_in(CONTROL_LCD_ON);
                    lcd_blon <= i_data_in(CONTROL_BACKLIGHT);
                end if;

                if i_write = '1' and i_address = DELAY_ADDRESS then
                    delay_reg <= unsigned(i_data_in(DELAY_BITS - 1 downto 0));
                end if;

                if i_write = '1' and i_address = DELAY_LONG_ADDRESS then
                    delay_long <= unsigned(i_data_in(DELAY_BITS - 1 downto 0));
                end if;

                -- Os eventos novos têm prioridade sobre uma limpeza simultânea.
                if i_write = '1' and i_address = STATUS_ADDRESS then
                    if i_data_in(STATUS_DROPPED) = '1' then
                        dropped <= '0';
                    end if;
                    if i_data_in(STATUS_TIMEOUT) = '1' then
                        timed_out <= '0';
                    end if;
                end if;

                if push = '1' and i_push_accepted = '0' then
                    dropped <= '1';
                end if;

                if i_timeout = '1' then
                    timed_out <= '1';
                end if;
            end if;
        end if;

    end process p_registers;

    p_readback : process (
                          i_address, i_fifo_full, i_fifo_empty, i_fifo_level, i_phy_busy, i_init_busy,
                          irq_enable, poll_enable, lcd_on, lcd_blon, dropped, timed_out, delay_reg, delay_long
                         ) is

        -- Valor montado para o registrador selecionado.
        variable value : std_logic_vector(data_width - 1 downto 0);

    begin

        value := (others => '0');

        case i_address is

            when STATUS_ADDRESS =>

                value(STATUS_BUSY)       := i_phy_busy or i_init_busy or not i_fifo_empty;
                value(STATUS_FIFO_FULL)  := i_fifo_full;
                value(STATUS_FIFO_EMPTY) := i_fifo_empty;
                value(STATUS_INIT_BUSY)  := i_init_busy;
                value(STATUS_DROPPED)    := dropped;
                value(STATUS_TIMEOUT)    := timed_out;
                value(STATUS_LEVEL_LOW + LEVEL_BITS - 1 downto STATUS_LEVEL_LOW) :=
                    std_logic_vector(to_unsigned(i_fifo_level, LEVEL_BITS));

            when CONTROL_ADDRESS =>

                value(CONTROL_IRQ_ENABLE)  := irq_enable;
                value(CONTROL_POLL_ENABLE) := poll_enable;
                value(CONTROL_LCD_ON)      := lcd_on;
                value(CONTROL_BACKLIGHT)   := lcd_blon;

            when DELAY_ADDRESS =>

                value(DELAY_BITS - 1 downto 0) := std_logic_vector(delay_reg);

            when DELAY_LONG_ADDRESS =>

                value(DELAY_BITS - 1 downto 0) := std_logic_vector(delay_long);

            when others =>

                null;

        end case;

        o_data_out <= value;

    end process p_readback;

end architecture rtl;
