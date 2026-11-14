-- =============================================================================
-- Constantes do periférico max10_adc
--
-- Largura do endereço, endereços de palavra dos registradores, posições dos
-- bits e a numeração dos canais do ADC do MAX 10. O mapa completo está em
-- docs/pt-br/ADC/max10_adc.md.
--
-- A numeração dos canais é a do comando do núcleo altera_modular_adc de um bloco
-- ADC: 0 é a entrada dedicada (ANAIN1 no primeiro bloco), 1 a 8 são os pinos de
-- função dupla (ADC1IN1 a ADC1IN8 no primeiro bloco), 9 a 16 só existem em
-- dispositivos com mais pinos de ADC e 17 é o sensor de temperatura do chip
-- (o comando 17 está no código-fonte do núcleo instalado com o Quartus). Quais
-- canais existem em cada placa é decisão da plataforma, pela máscara de
-- varredura.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

package max10_adc_consts is

    -- Largura do endereço local de palavra (32 palavras).
    constant ADC_ADDR_BITS : natural := 5;

    -- Quantidade de canais endereçáveis do núcleo (0 a 16 e o sensor de temperatura).
    constant ADC_CHANNELS     : natural := 18;
    -- Número do canal do sensor de temperatura no comando do núcleo.
    constant ADC_TEMP_CHANNEL : natural := 17;
    -- Largura em bits do número de canal do comando e da resposta do núcleo.
    constant ADC_CHANNEL_BITS : natural := 5;
    -- Largura em bits de uma amostra do conversor.
    constant ADC_SAMPLE_BITS  : natural := 12;

    -- Endereço do registrador de controle.
    constant ADDR_CTRL         : std_logic_vector(ADC_ADDR_BITS - 1 downto 0) := "00000";
    -- Endereço da máscara de canais da varredura.
    constant ADDR_MASK         : std_logic_vector(ADC_ADDR_BITS - 1 downto 0) := "00001";
    -- Endereço do período entre varreduras, em ciclos de clock.
    constant ADDR_PERIOD       : std_logic_vector(ADC_ADDR_BITS - 1 downto 0) := "00010";
    -- Endereço do registrador de estado.
    constant ADDR_STATUS       : std_logic_vector(ADC_ADDR_BITS - 1 downto 0) := "00011";
    -- Endereço de palavra do resultado do canal 0; o canal n fica em ADDR_CHANNEL_BASE + n.
    constant ADDR_CHANNEL_BASE : natural                                      := 8;

    -- Bit de CTRL que liga o sequenciador.
    constant CTRL_ENABLE_BIT     : natural := 0;
    -- Bit de CTRL que repete a varredura a cada período.
    constant CTRL_CONTINUOUS_BIT : natural := 1;
    -- Bit de CTRL que habilita a interrupção de fim de varredura.
    constant CTRL_IRQ_BIT        : natural := 2;
    -- Bit de CTRL que pede uma varredura única (pulso, lê como zero).
    constant CTRL_START_BIT      : natural := 3;

    -- Bit de STATUS: varredura em curso.
    constant ST_BUSY_BIT : natural := 0;
    -- Bit de STATUS: varredura terminada (sticky, escreve 1 para limpar).
    constant ST_DONE_BIT : natural := 1;
    -- Bit de STATUS: um início chegou com a varredura anterior ainda em curso (sticky, escreve 1 para limpar).
    constant ST_LATE_BIT : natural := 2;

    -- Bit do registrador de canal: resultado novo ainda não lido.
    constant CH_VALID_BIT   : natural := 12;
    -- Bit do registrador de canal: um resultado foi sobrescrito sem ser lido.
    constant CH_OVERRUN_BIT : natural := 13;

end package max10_adc_consts;
