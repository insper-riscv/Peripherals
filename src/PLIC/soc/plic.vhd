-- =============================================================================
-- PLIC: controlador de interrupção externa de plataforma (riscv-plic-1.0.0)
--
-- Um hart e um contexto (modo máquina), fontes 1 a n_sources (a fonte 0 não
-- existe). Cada fonte tem um gateway de nível (plic_gateway), uma prioridade de
-- priority_bits bits (0 = nunca interrompe) e um bit de habilitação. O limiar
-- é do contexto. A saída o_meip vale '1' exatamente quando há uma fonte
-- pendente, habilitada e com prioridade estritamente acima do limiar.
--
-- Registradores (deslocamento em bytes, acessos de 32 bits):
--   0x000000 + 4*id   prioridade da fonte id (leitura e escrita); o id 0 lê zero
--   0x001000 + 4*k    pendentes das fontes 32k a 32k+31 (somente leitura)
--   0x002000 + 4*k    habilitação do contexto 0 das fontes 32k a 32k+31
--   0x200000          limiar do contexto 0
--   0x200004          claim (leitura) e complete (escrita) do contexto 0
-- A leitura do claim devolve a fonte vencedora (zero sem candidata) e limpa o
-- seu pendente, a fonte segue mascarada no gateway até o complete. A escrita do
-- claim com um id habilitado desmascara essa fonte; com um id inválido ou não
-- habilitado é ignorada. Endereços fora do mapa leem zero e ignoram a escrita.
-- A janela mínima é de 0x200008 bytes (addr_width = 20 bits de palavra); os bits
-- de endereço acima do mapa só podem ser zero para acertar um registrador.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.plic_consts.all;

entity plic is
  generic (
    -- Número de fontes de interrupção (1 a 1023).
    n_sources     : positive := 8;
    -- Largura da prioridade e do limiar em bits (prioridades 1 a 2**priority_bits - 1).
    priority_bits : positive := 3;
    -- Largura do endereço de palavra, definida pela janela da plataforma (no mínimo 20).
    addr_width    : positive := PLIC_MIN_ADDR_WIDTH
  );
  port (
    -- Clock do módulo.
    i_clk      : in  std_logic;
    -- Reset síncrono, ativo em '1'.
    i_rst      : in  std_logic;
    -- Linhas de interrupção de nível das fontes, o bit n é a fonte n, ativas em '1'.
    i_sources  : in  std_logic_vector(n_sources downto 1);
    -- Dado de escrita vindo do processador.
    i_data_in  : in  std_logic_vector(31 downto 0);
    -- Endereço de palavra dentro do periférico.
    i_address  : in  std_logic_vector(addr_width - 1 downto 0);
    -- Pulso de escrita do processador ('1' = escreve).
    i_write    : in  std_logic;
    -- Pulso de leitura do processador (a leitura do claim limpa o pendente).
    i_read     : in  std_logic;
    -- Dado de leitura para o processador.
    o_data_out : out std_logic_vector(31 downto 0);
    -- Interrupção externa de máquina (MEIP), ativa em '1'.
    o_meip     : out std_logic
  );
end entity plic;

architecture rtl of plic is

  -- Largura do identificador de fonte.
  constant ID_WIDTH : positive := id_bits(n_sources);

  -- Prioridades concatenadas, a fonte n nos bits n*priority_bits-1 a (n-1)*priority_bits.
  signal priorities : std_logic_vector(n_sources * priority_bits - 1 downto 0) := (others => '0');
  -- Habilitação do contexto 0, o bit n é a fonte n.
  signal enable_reg : std_logic_vector(n_sources downto 1) := (others => '0');
  -- Limiar do contexto 0.
  signal threshold  : std_logic_vector(priority_bits - 1 downto 0) := (others => '0');
  -- Pendentes vindos dos gateways.
  signal pending    : std_logic_vector(n_sources downto 1);
  -- Fonte vencedora do árbitro.
  signal winner_id  : std_logic_vector(ID_WIDTH - 1 downto 0);
  -- Existe candidata.
  signal winner_ok  : std_logic;
  -- Pulso de claim de cada fonte.
  signal claim_hit  : std_logic_vector(n_sources downto 1);
  -- Pulso de complete de cada fonte.
  signal compl_hit  : std_logic_vector(n_sources downto 1);
  -- Leitura do claim neste ciclo.
  signal claim_read : std_logic;
  -- Escrita do claim/complete neste ciclo.
  signal compl_write : std_logic;
  -- Endereço de palavra como inteiro.
  signal addr       : natural;

begin

  assert n_sources <= PLIC_MAX_SOURCES
    report "plic: n_sources deve estar entre 1 e 1023"
    severity failure;
  assert priority_bits <= 32
    report "plic: priority_bits deve estar entre 1 e 32"
    severity failure;
  assert addr_width >= PLIC_MIN_ADDR_WIDTH and addr_width <= 31
    report "plic: addr_width deve estar entre 20 e 31"
    severity failure;

  addr <= to_integer(unsigned(i_address));

  claim_read  <= '1' when i_read = '1' and addr = ADDR_CLAIM_COMPLETE else '0';
  compl_write <= '1' when i_write = '1' and addr = ADDR_CLAIM_COMPLETE else '0';

  gen_sources : for n in 1 to n_sources generate
    -- A fonte é reclamada quando é a vencedora e o claim é lido.
    claim_hit(n) <= '1' when claim_read = '1' and winner_ok = '1' and to_integer(unsigned(winner_id)) = n else '0';
    -- O complete só vale para uma fonte habilitada no contexto.
    compl_hit(n) <= '1' when compl_write = '1' and enable_reg(n) = '1' and unsigned(i_data_in) = to_unsigned(n, 32) else '0';

    u_gateway : entity work.plic_gateway
      port map (
        i_clk      => i_clk,
        i_rst      => i_rst,
        i_source   => i_sources(n),
        i_claim    => claim_hit(n),
        i_complete => compl_hit(n),
        o_pending  => pending(n)
      );
  end generate gen_sources;

  u_arbiter : entity work.plic_arbiter
    generic map (
      n_sources     => n_sources,
      priority_bits => priority_bits,
      id_width      => ID_WIDTH
    )
    port map (
      i_pending    => pending,
      i_enable     => enable_reg,
      i_priorities => priorities,
      i_threshold  => threshold,
      o_id         => winner_id,
      o_valid      => winner_ok
    );

  o_meip <= winner_ok;

  -- ---------------------------------------------------------------------------
  -- Escrita de prioridade, habilitação e limiar
  -- ---------------------------------------------------------------------------
  process (i_clk)
  begin
    if rising_edge(i_clk) then
      if i_rst = '1' then
        priorities <= (others => '0');
        enable_reg <= (others => '0');
        threshold  <= (others => '0');
      elsif i_write = '1' then
        if addr = ADDR_THRESHOLD then
          threshold <= i_data_in(priority_bits - 1 downto 0);
        end if;
        for n in 1 to n_sources loop
          if addr = n then
            priorities(n * priority_bits - 1 downto (n - 1) * priority_bits) <= i_data_in(priority_bits - 1 downto 0);
          end if;
          if addr = ADDR_ENABLE_BASE + n / 32 then
            enable_reg(n) <= i_data_in(n mod 32);
          end if;
        end loop;
      end if;
    end if;
  end process;

  -- ---------------------------------------------------------------------------
  -- Leitura combinacional por endereço
  -- ---------------------------------------------------------------------------
  process (addr, priorities, pending, enable_reg, threshold, winner_id)
  begin
    o_data_out <= (others => '0');
    if addr = ADDR_THRESHOLD then
      o_data_out(priority_bits - 1 downto 0) <= threshold;
    elsif addr = ADDR_CLAIM_COMPLETE then
      o_data_out(ID_WIDTH - 1 downto 0) <= winner_id;
    end if;
    for n in 1 to n_sources loop
      if addr = n then
        o_data_out(priority_bits - 1 downto 0) <= priorities(n * priority_bits - 1 downto (n - 1) * priority_bits);
      end if;
      if addr = ADDR_PENDING_BASE + n / 32 then
        o_data_out(n mod 32) <= pending(n);
      end if;
      if addr = ADDR_ENABLE_BASE + n / 32 then
        o_data_out(n mod 32) <= enable_reg(n);
      end if;
    end loop;
  end process;

end architecture rtl;
