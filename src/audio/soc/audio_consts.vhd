-- =============================================================================
-- Constantes do periférico de áudio I2S
--
-- Endereços de palavra dos registradores, posições dos bits do registrador de
-- controle e do registrador de estado, e os códigos do campo de largura da
-- palavra de amostra. O mapa completo está documentado em docs/pt-br/audio.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

package audio_consts is

    -- Endereço do registrador de controle.
    constant ADDR_CONTROL    : std_logic_vector(3 downto 0) := x"0";
    -- Endereço do registrador de estado.
    constant ADDR_STATUS     : std_logic_vector(3 downto 0) := x"1";
    -- Endereço do registrador de níveis das filas.
    constant ADDR_LEVELS     : std_logic_vector(3 downto 0) := x"2";
    -- Endereço da porta de escrita da fila de reprodução.
    constant ADDR_TX_DATA    : std_logic_vector(3 downto 0) := x"3";
    -- Endereço da porta de leitura da fila de gravação.
    constant ADDR_RX_DATA    : std_logic_vector(3 downto 0) := x"4";
    -- Endereço dos limiares de interrupção das filas.
    constant ADDR_IRQ_LEVEL  : std_logic_vector(3 downto 0) := x"5";
    -- Endereço do passo do gerador fracionário do clock mestre.
    constant ADDR_XCK_STEP   : std_logic_vector(3 downto 0) := x"6";
    -- Endereço do módulo do gerador fracionário do clock mestre.
    constant ADDR_XCK_MOD    : std_logic_vector(3 downto 0) := x"7";
    -- Endereço do divisor do clock de bit.
    constant ADDR_BCLK_DIV   : std_logic_vector(3 downto 0) := x"8";
    -- Endereço do número de clocks de bit por canal.
    constant ADDR_SLOT_BITS  : std_logic_vector(3 downto 0) := x"9";
    -- Endereço da meio período do tom de teste, em quadros.
    constant ADDR_TONE_HALF  : std_logic_vector(3 downto 0) := x"A";
    -- Endereço da amplitude do tom de teste.
    constant ADDR_TONE_AMP   : std_logic_vector(3 downto 0) := x"B";
    -- Endereço do registrador com as profundidades das filas.
    constant ADDR_CONFIG     : std_logic_vector(3 downto 0) := x"C";
    -- Endereço do registrador de capacidades da instância.
    constant ADDR_CAPS       : std_logic_vector(3 downto 0) := x"D";

    -- Bit de CONTROL que habilita o serializador de reprodução.
    constant CTRL_TX_EN      : natural := 0;
    -- Bit de CONTROL que habilita o desserializador de gravação.
    constant CTRL_RX_EN      : natural := 1;
    -- Bit de CONTROL que habilita a interrupção por nível da fila de reprodução.
    constant CTRL_TX_IRQ_EN  : natural := 2;
    -- Bit de CONTROL que habilita a interrupção por nível da fila de gravação.
    constant CTRL_RX_IRQ_EN  : natural := 3;
    -- Bit de CONTROL que habilita a interrupção por subfluxo, sobrefluxo ou descarte.
    constant CTRL_ERR_IRQ_EN : natural := 4;
    -- Bit de CONTROL que habilita a geração dos clocks.
    constant CTRL_CLK_EN     : natural := 5;
    -- Bit de CONTROL que troca a fila de reprodução pelo tom de teste.
    constant CTRL_TONE_EN    : natural := 6;

    -- Bit de STATUS: a fila de reprodução aceita uma palavra.
    constant STAT_TX_NOT_FULL  : natural := 0;
    -- Bit de STATUS: a fila de gravação tem uma palavra.
    constant STAT_RX_NOT_EMPTY : natural := 1;
    -- Bit de STATUS: a fila de reprodução está vazia.
    constant STAT_TX_EMPTY     : natural := 2;
    -- Bit de STATUS: a fila de gravação está cheia.
    constant STAT_RX_FULL      : natural := 3;
    -- Bit de STATUS: um quadro começou sem duas palavras na fila de reprodução (limpa com 1).
    constant STAT_TX_UNDERFLOW : natural := 4;
    -- Bit de STATUS: um quadro recebido foi descartado com a fila de gravação cheia (limpa com 1).
    constant STAT_RX_OVERFLOW  : natural := 5;
    -- Bit de STATUS: uma escrita em TX_DATA foi descartada com a fila cheia (limpa com 1).
    constant STAT_TX_DROPPED   : natural := 6;

    -- Código do campo WORD para palavras de 16 bits.
    constant WORD_16 : natural := 0;
    -- Código do campo WORD para palavras de 24 bits.
    constant WORD_24 : natural := 1;
    -- Código do campo WORD para palavras de 32 bits.
    constant WORD_32 : natural := 2;

end package audio_consts;
