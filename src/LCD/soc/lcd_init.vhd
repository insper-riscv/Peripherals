-- =============================================================================
-- Sequência de inicialização do LCD em hardware
-- =============================================================================
-- Depois do reset espera o tempo de energização do chip e envia à camada
-- física, um de cada vez, os comandos da inicialização por instrução do
-- HD44780: três function sets de acordo, o function set de 8 bits e duas
-- linhas, display ligado, limpar a tela e entry mode. Cada comando espera um
-- atraso fixo, pois o flag de ocupado só é confiável depois do function set.
-- Com enabled falso a entidade fica sempre pronta e não envia nada.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.lcd_consts.all;

entity lcd_init is
    generic (
        -- Frequência do clock em hertz.
        clk_freq_hz  : positive := 50000000;
        -- Liga a sequência; falso deixa o periférico sem inicialização.
        enabled      : boolean  := true;
        -- Espera depois do reset antes do primeiro comando, em microssegundos.
        power_up_us  : natural  := 20000;
        -- Espera depois de um comando comum, em microssegundos.
        exec_us      : natural  := 50;
        -- Espera depois do comando de limpar a tela, em microssegundos.
        exec_long_us : natural  := 2000
    );
    port (
        -- Clock do módulo.
        i_clk       : in    std_logic;
        -- Reset síncrono, ativo em nível alto.
        i_rst       : in    std_logic;
        -- A camada física está livre para receber um comando.
        i_phy_ready : in    std_logic;
        -- Pedido de envio do comando atual à camada física.
        o_start     : out   std_logic;
        -- Byte do comando atual.
        o_data      : out   std_logic_vector(7 downto 0);
        -- Ciclos de espera depois do comando atual.
        o_delay     : out   std_logic_vector(DELAY_BITS - 1 downto 0);
        -- A sequência está em andamento.
        o_busy      : out   std_logic
    );
end entity lcd_init;

architecture rtl of lcd_init is

    -- Fases da sequência.
    type state_t is (ST_POWER, ST_SEND, ST_DRAIN, ST_DONE);

    -- Ciclos da espera de energização.
    constant POWER_CYCLES     : positive := us_to_cycles(power_up_us, clk_freq_hz);
    -- Ciclos de espera depois de um comando comum.
    constant EXEC_CYCLES      : positive := us_to_cycles(exec_us, clk_freq_hz);
    -- Ciclos de espera depois de limpar a tela.
    constant EXEC_LONG_CYCLES : positive := us_to_cycles(exec_long_us, clk_freq_hz);
    -- Ciclos de espera depois do primeiro function set (o datasheet pede mais de 4,1 ms).
    constant WAKE_FIRST_CYCLES : positive := us_to_cycles(5000, clk_freq_hz);
    -- Ciclos de espera depois dos function sets seguintes (o datasheet pede mais de 100 us).
    constant WAKE_CYCLES       : positive := us_to_cycles(200, clk_freq_hz);

    -- Fase atual.
    signal state : state_t;
    -- Passo atual da sequência.
    signal step  : natural range 0 to INIT_STEPS;
    -- Ciclos restantes da espera de energização, menos um.
    signal count : natural range 0 to POWER_CYCLES;

    -- Ciclos de espera depois do passo dado.
    function step_delay (
        index : natural
    ) return natural is
    begin

        case index is

            when 0 =>

                return WAKE_FIRST_CYCLES;

            when 1 | 2 =>

                return WAKE_CYCLES;

            when 5 =>

                return EXEC_LONG_CYCLES;

            when others =>

                return EXEC_CYCLES;

        end case;

    end function step_delay;

    -- Passo usado para os valores de saída, nunca além do último.
    signal shown_step : natural range 0 to INIT_STEPS - 1;

begin

    shown_step <= step when step < INIT_STEPS else INIT_STEPS - 1;
    o_data     <= init_command(shown_step);
    o_delay    <= std_logic_vector(to_unsigned(step_delay(shown_step), DELAY_BITS));
    o_start    <= '1' when state = ST_SEND and i_phy_ready = '1' else '0';
    o_busy     <= '0' when state = ST_DONE else '1';

    p_fsm : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            if i_rst = '1' then
                step <= 0;
                if enabled then
                    state <= ST_POWER;
                    count <= POWER_CYCLES - 1;
                else
                    state <= ST_DONE;
                    count <= 0;
                end if;
            else
                case state is

                    when ST_POWER =>

                        if count = 0 then
                            state <= ST_SEND;
                        else
                            count <= count - 1;
                        end if;

                    when ST_SEND =>

                        if i_phy_ready = '1' then
                            step <= step + 1;
                            if step = INIT_STEPS - 1 then
                                state <= ST_DRAIN;
                            end if;
                        end if;

                    when ST_DRAIN =>

                        if i_phy_ready = '1' then
                            state <= ST_DONE;
                        end if;

                    when ST_DONE =>

                        null;

                end case;
            end if;
        end if;

    end process p_fsm;

end architecture rtl;
