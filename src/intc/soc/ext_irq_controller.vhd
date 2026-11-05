-- =============================================================================
-- Controlador de interrupção externa (MEIP)
--
-- Reúne as linhas de interrupção de nível dos periféricos num único pedido de
-- interrupção externa para o núcleo (MEIP). As linhas são sincronizadas ao
-- clock do núcleo e o software lê e mascara o estado pelo barramento de 32
-- bits, como nos outros periféricos.
--
-- Registradores (endereço de palavra):
--   0 PENDING   (somente leitura)  bit n é a linha n, sincronizada.
--   1 ENABLE    (leitura e escrita) bit n habilita a linha n; zero no reset.
--   2 SOURCE_ID (somente leitura)  índice da linha pendente e habilitada de
--                                  menor índice mais um, ou zero sem nenhuma.
--   3           reservado: lê zero e a escrita é ignorada.
--
-- Saída: o_irq_external vale '1' exatamente quando (PENDING and ENABLE) é
-- diferente de zero. A interrupção é de nível, sem trava: o software limpa a
-- causa no periférico de origem. A leitura de um registrador não tem efeito
-- colateral. Linhas acima de irq_count não existem e leem zero.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.ext_irq_consts.all;

entity ext_irq_controller is
    generic (
        -- Número de linhas de interrupção (1 a data_width).
        irq_count   : natural := 8;
        -- Estágios do sincronizador de cada linha (no mínimo 2).
        sync_stages : natural := 2;
        -- Largura do barramento de dados em bits.
        data_width  : natural := 32
    );
    port (
        -- Clock do módulo.
        i_clk          : in  std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst          : in  std_logic;
        -- Linhas de interrupção de nível dos periféricos, ativas em '1'.
        i_irq_lines    : in  std_logic_vector(irq_count - 1 downto 0);
        -- Dado de escrita vindo do processador.
        i_data_in      : in  std_logic_vector(data_width - 1 downto 0);
        -- Endereço de palavra vindo do processador.
        i_address      : in  std_logic_vector(EXT_IRQ_ADDR_WIDTH - 1 downto 0);
        -- Pulso de escrita do processador ('1' = escreve).
        i_write        : in  std_logic;
        -- Pulso de leitura do processador; a leitura não tem efeito colateral.
        i_read         : in  std_logic;
        -- Dado de leitura para o processador.
        o_data_out     : out std_logic_vector(data_width - 1 downto 0);
        -- Pedido de interrupção externa para o núcleo (MEIP), ativo em '1'.
        o_irq_external : out std_logic
    );
end entity ext_irq_controller;

architecture rtl of ext_irq_controller is

    -- Estado das linhas depois do sincronizador.
    signal pending_lines : std_logic_vector(irq_count - 1 downto 0);
    -- Registrador de habilitação por linha.
    signal enable_reg    : std_logic_vector(irq_count - 1 downto 0);
    -- Linhas pendentes e habilitadas.
    signal active_lines  : std_logic_vector(irq_count - 1 downto 0);
    -- Linha ativa de menor índice mais um, ou zero.
    signal source_id     : natural range 0 to irq_count;

begin

    assert irq_count >= 1 and irq_count <= data_width
        report "ext_irq_controller: irq_count deve estar entre 1 e data_width"
        severity failure;

    u_sync : entity work.synchronizer
        generic map (
            stages     => sync_stages,
            data_width => irq_count
        )
        port map (
            i_clk => i_clk,
            i_rst => i_rst,
            i_d   => i_irq_lines,
            o_d   => pending_lines
        );

    -- Escrita no ENABLE; as demais escritas são ignoradas.
    process (i_clk)
    begin
        if rising_edge(i_clk) then
            if i_rst = '1' then
                enable_reg <= (others => '0');
            elsif i_write = '1' and i_address = EXT_IRQ_ADDR_ENABLE then
                enable_reg <= i_data_in(irq_count - 1 downto 0);
            end if;
        end if;
    end process;

    active_lines   <= pending_lines and enable_reg;
    o_irq_external <= '1' when active_lines /= (active_lines'range => '0') else '0';

    -- Prioridade fixa: a linha de menor índice vence.
    process (active_lines)
        -- Resultado parcial da busca, da maior para a menor linha.
        variable winner : natural range 0 to irq_count;
    begin
        winner := 0;
        for n in irq_count - 1 downto 0 loop
            if active_lines(n) = '1' then
                winner := n + 1;
            end if;
        end loop;
        source_id <= winner;
    end process;

    -- Leitura combinacional pelo endereço.
    process (i_address, pending_lines, enable_reg, source_id)
    begin
        o_data_out <= (others => '0');
        if i_address = EXT_IRQ_ADDR_PENDING then
            o_data_out(irq_count - 1 downto 0) <= pending_lines;
        elsif i_address = EXT_IRQ_ADDR_ENABLE then
            o_data_out(irq_count - 1 downto 0) <= enable_reg;
        elsif i_address = EXT_IRQ_ADDR_SOURCE_ID then
            o_data_out <= std_logic_vector(to_unsigned(source_id, data_width));
        end if;
    end process;

end architecture rtl;
