-- =============================================================================
-- Controlador do módulo LCD alfanumérico 16x2 (HD44780) da DE2-115
-- =============================================================================
-- Liga o processador ao barramento paralelo de 8 bits do LCD (LCD_DATA, LCD_RS,
-- LCD_RW, LCD_EN, LCD_ON e LCD_BLON). O software escreve comandos e dados em
-- registradores; uma fila de escrita absorve a rajada e a camada física gera a
-- temporização do barramento e espera o chip terminar cada operação. Uma
-- sequência de inicialização em hardware, opcional, roda depois do reset e
-- segura a fila até terminar.
--
-- Pinos de dados: par de saída e habilitação (o_lcd_data, o_lcd_data_oe) mais a
-- entrada i_lcd_data, para a camada de três estados do topo da placa. Só o bit 7
-- da entrada é lido (flag de ocupado), por um sincronizador de dois estágios.
--
-- Mapa de registradores, em endereços de palavra:
--
--   0 COMMAND     W      bits 7:0, byte enfileirado com RS = 0
--   1 DATA        W      bits 7:0, byte enfileirado com RS = 1
--   2 STATUS      R/W1C  bit 0 BUSY, 1 FIFO_FULL, 2 FIFO_EMPTY, 3 INIT_BUSY,
--                        4 DROPPED, 5 TIMEOUT, 15:8 FIFO_LEVEL
--   3 CONTROL     R/W    bit 0 EMPTY_IRQ_ENABLE, 1 POLL_ENABLE, 2 LCD_ON,
--                        3 BACKLIGHT_ON
--   4 DELAY       R/W    bits 23:0, ciclos de espera dos comandos comuns
--   5 DELAY_LONG  R/W    bits 23:0, ciclos de espera de limpar e início
--
-- O topo só instancia e conecta as partes.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.lcd_consts.all;

entity lcd is
    generic (
        -- Largura do barramento de dados em bits.
        data_width       : natural  := 32;
        -- Frequência do clock em hertz.
        clk_freq_hz      : positive := 50000000;
        -- Profundidade da fila de escrita.
        fifo_depth       : positive := 16;
        -- Verdadeiro quando o pino RW da placa é ligado ao periférico.
        has_rw           : boolean  := true;
        -- Liga a sequência de inicialização em hardware depois do reset.
        auto_init        : boolean  := false;
        -- Tempo de setup de RS, RW e dado antes de EN, em nanossegundos.
        setup_ns         : natural  := 100;
        -- Tempo de EN alto, em nanossegundos.
        pulse_ns         : natural  := 300;
        -- Tempo de hold de RS, RW e dado depois de EN, em nanossegundos.
        hold_ns          : natural  := 100;
        -- Espera de energização antes da inicialização, em microssegundos.
        power_up_us      : natural  := 20000;
        -- Atraso de reset de um comando comum, em microssegundos.
        exec_us          : natural  := 50;
        -- Atraso de reset de limpar e início, em microssegundos.
        exec_long_us     : natural  := 2000;
        -- Tempo limite da espera pelo flag de ocupado, em microssegundos.
        busy_timeout_us  : natural  := 10000
    );
    port (
        -- Clock do módulo.
        i_clk         : in    std_logic;
        -- Reset síncrono, ativo em nível alto.
        i_rst         : in    std_logic;
        -- Dado de escrita vindo do processador.
        i_data_in     : in    std_logic_vector(data_width - 1 downto 0);
        -- Endereço de palavra do registrador, entre zero e cinco.
        i_address     : in    std_logic_vector(2 downto 0);
        -- Pulso de escrita do processador.
        i_write       : in    std_logic;
        -- Pulso de leitura do processador (a leitura não tem efeito colateral).
        i_read        : in    std_logic;
        -- Dado de leitura devolvido ao processador.
        o_data_out    : out   std_logic_vector(data_width - 1 downto 0);
        -- Requisição de interrupção de nível (fila de escrita vazia).
        o_irq         : out   std_logic;
        -- Entrada dos pinos LCD_DATA, da camada de três estados.
        i_lcd_data    : in    std_logic_vector(7 downto 0);
        -- Saída dos pinos LCD_DATA.
        o_lcd_data    : out   std_logic_vector(7 downto 0);
        -- Habilitação do driver dos pinos LCD_DATA.
        o_lcd_data_oe : out   std_logic;
        -- Pino LCD_RS.
        o_lcd_rs      : out   std_logic;
        -- Pino LCD_RW (sempre baixo sem has_rw).
        o_lcd_rw      : out   std_logic;
        -- Pino LCD_EN.
        o_lcd_en      : out   std_logic;
        -- Pino LCD_ON.
        o_lcd_on      : out   std_logic;
        -- Pino LCD_BLON.
        o_lcd_blon    : out   std_logic
    );
end entity lcd;

architecture rtl of lcd is

    -- Atraso de reset de DELAY, em ciclos.
    constant DELAY_RESET      : positive := us_to_cycles(exec_us, clk_freq_hz);
    -- Atraso de reset de DELAY_LONG, em ciclos.
    constant DELAY_LONG_RESET : positive := us_to_cycles(exec_long_us, clk_freq_hz);

    -- Pedido de inserção vindo dos registradores.
    signal push            : std_logic;
    -- RS da palavra a inserir.
    signal push_rs         : std_logic;
    -- Byte da palavra a inserir.
    signal push_data       : std_logic_vector(7 downto 0);
    -- Palavra de nove bits (RS e byte) a inserir.
    signal push_word       : std_logic_vector(8 downto 0);
    -- Palavra mais antiga da fila.
    signal head_word       : std_logic_vector(8 downto 0);
    -- A fila aceitou a inserção.
    signal push_accepted   : std_logic;
    -- A fila está cheia.
    signal fifo_full       : std_logic;
    -- A fila está vazia.
    signal fifo_empty      : std_logic;
    -- Quantidade de palavras na fila.
    signal fifo_level      : natural range 0 to fifo_depth;
    -- Remoção da palavra mais antiga.
    signal fifo_pop        : std_logic;

    -- A camada física está ocupada.
    signal phy_busy        : std_logic;
    -- A camada física está livre.
    signal phy_ready       : std_logic;
    -- Pulso de tempo limite da camada física.
    signal phy_timeout     : std_logic;
    -- Pedido de operação à camada física.
    signal phy_start       : std_logic;
    -- RS da operação.
    signal phy_rs          : std_logic;
    -- Byte da operação.
    signal phy_data        : std_logic_vector(7 downto 0);
    -- Espera pelo flag de ocupado na operação.
    signal phy_poll        : std_logic;
    -- Atraso da operação.
    signal phy_delay       : std_logic_vector(DELAY_BITS - 1 downto 0);
    -- Bit 7 do dado do chip sincronizado.
    signal busy_flag       : std_logic_vector(0 downto 0);

    -- A inicialização está em andamento.
    signal init_busy       : std_logic;
    -- Pedido de operação da inicialização.
    signal init_start      : std_logic;
    -- Byte do comando da inicialização.
    signal init_data       : std_logic_vector(7 downto 0);
    -- Atraso do comando da inicialização.
    signal init_delay      : std_logic_vector(DELAY_BITS - 1 downto 0);

    -- Espera pelo flag de ocupado habilitada nos registradores.
    signal poll_enable     : std_logic;
    -- Atraso dos comandos comuns.
    signal reg_delay       : std_logic_vector(DELAY_BITS - 1 downto 0);
    -- Atraso dos comandos lentos.
    signal reg_delay_long  : std_logic_vector(DELAY_BITS - 1 downto 0);

begin

    phy_busy  <= not phy_ready;
    push_word <= push_rs & push_data;
    fifo_pop  <= '1' when phy_ready = '1' and fifo_empty = '0' and init_busy = '0' else '0';

    phy_start <= init_start when init_busy = '1' else fifo_pop;
    phy_rs    <= '0' when init_busy = '1' else head_word(8);
    phy_data  <= init_data when init_busy = '1' else head_word(7 downto 0);
    phy_poll  <= '0' when init_busy = '1' else poll_enable;

    phy_delay <= init_delay when init_busy = '1' else
                 reg_delay_long when is_slow_command(head_word(8), head_word(7 downto 0)) else
                 reg_delay;

    u_regs : entity work.lcd_regs
        generic map (
            data_width       => data_width,
            fifo_depth       => fifo_depth,
            has_rw           => has_rw,
            delay_reset      => DELAY_RESET,
            delay_long_reset => DELAY_LONG_RESET
        )
        port map (
            i_clk           => i_clk,
            i_rst           => i_rst,
            i_data_in       => i_data_in,
            i_address       => i_address,
            i_write         => i_write,
            o_data_out      => o_data_out,
            o_irq           => o_irq,
            o_push          => push,
            o_push_rs       => push_rs,
            o_push_data     => push_data,
            i_push_accepted => push_accepted,
            i_fifo_full     => fifo_full,
            i_fifo_empty    => fifo_empty,
            i_fifo_level    => fifo_level,
            i_phy_busy      => phy_busy,
            i_init_busy     => init_busy,
            i_timeout       => phy_timeout,
            o_poll_enable   => poll_enable,
            o_delay         => reg_delay,
            o_delay_long    => reg_delay_long,
            o_lcd_on        => o_lcd_on,
            o_lcd_blon      => o_lcd_blon
        );

    u_fifo : entity work.uart_fifo
        generic map (
            data_width => 9,
            depth      => fifo_depth
        )
        port map (
            i_clk           => i_clk,
            i_rst           => i_rst,
            i_push          => push,
            i_push_data     => push_word,
            i_pop           => fifo_pop,
            o_pop_data      => head_word,
            o_push_accepted => push_accepted,
            o_pop_accepted  => open,
            o_full          => fifo_full,
            o_empty         => fifo_empty,
            o_level         => fifo_level
        );

    u_init : entity work.lcd_init
        generic map (
            clk_freq_hz  => clk_freq_hz,
            enabled      => auto_init,
            power_up_us  => power_up_us,
            exec_us      => exec_us,
            exec_long_us => exec_long_us
        )
        port map (
            i_clk       => i_clk,
            i_rst       => i_rst,
            i_phy_ready => phy_ready,
            o_start     => init_start,
            o_data      => init_data,
            o_delay     => init_delay,
            o_busy      => init_busy
        );

    u_busy_sync : entity work.synchronizer
        generic map (
            stages     => 2,
            data_width => 1
        )
        port map (
            i_clk => i_clk,
            i_rst => i_rst,
            i_d   => i_lcd_data(7 downto 7),
            o_d   => busy_flag
        );

    u_phy : entity work.lcd_phy
        generic map (
            setup_cycles   => ns_to_cycles(setup_ns, clk_freq_hz),
            pulse_cycles   => ns_to_cycles(pulse_ns, clk_freq_hz),
            hold_cycles    => ns_to_cycles(hold_ns, clk_freq_hz),
            timeout_cycles => us_to_cycles(busy_timeout_us, clk_freq_hz),
            has_rw         => has_rw
        )
        port map (
            i_clk         => i_clk,
            i_rst         => i_rst,
            i_start       => phy_start,
            i_rs          => phy_rs,
            i_data        => phy_data,
            i_poll        => phy_poll,
            i_delay       => phy_delay,
            i_busy_flag   => busy_flag(0),
            o_ready       => phy_ready,
            o_timeout     => phy_timeout,
            o_lcd_rs      => o_lcd_rs,
            o_lcd_rw      => o_lcd_rw,
            o_lcd_en      => o_lcd_en,
            o_lcd_data    => o_lcd_data,
            o_lcd_data_oe => o_lcd_data_oe
        );

end architecture rtl;
