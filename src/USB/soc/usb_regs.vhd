-- =============================================================================
-- Registradores da ponte paralela para o chip USB
--
-- Decodifica o barramento do SoC. As quatro primeiras palavras são as portas de
-- acesso ao chip: escrever numa delas pede uma escrita de 16 bits na porta
-- correspondente; ler uma delas pede uma leitura, cujo resultado aparece no
-- registrador de dado lido quando o estado deixa de indicar ocupado. Um pedido
-- feito com a ponte ocupada é descartado e marca o erro pegajoso do estado. O
-- restante são controle (reset do chip e reconhecimento de DMA), estado (níveis
-- das interrupções do chip, pedido de DMA, ocupado, erro), máscara de
-- interrupção e os três campos de temporização, que partem dos generics.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.config_pkg.all;
use work.usb_consts.all;

entity usb_regs is
    generic (
        -- Ciclos de preparação no reset (0 a 255; zero vale um ciclo).
        setup_cycles    : natural range 0 to 255 := 2;
        -- Ciclos do pulso de leitura ou escrita no reset (0 a 255; zero vale um ciclo).
        pulse_cycles    : natural range 0 to 255 := 6;
        -- Ciclos de recuperação no reset (0 a 255; zero vale um ciclo).
        recovery_cycles : natural range 0 to 255 := 4;
        -- As interrupções do chip são ativas em nível alto quando verdadeiro.
        int_active_high : boolean := true
    );
    port (
        -- Clock do módulo.
        i_clk      : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst      : in    std_logic;
        -- Dado de escrita vindo do processador.
        i_data_in  : in    word_t;
        -- Endereço de palavra acessado pelo processador.
        i_address  : in    std_logic_vector(USB_ADDR_BITS - 1 downto 0);
        -- Pulso de escrita do processador.
        i_write    : in    std_logic;
        -- Pulso de leitura do processador.
        i_read     : in    std_logic;
        -- Dado de leitura para o processador.
        o_data_out : out   word_t;
        -- Requisição de interrupção, ativa em '1'.
        o_irq      : out   std_logic;

        -- Pedido de acesso ao mestre do barramento.
        o_start    : out   std_logic;
        -- Tipo do acesso: '1' leitura, '0' escrita.
        o_is_read  : out   std_logic;
        -- Endereço do chip do acesso.
        o_port     : out   std_logic_vector(CHIP_ADDR_BITS - 1 downto 0);
        -- Dado a escrever no chip.
        o_wdata    : out   std_logic_vector(CHIP_DATA_BITS - 1 downto 0);
        -- Ciclos de preparação.
        o_setup    : out   std_logic_vector(TIMING_FIELD_BITS - 1 downto 0);
        -- Ciclos do pulso.
        o_pulse    : out   std_logic_vector(TIMING_FIELD_BITS - 1 downto 0);
        -- Ciclos de recuperação.
        o_recovery : out   std_logic_vector(TIMING_FIELD_BITS - 1 downto 0);
        -- O mestre está executando um acesso.
        i_busy     : in    std_logic;
        -- Último dado lido pelo mestre.
        i_rdata    : in    std_logic_vector(CHIP_DATA_BITS - 1 downto 0);

        -- Interrupções do chip, sincronizadas, na polaridade do pino.
        i_int      : in    std_logic_vector(1 downto 0);
        -- Pedido de DMA do controlador de dispositivo, sincronizado.
        i_dreq     : in    std_logic;
        -- Mantém o chip em reset.
        o_chip_reset : out   std_logic;
        -- Reconhecimento de DMA enviado ao chip.
        o_dack     : out   std_logic
    );
end entity usb_regs;

architecture rtl of usb_regs is

    -- Os endereços de palavra das quatro portas ocupam os valores abaixo deste.
    constant PORT_COUNT : natural := 4;

    -- Endereço de palavra como inteiro.
    signal addr_int    : natural range 0 to 2 ** USB_ADDR_BITS - 1;
    -- O endereço escolhe uma das portas de acesso ao chip.
    signal is_port     : std_logic;
    -- Pedido de acesso feito pelo processador neste ciclo.
    signal request     : std_logic;
    -- Interrupções do chip normalizadas para ativas em '1'.
    signal int_level   : std_logic_vector(1 downto 0);

    -- Controle: reset do chip.
    signal chip_reset  : std_logic;
    -- Controle: reconhecimento de DMA.
    signal dack        : std_logic;
    -- Erro pegajoso de acesso descartado.
    signal err         : std_logic;
    -- Máscara de interrupção.
    signal irq_mask    : std_logic_vector(1 downto 0);
    -- Campo de preparação.
    signal setup_reg   : std_logic_vector(TIMING_FIELD_BITS - 1 downto 0);
    -- Campo do pulso.
    signal pulse_reg   : std_logic_vector(TIMING_FIELD_BITS - 1 downto 0);
    -- Campo de recuperação.
    signal recovery_reg : std_logic_vector(TIMING_FIELD_BITS - 1 downto 0);

begin

    addr_int <= to_integer(unsigned(i_address));
    is_port  <= '1' when addr_int < PORT_COUNT else '0';
    request  <= (i_write or i_read) and is_port;

    int_level <= i_int when int_active_high else not i_int;

    o_start      <= request and not i_busy;
    o_is_read    <= i_read;
    o_port       <= i_address(CHIP_ADDR_BITS - 1 downto 0);
    o_wdata      <= i_data_in(CHIP_DATA_BITS - 1 downto 0);
    o_setup      <= setup_reg;
    o_pulse      <= pulse_reg;
    o_recovery   <= recovery_reg;
    o_chip_reset <= chip_reset;
    o_dack       <= dack;
    o_irq        <= '1' when (int_level and irq_mask) /= "00" else '0';

    process (i_clk) is
    begin
        if rising_edge(i_clk) then
            if i_rst = '1' then
                chip_reset   <= '1';
                dack         <= '0';
                err          <= '0';
                irq_mask     <= (others => '0');
                setup_reg    <= std_logic_vector(to_unsigned(setup_cycles, TIMING_FIELD_BITS));
                pulse_reg    <= std_logic_vector(to_unsigned(pulse_cycles, TIMING_FIELD_BITS));
                recovery_reg <= std_logic_vector(to_unsigned(recovery_cycles, TIMING_FIELD_BITS));
            else
                if request = '1' and i_busy = '1' then
                    err <= '1';
                end if;
                if i_write = '1' then
                    case addr_int is
                        when USB_ADDR_CTRL =>
                            chip_reset <= i_data_in(USB_CTRL_CHIP_RESET);
                            dack       <= i_data_in(USB_CTRL_DACK);
                        when USB_ADDR_STATUS =>
                            if i_data_in(USB_STATUS_ERROR) = '1' and not (request = '1' and i_busy = '1') then
                                err <= '0';
                            end if;
                        when USB_ADDR_IRQ_MASK =>
                            irq_mask <= i_data_in(1 downto 0);
                        when USB_ADDR_TIMING =>
                            setup_reg    <= i_data_in(TIMING_FIELD_BITS - 1 downto 0);
                            pulse_reg    <= i_data_in(2 * TIMING_FIELD_BITS - 1 downto TIMING_FIELD_BITS);
                            recovery_reg <= i_data_in(3 * TIMING_FIELD_BITS - 1 downto 2 * TIMING_FIELD_BITS);
                        when others =>
                            null;
                    end case;
                end if;
            end if;
        end if;
    end process;

    process (all) is
    begin
        o_data_out <= (others => '0');
        if i_read = '1' then
            case addr_int is
                when USB_ADDR_RDATA =>
                    o_data_out(CHIP_DATA_BITS - 1 downto 0) <= i_rdata;
                when USB_ADDR_CTRL =>
                    o_data_out(USB_CTRL_CHIP_RESET) <= chip_reset;
                    o_data_out(USB_CTRL_DACK)       <= dack;
                when USB_ADDR_STATUS =>
                    o_data_out(USB_STATUS_INT1 downto USB_STATUS_INT0) <= int_level;
                    o_data_out(USB_STATUS_DREQ)  <= i_dreq;
                    o_data_out(USB_STATUS_BUSY)  <= i_busy;
                    o_data_out(USB_STATUS_ERROR) <= err;
                when USB_ADDR_IRQ_MASK =>
                    o_data_out(1 downto 0) <= irq_mask;
                when USB_ADDR_TIMING =>
                    o_data_out(TIMING_FIELD_BITS - 1 downto 0) <= setup_reg;
                    o_data_out(2 * TIMING_FIELD_BITS - 1 downto TIMING_FIELD_BITS) <= pulse_reg;
                    o_data_out(3 * TIMING_FIELD_BITS - 1 downto 2 * TIMING_FIELD_BITS) <= recovery_reg;
                when others =>
                    null;
            end case;
        end if;
    end process;

end architecture rtl;
