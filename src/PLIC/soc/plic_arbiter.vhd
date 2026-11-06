-- =============================================================================
-- Árbitro do PLIC
--
-- Escolhe, entre as fontes pendentes e habilitadas, a de maior prioridade
-- estritamente acima do limiar. Em empate de prioridade vence o menor
-- identificador. Sem candidata, o identificador é zero e a saída o_valid vale
-- '0'. É combinacional.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity plic_arbiter is
  generic (
    -- Número de fontes (identificadores de 1 a n_sources).
    n_sources     : positive := 8;
    -- Largura da prioridade em bits.
    priority_bits : positive := 3;
    -- Largura do identificador em bits.
    id_width      : positive := 4
  );
  port (
    -- Pendentes, o bit n é a fonte n.
    i_pending    : in  std_logic_vector(n_sources downto 1);
    -- Habilitadas no contexto, o bit n é a fonte n.
    i_enable     : in  std_logic_vector(n_sources downto 1);
    -- Prioridades concatenadas, a fonte n ocupa os bits n*priority_bits-1 a (n-1)*priority_bits.
    i_priorities : in  std_logic_vector(n_sources * priority_bits - 1 downto 0);
    -- Limiar do contexto.
    i_threshold  : in  std_logic_vector(priority_bits - 1 downto 0);
    -- Identificador da fonte vencedora, ou zero sem candidata.
    o_id         : out std_logic_vector(id_width - 1 downto 0);
    -- Existe uma candidata.
    o_valid      : out std_logic
  );
end entity plic_arbiter;

architecture rtl of plic_arbiter is
begin

  process (i_pending, i_enable, i_priorities, i_threshold)
    -- Melhor fonte até o momento.
    variable best_id  : natural range 0 to n_sources;
    -- Prioridade que a próxima candidata precisa superar.
    variable best_pri : unsigned(priority_bits - 1 downto 0);
    -- Prioridade da fonte em exame.
    variable pri      : unsigned(priority_bits - 1 downto 0);
  begin
    best_id  := 0;
    best_pri := unsigned(i_threshold);
    for n in 1 to n_sources loop
      pri := unsigned(i_priorities(n * priority_bits - 1 downto (n - 1) * priority_bits));
      if i_pending(n) = '1' and i_enable(n) = '1' and pri > best_pri then
        best_id  := n;
        best_pri := pri;
      end if;
    end loop;
    o_id <= std_logic_vector(to_unsigned(best_id, id_width));
    if best_id /= 0 then
      o_valid <= '1';
    else
      o_valid <= '0';
    end if;
  end process;

end architecture rtl;
