-- ==========================================================================
-- Fila síncrona de palavras
-- ==========================================================================
-- Armazena palavras em ordem de chegada usando um único domínio de clock.
-- A palavra mais antiga fica disponível de forma combinacional, permitindo
-- que o barramento leia o dado antes da borda que efetiva a remoção. Uma
-- inserção numa fila cheia é aceita quando há uma remoção aceita no mesmo
-- ciclo, pois a posição liberada pode ser reutilizada sem mudar o nível.
-- ==========================================================================

library ieee;
use ieee.std_logic_1164.all;

entity uart_fifo is
  generic (
    -- Largura de cada palavra armazenada, em bits.
    data_width : positive := 8;
    -- Quantidade máxima de palavras armazenadas.
    depth      : positive := 16
  );
  port (
    -- Clock da fila.
    i_clk           : in  std_logic;
    -- Reset assíncrono, ativo em nível alto.
    i_rst           : in  std_logic;
    -- Pedido de inserção de uma palavra.
    i_push          : in  std_logic;
    -- Palavra apresentada para inserção.
    i_push_data     : in  std_logic_vector(data_width - 1 downto 0);
    -- Pedido de remoção da palavra mais antiga.
    i_pop           : in  std_logic;
    -- Palavra mais antiga, ou zero quando a fila está vazia.
    o_pop_data      : out std_logic_vector(data_width - 1 downto 0);
    -- Indica que a inserção solicitada será efetivada na próxima borda.
    o_push_accepted : out std_logic;
    -- Indica que a remoção solicitada será efetivada na próxima borda.
    o_pop_accepted  : out std_logic;
    -- Indica que todas as posições estão ocupadas.
    o_full          : out std_logic;
    -- Indica que nenhuma palavra está armazenada.
    o_empty         : out std_logic;
    -- Quantidade atual de palavras armazenadas.
    o_level         : out natural range 0 to depth
  );
end entity uart_fifo;

architecture rtl of uart_fifo is
  -- Memória que guarda as palavras da fila.
  type memory_t is array (0 to depth - 1) of
    std_logic_vector(data_width - 1 downto 0);

  -- Conteúdo das posições da fila.
  signal memory        : memory_t;
  -- Posição da próxima palavra a remover.
  signal read_pointer  : natural range 0 to depth - 1;
  -- Posição da próxima palavra a inserir.
  signal write_pointer : natural range 0 to depth - 1;
  -- Quantidade de palavras armazenadas.
  signal count         : natural range 0 to depth;
  -- Aceitação combinacional do pedido de inserção.
  signal push_accepted : std_logic;
  -- Aceitação combinacional do pedido de remoção.
  signal pop_accepted  : std_logic;

  -- Avança um ponteiro circular, retornando ao início depois da última posição.
  function next_pointer(pointer : natural) return natural is
  begin
    if pointer = depth - 1 then
      return 0;
    end if;

    return pointer + 1;
  end function next_pointer;
begin
  o_empty <= '1' when count = 0 else '0';
  o_full  <= '1' when count = depth else '0';
  o_level <= count;

  pop_accepted <= '1' when i_pop = '1' and count > 0 else '0';
  push_accepted <= '1'
    when i_push = '1' and (count < depth or pop_accepted = '1')
    else '0';

  o_push_accepted <= push_accepted;
  o_pop_accepted  <= pop_accepted;

  o_pop_data <= memory(read_pointer) when count > 0 else (others => '0');

  p_storage : process (i_rst, i_clk)
  begin
    if i_rst = '1' then
      read_pointer  <= 0;
      write_pointer <= 0;
      count         <= 0;
    elsif rising_edge(i_clk) then
      if push_accepted = '1' then
        memory(write_pointer) <= i_push_data;
        write_pointer <= next_pointer(write_pointer);
      end if;

      if pop_accepted = '1' then
        read_pointer <= next_pointer(read_pointer);
      end if;

      if push_accepted = '1' and pop_accepted = '0' then
        count <= count + 1;
      elsif push_accepted = '0' and pop_accepted = '1' then
        count <= count - 1;
      end if;
    end if;
  end process p_storage;
end architecture rtl;
