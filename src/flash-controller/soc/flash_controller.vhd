-- =============================================================================
-- Controlador de FLASH, periférico mapeado em memória
--
-- Interface de registradores no estilo das FLASH seriais comuns para o chip
-- modelado por flash_cmd_port (repositório Memory). O software escreve o
-- endereço, enche o buffer de página e escreve o código do comando; o
-- controlador entrega o comando ao chip no mesmo ciclo da escrita e mostra o
-- estado do chip (ocupado, latch de escrita e recusa) num registrador de leitura.
--
-- Mapa de registradores (endereço de palavra em i_address):
--
--   0  CMD       escrita: entrega o comando de 3 bits em i_data_in(2 downto 0)
--   1  ADDR      leitura e escrita: endereço de byte do comando (32 bits)
--   2  STATUS    leitura: bit 0 ocupado, bit 1 latch de escrita, bit 2 recusado
--   3  BUF_PTR   leitura e escrita: índice da palavra do buffer de página
--   4  BUF_DATA  escrita: grava a palavra em BUF_PTR e avança BUF_PTR em um
--   5  IRQ_ENABLE leitura e escrita: bit 0 DONE, bit 1 REFUSED; zero no reset
--   6  IRQ_STATUS leitura: bit 0 DONE (o chip terminou um apagar ou gravar, ocupado
--                 caiu), bit 1 REFUSED (o chip recusou um apagar ou gravar, recusa
--                 subiu); escrita: 1 limpa o bit, 0 não muda (W1C)
--   7            reservado: lê zero e ignora a escrita
--
-- A saída o_irq é de nível e vale (IRQ_STATUS and IRQ_ENABLE) diferente de zero.
-- Os bits de IRQ_STATUS ligam sempre que o evento ocorre, mesmo desabilitado; um
-- evento novo no mesmo ciclo da limpeza vence.
--
-- A escrita em CMD vira o pulso o_cmd_valid no mesmo ciclo, sem registrador no
-- caminho, então o chip já mostra ocupado no ciclo seguinte e uma leitura de
-- STATUS logo depois da escrita não vê o estado antigo. O chip ignora um
-- comando que chega com ocupado alto. O buffer guarda uma página de
-- page_bytes bytes, com todos os bits em 1 na configuração da FPGA, e a gravação do
-- chip lê as palavras dele por o_buf_data, que tem leitura registrada. O
-- software precisa escrever as palavras que quer gravar; as que não escreve
-- mantêm o conteúdo anterior do buffer.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.utils_pkg.all;

entity flash_controller is
  generic (
    -- Tamanho da página de gravar em bytes, uma potência de dois de 8 bytes em diante (256).
    page_bytes : positive := 256
  );
  port (
    -- Clock do módulo.
    i_clk        : in  std_logic;
    -- Reset, ativo em '1'.
    i_rst        : in  std_logic;

    -- Dado de escrita vindo do processador.
    i_data_in    : in  std_logic_vector(31 downto 0);
    -- Endereço de palavra de 3 bits vindo do processador.
    i_address    : in  std_logic_vector(2 downto 0);
    -- Pulso de escrita do processador ('1' = escreve).
    i_write      : in  std_logic;
    -- Pulso de leitura do processador ('1' = lê).
    i_read       : in  std_logic;
    -- Dado de leitura para o processador.
    o_data_out   : out std_logic_vector(31 downto 0);
    -- Requisição de interrupção de nível (comando concluído ou recusado), ativa em '1'.
    o_irq        : out std_logic;

    -- Pulso que entrega um comando ao chip.
    o_cmd_valid  : out std_logic;
    -- Código do comando.
    o_cmd_op     : out std_logic_vector(2 downto 0);
    -- Endereço de byte do comando.
    o_cmd_addr   : out std_logic_vector(31 downto 0);
    -- O chip está ocupado ('1').
    i_busy       : in  std_logic;
    -- O latch de escrita do chip está armado ('1').
    i_wel        : in  std_logic;
    -- O último apagar ou gravar com o latch armado foi recusado ('1').
    i_refused    : in  std_logic;

    -- Índice da palavra do buffer lida pela gravação do chip (registrado no chip).
    i_buf_idx    : in  std_logic_vector(log2_exact(page_bytes) - 3 downto 0);
    -- Palavra do buffer de página, com leitura registrada.
    o_buf_data   : out std_logic_vector(31 downto 0)
  );
end entity flash_controller;

architecture rtl of flash_controller is

  -- Endereço do registrador de comando.
  constant REG_CMD      : std_logic_vector(2 downto 0) := "000";
  -- Endereço do registrador de endereço do comando.
  constant REG_ADDR     : std_logic_vector(2 downto 0) := "001";
  -- Endereço do registrador de estado.
  constant REG_STATUS   : std_logic_vector(2 downto 0) := "010";
  -- Endereço do registrador de índice do buffer.
  constant REG_BUF_PTR  : std_logic_vector(2 downto 0) := "011";
  -- Endereço do registrador de dado do buffer.
  constant REG_BUF_DATA : std_logic_vector(2 downto 0) := "100";

  -- Endereço do registrador de habilitação de interrupção.
  constant REG_IRQ_ENABLE : std_logic_vector(2 downto 0) := "101";
  -- Endereço do registrador de estado de interrupção.
  constant REG_IRQ_STATUS : std_logic_vector(2 downto 0) := "110";

  -- Bits do índice do buffer.
  constant PTR_BITS   : natural := log2_exact(page_bytes) - 2;
  -- Palavras do buffer de página.
  constant PAGE_WORDS : natural := page_bytes / 4;

  -- Vetor de palavras do buffer de página.
  type page_t is array (0 to PAGE_WORDS - 1) of std_logic_vector(31 downto 0);
  -- Palavras do buffer de página, todas em 1 no início.
  signal page     : page_t := (others => (others => '1'));
  -- Endereço de byte do comando.
  signal addr_reg : std_logic_vector(31 downto 0) := (others => '0');
  -- Índice da palavra do buffer escrita por BUF_DATA.
  signal ptr      : unsigned(PTR_BITS - 1 downto 0) := (others => '0');
  -- Palavra do buffer lida pelo chip (registrada).
  signal buf_q    : std_logic_vector(31 downto 0) := (others => '0');
  -- Escrita no registrador de comando.
  signal wr_cmd   : std_logic;
  -- Escrita no registrador de dado do buffer.
  signal wr_data  : std_logic;
  -- Habilitação das interrupções: bit 0 conclusão, bit 1 recusa.
  signal irq_enable : std_logic_vector(1 downto 0) := (others => '0');
  -- Eventos pendentes: bit 0 conclusão, bit 1 recusa.
  signal irq_status : std_logic_vector(1 downto 0) := (others => '0');
  -- Ocupado do ciclo anterior, para detectar o fim do comando.
  signal busy_prev    : std_logic := '0';
  -- Recusa do ciclo anterior, para detectar uma recusa nova.
  signal refused_prev : std_logic := '0';
  -- Pulso de um ciclo: o chip terminou um comando.
  signal ev_done    : std_logic;
  -- Pulso de um ciclo: o chip recusou um comando.
  signal ev_refused : std_logic;

begin

  assert page_bytes >= 8 report "page_bytes must be at least 8 bytes" severity failure;

  wr_cmd      <= i_write when i_address = REG_CMD else '0';
  wr_data     <= i_write when i_address = REG_BUF_DATA else '0';
  o_cmd_valid <= wr_cmd;
  o_cmd_op    <= i_data_in(2 downto 0);
  o_cmd_addr  <= addr_reg;
  o_buf_data  <= buf_q;

  ev_done    <= busy_prev and not i_busy;
  ev_refused <= i_refused and not refused_prev;
  o_irq      <= '1' when (irq_status and irq_enable) /= "00" else '0';

  process (i_clk)
  begin
    if rising_edge(i_clk) then
      busy_prev    <= i_busy;
      refused_prev <= i_refused;
      if i_rst = '1' then
        irq_enable <= (others => '0');
        irq_status <= (others => '0');
      else
        if i_write = '1' and i_address = REG_IRQ_ENABLE then
          irq_enable <= i_data_in(1 downto 0);
        end if;
        if i_write = '1' and i_address = REG_IRQ_STATUS then
          irq_status <= irq_status and not i_data_in(1 downto 0);
        end if;
        if ev_done = '1' then
          irq_status(0) <= '1';
        end if;
        if ev_refused = '1' then
          irq_status(1) <= '1';
        end if;
      end if;
    end if;
  end process;

  process (i_clk)
  begin
    if rising_edge(i_clk) then
      if i_rst = '1' then
        addr_reg <= (others => '0');
        ptr      <= (others => '0');
      else
        if i_write = '1' and i_address = REG_ADDR then
          addr_reg <= i_data_in;
        end if;
        if i_write = '1' and i_address = REG_BUF_PTR then
          ptr <= unsigned(i_data_in(PTR_BITS - 1 downto 0));
        elsif wr_data = '1' then
          ptr <= ptr + 1;
        end if;
      end if;
      if wr_data = '1' then
        page(to_integer(ptr)) <= i_data_in;
      end if;
      buf_q <= page(to_integer(unsigned(i_buf_idx)));
    end if;
  end process;

  process (i_read, i_address, addr_reg, ptr, i_busy, i_wel, i_refused, irq_enable, irq_status)
  begin
    o_data_out <= (others => '0');
    if i_read = '1' then
      case i_address is
        when REG_ADDR =>
          o_data_out <= addr_reg;
        when REG_STATUS =>
          o_data_out(0) <= i_busy;
          o_data_out(1) <= i_wel;
          o_data_out(2) <= i_refused;
        when REG_BUF_PTR =>
          o_data_out(PTR_BITS - 1 downto 0) <= std_logic_vector(ptr);
        when REG_IRQ_ENABLE =>
          o_data_out(1 downto 0) <= irq_enable;
        when REG_IRQ_STATUS =>
          o_data_out(1 downto 0) <= irq_status;
        when others =>
          null;
      end case;
    end if;
  end process;

end architecture rtl;
