-- =============================================================================
-- CLINT: mtime, mtimecmp e msip de um hart
--
-- Periférico mapeado em memória no leiaute do CLINT da SiFive que o porte do
-- FreeRTOS espera. Todos os acessos são de 32 bits, com a metade baixa no
-- endereço menor. O mtime de 64 bits soma 1 a cada tick_cycles ciclos de clock.
-- A saída o_irq_timer (MTIP) vale mtime >= mtimecmp, sem sinal, em 64 bits,
-- registrada em um ciclo. A saída o_irq_software (MSIP) é o bit 0 do msip.
-- A saída o_mtime entrega o mtime de 64 bits (a metade alta já com o vai-um pendente), para o CSR time do núcleo,
-- que é o sombreamento somente leitura dele.
--
-- Escrita segura do mtimecmp: a sequência do porte (metade baixa com
-- 0xFFFFFFFF, metade alta, metade baixa) só cresce o mtimecmp até o valor final,
-- então a comparação nunca dispara num estado intermediário que o valor antigo
-- ou o final não dispararia.
--
-- Leitura: o_data_out é combinacional no endereço, sem efeito colateral. O par
-- lido em três leituras (alta, baixa, alta) é consistente, porque o vai-um
-- pendente já aparece na metade alta. Endereços fora do mapa leem zero e a
-- escrita neles não tem efeito.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.config_pkg.all;
use work.clint_consts.all;

entity clint is
    generic (
        -- Número de ciclos de clock por incremento do mtime.
        tick_cycles : positive := 1
    );
    port (
        -- Clock do módulo.
        i_clk          : in    std_logic;
        -- Reset, ativo em '1'.
        i_rst          : in    std_logic;
        -- Dado de escrita vindo do processador.
        i_data_in      : in    word_t;
        -- Endereço de palavra dentro do periférico.
        i_address      : in    std_logic_vector(CLINT_ADDR_WIDTH - 1 downto 0);
        -- Pulso de escrita do processador ('1' = escreve).
        i_write        : in    std_logic;
        -- Dado de leitura para o processador.
        o_data_out     : out   word_t;
        -- Interrupção de timer de máquina (MTIP), ativa em '1'.
        o_irq_timer    : out   std_logic;
        -- Interrupção de software de máquina (MSIP), ativa em '1'.
        o_irq_software : out   std_logic;
        -- Valor de 64 bits do mtime (a metade alta com o vai-um pendente), que o CSR time do núcleo espelha.
        o_mtime        : out   std_logic_vector(63 downto 0)
    );
end entity clint;

architecture rtl of clint is

    -- Habilita a escrita do msip.
    signal wr_msip     : std_logic;
    -- Habilita a escrita da metade baixa do mtimecmp.
    signal wr_cmp_lo   : std_logic;
    -- Habilita a escrita da metade alta do mtimecmp.
    signal wr_cmp_hi   : std_logic;
    -- Habilita a escrita da metade baixa do mtime.
    signal wr_mtime_lo : std_logic;
    -- Habilita a escrita da metade alta do mtime.
    signal wr_mtime_hi : std_logic;
    -- Incremento do mtime neste ciclo.
    signal tick        : std_logic;
    -- Bit do msip.
    signal msip        : std_logic_vector(0 downto 0);
    -- Metade baixa do mtimecmp.
    signal cmp_lo      : word_t;
    -- Metade alta do mtimecmp.
    signal cmp_hi      : word_t;
    -- Metade baixa do mtime.
    signal mtime_lo    : word_t;
    -- Metade alta do mtime, com o vai-um pendente.
    signal mtime_hi    : word_t;
    -- Valor de 64 bits do mtime.
    signal mtime       : std_logic_vector(63 downto 0);
    -- Valor de 64 bits do mtimecmp.
    signal mtimecmp    : std_logic_vector(63 downto 0);
    -- mtime >= mtimecmp, antes do registro.
    signal timer_ge    : std_logic;
    -- Saída MTIP registrada.
    signal timer_irq   : std_logic;

begin

    wr_msip     <= i_write when i_address = ADDR_MSIP else '0';
    wr_cmp_lo   <= i_write when i_address = ADDR_MTIMECMP_LO else '0';
    wr_cmp_hi   <= i_write when i_address = ADDR_MTIMECMP_HI else '0';
    wr_mtime_lo <= i_write when i_address = ADDR_MTIME_LO else '0';
    wr_mtime_hi <= i_write when i_address = ADDR_MTIME_HI else '0';

    -- ---------------------------------------------------------------------------
    -- Divisor do incremento: um tick a cada tick_cycles ciclos
    -- ---------------------------------------------------------------------------

    gen_tick_every_cycle : if tick_cycles = 1 generate
        tick <= '1';
    end generate gen_tick_every_cycle;

    gen_tick_divided : if tick_cycles > 1 generate
        -- Ciclos já contados no período atual.
        signal phase : natural range 0 to tick_cycles - 1;
    begin

        p_phase : process (i_rst, i_clk) is
        begin

            if i_rst = '1' then
                phase <= 0;
            elsif rising_edge(i_clk) then
                if phase = tick_cycles - 1 then
                    phase <= 0;
                else
                    phase <= phase + 1;
                end if;
            end if;

        end process p_phase;

        tick <= '1' when phase = tick_cycles - 1 else '0';
    end generate gen_tick_divided;

    u_mtime : entity work.counter64
        generic map (
            width => 64
        )
        port map (
            i_clk   => i_clk,
            i_rst   => i_rst,
            i_inc   => tick,
            i_we_lo => wr_mtime_lo,
            i_we_hi => wr_mtime_hi,
            i_wdata => i_data_in,
            o_lo    => mtime_lo,
            o_hi    => mtime_hi,
            o_wrap  => open
        );

    u_msip : entity work.generic_register
        generic map (
            data_width => 1
        )
        port map (
            i_clk    => i_clk,
            i_rst    => i_rst,
            i_enable => wr_msip,
            i_d      => i_data_in(0 downto 0),
            o_d      => msip
        );

    -- O mtimecmp reinicia com todos os bits em '1', o que mantém o MTIP baixo.
    u_cmp_lo : entity work.clearable_register
        generic map (
            data_width  => 32,
            clear_value => '1'
        )
        port map (
            i_clk    => i_clk,
            i_clear  => i_rst,
            i_enable => wr_cmp_lo,
            i_d      => i_data_in,
            o_d      => cmp_lo
        );

    u_cmp_hi : entity work.clearable_register
        generic map (
            data_width  => 32,
            clear_value => '1'
        )
        port map (
            i_clk    => i_clk,
            i_clear  => i_rst,
            i_enable => wr_cmp_hi,
            i_d      => i_data_in,
            o_d      => cmp_hi
        );

    mtime    <= mtime_hi & mtime_lo;
    o_mtime  <= mtime;
    mtimecmp <= cmp_hi & cmp_lo;

    u_ge : entity work.alu_ge_unsigned
        generic map (
            data_width => 64
        )
        port map (
            i_source_1 => mtime,
            i_source_2 => mtimecmp,
            o_ge       => timer_ge
        );

    u_mtip : entity work.flip_flop
        port map (
            i_d      => timer_ge,
            o_d      => timer_irq,
            i_enable => '1',
            i_clk    => i_clk,
            i_rst    => i_rst
        );

    o_irq_timer    <= timer_irq;
    o_irq_software <= msip(0);

    -- ---------------------------------------------------------------------------
    -- Leitura combinacional por endereço
    -- ---------------------------------------------------------------------------
    with i_address select o_data_out <=
        (XLEN - 1 downto 1 => '0') & msip when ADDR_MSIP,
        cmp_lo when ADDR_MTIMECMP_LO,
        cmp_hi when ADDR_MTIMECMP_HI,
        mtime_lo when ADDR_MTIME_LO,
        mtime_hi when ADDR_MTIME_HI,
        (others => '0') when others;

end architecture rtl;
