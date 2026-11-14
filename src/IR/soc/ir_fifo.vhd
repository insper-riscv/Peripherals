-- =============================================================================
-- FIFO síncrona de quadros do receptor de infravermelho
--
-- Guarda os quadros em ordem de chegada. O quadro mais antigo fica disponível
-- de forma combinacional em o_pop_data (zero com a fila vazia), de modo que o
-- barramento lê antes da borda que remove. Um empilhamento numa fila cheia é
-- recusado, mesmo com uma remoção no mesmo ciclo, e o aviso sai em o_refused.
-- i_flush esvazia a fila e tem prioridade sobre empilhar e remover.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity ir_fifo is
    generic (
        -- Largura de cada quadro, em bits.
        data_width : positive := 26;
        -- Quantidade máxima de quadros.
        depth      : positive := 8
    );
    port (
        -- Clock da fila.
        i_clk       : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst       : in    std_logic;
        -- Esvazia a fila.
        i_flush     : in    std_logic;
        -- Pedido de empilhar um quadro.
        i_push      : in    std_logic;
        -- Quadro a empilhar.
        i_push_data : in    std_logic_vector(data_width - 1 downto 0);
        -- Pedido de remover o quadro mais antigo.
        i_pop       : in    std_logic;
        -- Quadro mais antigo, ou zero com a fila vazia.
        o_pop_data  : out   std_logic_vector(data_width - 1 downto 0);
        -- Todas as posições ocupadas.
        o_full      : out   std_logic;
        -- Nenhum quadro armazenado.
        o_empty     : out   std_logic;
        -- Quantidade de quadros armazenados.
        o_level     : out   natural range 0 to depth;
        -- Empilhamento pedido numa fila cheia (o quadro é perdido).
        o_refused   : out   std_logic
    );
end entity ir_fifo;

architecture rtl of ir_fifo is

    -- Memória dos quadros.
    type memory_t is array (0 to depth - 1) of std_logic_vector(data_width - 1 downto 0);

    -- Conteúdo das posições.
    signal memory : memory_t := (others => (others => '0'));
    -- Posição do próximo quadro a remover.
    signal rd_ptr : natural range 0 to depth - 1 := 0;
    -- Posição do próximo quadro a empilhar.
    signal wr_ptr : natural range 0 to depth - 1 := 0;
    -- Quadros armazenados.
    signal count  : natural range 0 to depth := 0;
    -- Empilhamento aceito neste ciclo.
    signal do_push : std_logic;
    -- Remoção aceita neste ciclo.
    signal do_pop  : std_logic;

    -- Avança um ponteiro circular.
    function next_pointer (pointer : natural) return natural is
    begin

        if pointer = depth - 1 then
            return 0;
        end if;

        return pointer + 1;

    end function next_pointer;

begin

    do_push <= '1' when i_push = '1' and count < depth else '0';
    do_pop  <= '1' when i_pop = '1' and count > 0 else '0';

    o_empty   <= '1' when count = 0 else '0';
    o_full    <= '1' when count = depth else '0';
    o_level   <= count;
    o_refused <= '1' when i_push = '1' and count = depth else '0';
    o_pop_data <= memory(rd_ptr) when count > 0 else (others => '0');

    -- Ponteiros, contador e memória.
    p_storage : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            if i_rst = '1' or i_flush = '1' then
                rd_ptr <= 0;
                wr_ptr <= 0;
                count  <= 0;
            else
                if do_push = '1' then
                    memory(wr_ptr) <= i_push_data;
                    wr_ptr         <= next_pointer(wr_ptr);
                end if;

                if do_pop = '1' then
                    rd_ptr <= next_pointer(rd_ptr);
                end if;

                if do_push = '1' and do_pop = '0' then
                    count <= count + 1;
                elsif do_push = '0' and do_pop = '1' then
                    count <= count - 1;
                end if;
            end if;
        end if;

    end process p_storage;

end architecture rtl;
