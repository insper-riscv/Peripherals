-- =============================================================================
-- Constantes e funções do receptor de infravermelho
--
-- Endereços de palavra dos registradores, posições de bit do controle, do
-- status e do quadro armazenado na FIFO, e as funções que convertem tempos em
-- ciclos de clock. O protocolo NEC mede todos os tempos em múltiplos de uma
-- unidade de 562,5 us (9 ms dividido por 16), e a função nec_unit_cycles dá
-- essa unidade em ciclos. Vale para clock abaixo de 238 MHz.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

package ir_consts is

    -- Endereço do registrador de controle.
    constant ADDR_CTRL      : std_logic_vector(2 downto 0) := "000";
    -- Endereço do registrador de status.
    constant ADDR_STATUS    : std_logic_vector(2 downto 0) := "001";
    -- Endereço do registrador de dados (cabeça da FIFO, a leitura remove o quadro).
    constant ADDR_DATA      : std_logic_vector(2 downto 0) := "010";
    -- Endereço da largura bruta do último pulso.
    constant ADDR_RAW_MARK  : std_logic_vector(2 downto 0) := "011";
    -- Endereço da largura bruta do último espaço.
    constant ADDR_RAW_SPACE : std_logic_vector(2 downto 0) := "100";

    -- Bit de controle que habilita o receptor.
    constant CTRL_EN       : natural := 0;
    -- Bit de controle que habilita a interrupção de quadro na FIFO.
    constant CTRL_FRAME_IE : natural := 1;
    -- Bit de controle que habilita a interrupção de erro e de estouro.
    constant CTRL_ERR_IE   : natural := 2;
    -- Bit de controle que aceita o NEC estendido de 16 bits de endereço.
    constant CTRL_EXT_EN   : natural := 3;
    -- Bit de controle que habilita a interrupção de medida bruta nova.
    constant CTRL_RAW_IE   : natural := 4;
    -- Bit de controle que esvazia a FIFO (escrita, lê zero).
    constant CTRL_FLUSH    : natural := 5;

    -- Bit de status com a FIFO não vazia.
    constant STAT_NOT_EMPTY : natural := 0;
    -- Bit de status com a FIFO cheia.
    constant STAT_FULL      : natural := 1;
    -- Bit de status pegajoso de quadro malformado.
    constant STAT_FRAME_ERR : natural := 2;
    -- Bit de status pegajoso de estouro da FIFO.
    constant STAT_OVERFLOW  : natural := 3;
    -- Bit de status com o nível da linha (1 com o receptor vendo pulso).
    constant STAT_LINE      : natural := 4;
    -- Bit de status pegajoso de medida bruta nova.
    constant STAT_RAW_NEW   : natural := 5;
    -- Posição do campo de nível da FIFO no status (oito bits).
    constant STAT_LEVEL_LSB : natural := 8;

    -- Largura do quadro armazenado: endereço (16), comando (8), repetição e estendido.
    constant FRAME_WIDTH : natural := 26;
    -- Posição do bit de repetição no quadro.
    constant FRAME_REPEAT : natural := 24;
    -- Posição do bit de NEC estendido no quadro.
    constant FRAME_EXT    : natural := 25;

    -- Converte microssegundos em ciclos de clock, no mínimo 1.
    function us_to_cycles (clk_freq_hz : positive; us : natural) return positive;

    -- Unidade de tempo do NEC (562,5 us) em ciclos de clock.
    function nec_unit_cycles (clk_freq_hz : positive) return positive;

end package ir_consts;

package body ir_consts is

    function us_to_cycles (clk_freq_hz : positive; us : natural) return positive is
        -- Quantidade de ciclos de clock do intervalo, antes do arredondamento.
        variable cycles : natural;
    begin

        cycles := (clk_freq_hz / 1000) * us / 1000;

        if cycles = 0 then
            return 1;
        end if;

        return cycles;

    end function us_to_cycles;

    function nec_unit_cycles (clk_freq_hz : positive) return positive is
        -- Quantidade de ciclos de clock da unidade de tempo do NEC.
        variable cycles : natural;
    begin

        cycles := clk_freq_hz / 16000 * 9;

        if cycles = 0 then
            return 1;
        end if;

        return cycles;

    end function nec_unit_cycles;

end package body ir_consts;
