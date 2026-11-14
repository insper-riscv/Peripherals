-- =============================================================================
-- Medidor de pulsos e espaços do receptor de infravermelho
--
-- Filtra a linha já sincronizada (uma mudança só vale depois de glitch_cycles
-- ciclos seguidos no novo nível) e mede, em ciclos de clock, quanto durou cada
-- nível. A cada mudança do nível filtrado gera um pulso de um ciclo em
-- o_event, com a largura do nível que acabou em o_width e o tipo dele em
-- o_event_mark ('1' para pulso, nível ativo; '0' para espaço). Quando um nível
-- dura timeout_cycles ciclos sem mudar, gera um pulso em o_timeout, uma vez por
-- nível. O nível de repouso é o inativo, então o primeiro evento depois do
-- reset é o fim de um espaço.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ir_pulse_meter is
    generic (
        -- Ciclos que a linha precisa ficar estável para a mudança valer (no mínimo 1).
        glitch_cycles  : positive := 2;
        -- Ciclos de um mesmo nível que disparam o_timeout.
        timeout_cycles : positive := 600000;
        -- Linha ativa em nível baixo, como os módulos demoduladores (TSOP, IRM).
        active_low     : boolean  := true
    );
    port (
        -- Clock do módulo.
        i_clk         : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst         : in    std_logic;
        -- Linha do receptor, já sincronizada com i_clk.
        i_line        : in    std_logic;
        -- Pulso de um ciclo quando o nível filtrado muda.
        o_event       : out   std_logic;
        -- Tipo do nível que acabou: '1' pulso, '0' espaço.
        o_event_mark  : out   std_logic;
        -- Largura em ciclos do nível que acabou.
        o_width       : out   std_logic_vector(31 downto 0);
        -- Pulso de um ciclo quando o nível atual chega a timeout_cycles.
        o_timeout     : out   std_logic;
        -- Nível filtrado atual: '1' com pulso.
        o_active      : out   std_logic
    );
end entity ir_pulse_meter;

architecture rtl of ir_pulse_meter is

    -- Nível da linha que representa o pulso.
    function level_of_mark return std_logic is
    begin

        if active_low then
            return '0';
        end if;

        return '1';

    end function level_of_mark;

    -- Nível de repouso da linha.
    constant ACTIVE_LEVEL : std_logic := level_of_mark;
    -- Nível filtrado da linha.
    signal filt   : std_logic := not ACTIVE_LEVEL;
    -- Ciclos seguidos em que a linha discorda do nível filtrado.
    signal stable : natural range 0 to glitch_cycles := 0;
    -- Ciclos desde a última mudança do nível filtrado, saturado.
    signal count  : unsigned(31 downto 0) := to_unsigned(1, 32);
    -- Pulso de evento registrado.
    signal event_r   : std_logic := '0';
    -- Tipo do evento registrado.
    signal mark_r    : std_logic := '0';
    -- Largura do evento registrada.
    signal width_r   : std_logic_vector(31 downto 0) := (others => '0');
    -- Pulso de timeout registrado.
    signal timeout_r : std_logic := '0';

begin

    o_event      <= event_r;
    o_event_mark <= mark_r;
    o_width      <= width_r;
    o_timeout    <= timeout_r;
    o_active     <= '1' when filt = ACTIVE_LEVEL else '0';

    -- Filtro de ruído, contador de largura e geração dos eventos.
    p_meter : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            event_r   <= '0';
            timeout_r <= '0';

            if i_rst = '1' then
                filt   <= not ACTIVE_LEVEL;
                stable <= 0;
                count  <= to_unsigned(1, 32);
                width_r <= (others => '0');
                mark_r  <= '0';
            else
                if count /= x"FFFFFFFF" then
                    count <= count + 1;
                end if;

                if i_line = filt then
                    stable <= 0;

                    if count = to_unsigned(timeout_cycles, 32) then
                        timeout_r <= '1';
                    end if;
                elsif stable = glitch_cycles - 1 then
                    stable  <= 0;
                    filt    <= i_line;
                    event_r <= '1';
                    width_r <= std_logic_vector(count);
                    count   <= to_unsigned(1, 32);

                    if filt = ACTIVE_LEVEL then
                        mark_r <= '1';
                    else
                        mark_r <= '0';
                    end if;
                else
                    stable <= stable + 1;

                    if count = to_unsigned(timeout_cycles, 32) then
                        timeout_r <= '1';
                    end if;
                end if;
            end if;
        end if;

    end process p_meter;

end architecture rtl;
