-- =============================================================================
-- Sincronizador de N estágios para um bit assíncrono
--
-- Cada estágio é um flip-flop; o bit assíncrono atravessa n estágios em série
-- antes de chegar à saída, o que reduz a probabilidade de metaestabilidade.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity generic_synchronizer_1bit is
    generic (
        -- Número de estágios do sincronizador (no mínimo 2).
        n : natural := 2
    );
    port (
        -- Clock do domínio de destino.
        i_clk    : in  std_logic;
        -- Bit de entrada assíncrono.
        i_async_in : in  std_logic;
        -- Bit sincronizado.
        o_sync_out : out std_logic
    );
end entity generic_synchronizer_1bit;

-- -----------------------------------------------------------------------------
-- Architecture
-- -----------------------------------------------------------------------------
architecture rtl of generic_synchronizer_1bit is

    -- Vetor com a entrada e a saída de cada estágio.
    type sync_array_t is array (0 to n) of std_logic;
    -- Valor em cada estágio do sincronizador.
    signal sync_stages : sync_array_t;

begin
    ---------------------------------------------------------------------------
    -- Estágio 0: liga o sinal assíncrono bruto à cadeia
    ---------------------------------------------------------------------------
    sync_stages(0) <= i_async_in;

    ---------------------------------------------------------------------------
    -- Estágios 1 a N: um flip-flop por estágio
    ---------------------------------------------------------------------------
    gen_stage : for i in 1 to n generate
        u_ff : entity work.flip_flop
            port map (
                i_clk    => i_clk,
                i_rst    => '0',            -- sem reset
                i_enable => '1',            -- sempre habilitado
                i_d      => sync_stages(i-1),
                o_d      => sync_stages(i)
            );
    end generate gen_stage;

    ---------------------------------------------------------------------------
    -- Saída: último estágio da cadeia
    ---------------------------------------------------------------------------
    o_sync_out <= sync_stages(n);

end architecture rtl;
