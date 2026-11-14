-- =============================================================================
-- Camada física do barramento paralelo do LCD (HD44780, interface de 8 bits)
-- =============================================================================
-- Executa uma operação de escrita por vez: apresenta RS, RW e o dado, espera o
-- tempo de setup, mantém EN alto pelo tempo do pulso, espera o tempo de hold e
-- então espera o chip terminar. A espera é um atraso fixo em ciclos ou, com
-- i_poll e has_rw, a leitura repetida do flag de ocupado (bit 7 do dado, com
-- RW alto e RS baixo) até ele baixar ou até o tempo limite estourar.
--
-- Os pinos de dado são o par saída e habilitação: o_lcd_data_oe vale '1' só
-- durante uma escrita, com RW baixo. Na leitura do ocupado o periférico solta o
-- barramento e o chip o conduz enquanto EN está alto; i_busy_flag vem do bit 7
-- já sincronizado e é amostrado no último ciclo do pulso. O pulso deve durar
-- mais que o atraso de dados do chip somado aos dois ciclos do sincronizador.
-- Os pinos saem de registradores, sem lógica entre o estado e o pino.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.lcd_consts.all;

entity lcd_phy is
    generic (
        -- Ciclos de RS, RW e dado estáveis antes da subida de EN.
        setup_cycles   : positive := 5;
        -- Ciclos com EN alto.
        pulse_cycles   : positive := 15;
        -- Ciclos de RS, RW e dado mantidos depois da descida de EN.
        hold_cycles    : positive := 5;
        -- Ciclos de espera pelo flag de ocupado antes de desistir.
        timeout_cycles : positive := 500000;
        -- Verdadeiro quando o pino RW da placa é ligado ao periférico.
        has_rw         : boolean  := true
    );
    port (
        -- Clock do módulo.
        i_clk          : in    std_logic;
        -- Reset síncrono, ativo em nível alto.
        i_rst          : in    std_logic;
        -- Pedido de uma operação, aceito no ciclo em que o_ready vale '1'.
        i_start        : in    std_logic;
        -- Valor de RS da operação ('0' comando, '1' dado).
        i_rs           : in    std_logic;
        -- Byte escrito no barramento de dados do chip.
        i_data         : in    std_logic_vector(7 downto 0);
        -- Pede a espera pelo flag de ocupado (ignorado sem has_rw).
        i_poll         : in    std_logic;
        -- Ciclos de espera depois da escrita quando não há leitura do flag.
        i_delay        : in    std_logic_vector(DELAY_BITS - 1 downto 0);
        -- Bit 7 do dado do chip, sincronizado com i_clk.
        i_busy_flag    : in    std_logic;
        -- Indica que nenhuma operação está em andamento.
        o_ready        : out   std_logic;
        -- Pulso de um ciclo quando o flag de ocupado não baixou a tempo.
        o_timeout      : out   std_logic;
        -- Pino RS do LCD.
        o_lcd_rs       : out   std_logic;
        -- Pino RW do LCD.
        o_lcd_rw       : out   std_logic;
        -- Pino EN do LCD.
        o_lcd_en       : out   std_logic;
        -- Dado conduzido nos pinos de dados do LCD.
        o_lcd_data     : out   std_logic_vector(7 downto 0);
        -- Habilitação do driver dos pinos de dados do LCD.
        o_lcd_data_oe  : out   std_logic
    );
end entity lcd_phy;

architecture rtl of lcd_phy is

    -- Fases de uma operação.
    type state_t is (
        ST_IDLE,
        ST_WRITE_SETUP,
        ST_WRITE_PULSE,
        ST_WRITE_HOLD,
        ST_WAIT_DELAY,
        ST_READ_SETUP,
        ST_READ_PULSE,
        ST_READ_HOLD
    );

    -- Fase atual.
    signal state     : state_t;
    -- Ciclos restantes da fase, menos um.
    signal count     : unsigned(DELAY_BITS - 1 downto 0);
    -- Ciclos restantes até o tempo limite da leitura do ocupado.
    signal poll_left : unsigned(DELAY_BITS - 1 downto 0);
    -- Atraso guardado da operação em andamento.
    signal delay_reg : unsigned(DELAY_BITS - 1 downto 0);
    -- A operação em andamento espera pelo flag de ocupado.
    signal poll_reg  : std_logic;
    -- Valor do flag de ocupado amostrado na última leitura.
    signal busy_seen : std_logic;
    -- Registrador do pino RS.
    signal rs_reg    : std_logic;
    -- Registrador do pino RW.
    signal rw_reg    : std_logic;
    -- Registrador do pino EN.
    signal en_reg    : std_logic;
    -- Registrador do dado conduzido.
    signal data_reg  : std_logic_vector(7 downto 0);
    -- Registrador da habilitação do driver de dados.
    signal oe_reg    : std_logic;
    -- Registrador do pulso de tempo limite.
    signal timeout_r : std_logic;

    -- Contagem de ciclos de uma fase com a duração dada.
    function phase_count (
        cycles : positive
    ) return unsigned is
    begin

        return to_unsigned(cycles - 1, DELAY_BITS);

    end function phase_count;

begin

    o_ready       <= '1' when state = ST_IDLE else '0';
    o_timeout     <= timeout_r;
    o_lcd_rs      <= rs_reg;
    o_lcd_rw      <= rw_reg;
    o_lcd_en      <= en_reg;
    o_lcd_data    <= data_reg;
    o_lcd_data_oe <= oe_reg;

    p_fsm : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            timeout_r <= '0';

            if i_rst = '1' then
                state     <= ST_IDLE;
                count     <= (others => '0');
                poll_left <= (others => '0');
                delay_reg <= (others => '0');
                poll_reg  <= '0';
                busy_seen <= '0';
                rs_reg    <= '0';
                rw_reg    <= '0';
                en_reg    <= '0';
                data_reg  <= (others => '0');
                oe_reg    <= '0';
                timeout_r <= '0';
            else
                -- O tempo limite corre durante toda a leitura do ocupado.
                if poll_left /= 0 and (state = ST_READ_SETUP or state = ST_READ_PULSE or state = ST_READ_HOLD) then
                    poll_left <= poll_left - 1;
                end if;

                case state is

                    when ST_IDLE =>

                        if i_start = '1' then
                            rs_reg    <= i_rs;
                            rw_reg    <= '0';
                            data_reg  <= i_data;
                            oe_reg    <= '1';
                            delay_reg <= unsigned(i_delay);
                            if has_rw then
                                poll_reg <= i_poll;
                            else
                                poll_reg <= '0';
                            end if;
                            count <= phase_count(setup_cycles);
                            state <= ST_WRITE_SETUP;
                        end if;

                    when ST_WRITE_SETUP =>

                        if count = 0 then
                            en_reg <= '1';
                            count  <= phase_count(pulse_cycles);
                            state  <= ST_WRITE_PULSE;
                        else
                            count <= count - 1;
                        end if;

                    when ST_WRITE_PULSE =>

                        if count = 0 then
                            en_reg <= '0';
                            count  <= phase_count(hold_cycles);
                            state  <= ST_WRITE_HOLD;
                        else
                            count <= count - 1;
                        end if;

                    when ST_WRITE_HOLD =>

                        if count = 0 then
                            oe_reg <= '0';
                            if poll_reg = '1' then
                                rw_reg    <= '1';
                                rs_reg    <= '0';
                                poll_left <= phase_count(timeout_cycles);
                                count     <= phase_count(setup_cycles);
                                state     <= ST_READ_SETUP;
                            elsif delay_reg = 0 then
                                state <= ST_IDLE;
                            else
                                count <= delay_reg - 1;
                                state <= ST_WAIT_DELAY;
                            end if;
                        else
                            count <= count - 1;
                        end if;

                    when ST_WAIT_DELAY =>

                        if count = 0 then
                            state <= ST_IDLE;
                        else
                            count <= count - 1;
                        end if;

                    when ST_READ_SETUP =>

                        if count = 0 then
                            en_reg <= '1';
                            count  <= phase_count(pulse_cycles);
                            state  <= ST_READ_PULSE;
                        else
                            count <= count - 1;
                        end if;

                    when ST_READ_PULSE =>

                        if count = 0 then
                            en_reg    <= '0';
                            busy_seen <= i_busy_flag;
                            count     <= phase_count(hold_cycles);
                            state     <= ST_READ_HOLD;
                        else
                            count <= count - 1;
                        end if;

                    when ST_READ_HOLD =>

                        if count = 0 then
                            if busy_seen = '1' and poll_left /= 0 then
                                count <= phase_count(setup_cycles);
                                state <= ST_READ_SETUP;
                            else
                                rw_reg    <= '0';
                                timeout_r <= busy_seen;
                                state     <= ST_IDLE;
                            end if;
                        else
                            count <= count - 1;
                        end if;

                end case;

            end if;
        end if;

    end process p_fsm;

end architecture rtl;
