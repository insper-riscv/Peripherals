-- =============================================================================
-- Constantes do controlador de interrupção externa
--
-- Endereços de palavra dos registradores de ext_irq_controller. Os testes, a
-- prova formal e a documentação usam os mesmos valores.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

package ext_irq_consts is

    -- Largura do endereço de palavra do controlador.
    constant EXT_IRQ_ADDR_WIDTH : natural := 2;

    -- Endereço de PENDING: estado sincronizado das linhas (somente leitura).
    constant EXT_IRQ_ADDR_PENDING : std_logic_vector(EXT_IRQ_ADDR_WIDTH - 1 downto 0) := "00";

    -- Endereço de ENABLE: máscara de habilitação por linha (leitura e escrita).
    constant EXT_IRQ_ADDR_ENABLE : std_logic_vector(EXT_IRQ_ADDR_WIDTH - 1 downto 0) := "01";

    -- Endereço de SOURCE_ID: linha pendente e habilitada de menor índice, mais um (somente leitura).
    constant EXT_IRQ_ADDR_SOURCE_ID : std_logic_vector(EXT_IRQ_ADDR_WIDTH - 1 downto 0) := "10";

end package ext_irq_consts;
