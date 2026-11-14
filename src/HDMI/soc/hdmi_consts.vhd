-- =============================================================================
-- Constantes do periférico de saída HDMI
--
-- Endereços de palavra dos registradores próprios do HDMI (os registradores do
-- vídeo, a paleta e a janela do framebuffer são os do periférico de vídeo, em
-- video_consts), posição dos bits de estado e de interrupção, e as funções que
-- interpretam a tabela de inicialização do transmissor ADV7513 recebida por
-- generic. A tabela é uma cadeia de caracteres com quatro dígitos
-- hexadecimais por entrada: os dois primeiros são o endereço do registrador do
-- chip e os dois últimos o valor a escrever, por exemplo "9803" escreve 0x03
-- no registrador 0x98.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

package hdmi_consts is

    -- Endereço de palavra do registrador de modo (somente leitura).
    constant ADDR_HDMI_MODE      : natural := 8;
    -- Endereço de palavra do registrador de estado do transmissor (somente leitura).
    constant ADDR_HDMI_STATUS    : natural := 9;
    -- Endereço de palavra da habilitação das interrupções (leitura e escrita).
    constant ADDR_HDMI_IRQ_EN    : natural := 10;
    -- Endereço de palavra das interrupções pendentes (leitura; escrever 1 limpa).
    constant ADDR_HDMI_IRQ_PEND  : natural := 11;
    -- Endereço de palavra do controle do sequenciador de inicialização (escrita do bit 0 reinicia).
    constant ADDR_HDMI_SEQ_CTRL  : natural := 12;
    -- Endereço de palavra do contador do sequenciador (somente leitura).
    constant ADDR_HDMI_SEQ_COUNT : natural := 13;
    -- Endereço de palavra do clock de pixel do modo em kHz (somente leitura).
    constant ADDR_HDMI_PIXEL_KHZ : natural := 14;

    -- Bit do estado que vale '1' enquanto o pino de interrupção do transmissor está ativo.
    constant STATUS_INT_BIT  : natural := 0;
    -- Bit do estado que vale '1' enquanto o sequenciador de inicialização escreve no chip.
    constant STATUS_BUSY_BIT : natural := 1;
    -- Bit do estado que vale '1' depois que o sequenciador terminou a tabela.
    constant STATUS_DONE_BIT : natural := 2;
    -- Bit do estado que vale '1' se alguma escrita da tabela não recebeu confirmação (ACK) do chip.
    constant STATUS_NACK_BIT : natural := 3;
    -- Bit do estado que vale '1' quando o sequenciador de inicialização existe nesta instância.
    constant STATUS_INIT_BIT : natural := 4;

    -- Bit de interrupção do fim de quadro (habilitação e pendência).
    constant IRQ_FRAME_BIT : natural := 0;
    -- Bit de interrupção da ativação do pino de interrupção do transmissor (habilitação e pendência).
    constant IRQ_INT_BIT   : natural := 1;

    -- Caracteres hexadecimais de cada entrada da tabela de inicialização.
    constant ENTRY_CHARS       : positive := 4;
    -- Maior número de entradas da tabela (o contador do sequenciador tem 8 bits).
    constant MAX_INIT_ENTRIES  : positive := 255;
    -- Bits de cada pixel do framebuffer no formato direto (RGB565).
    constant DIRECT_PIXEL_BITS : positive := 16;
    -- Bits de cada canal no cálculo do tamanho do framebuffer direto (o tamanho depende só dos 16 bits do pixel).
    constant DIRECT_SIZE_CHANNEL_BITS : positive := 5;
    -- Bits de cada canal que sai para o transmissor.
    constant OUT_CHANNEL_BITS  : positive := 8;

    -- Número de entradas da tabela de inicialização (quatro caracteres por entrada).

    function init_count (table : string) return natural;

    -- Indica se a tabela tem um número inteiro de entradas, só dígitos hexadecimais e cabe no contador.

    function is_valid_table (table : string) return boolean;

    -- Entrada de índice dado da tabela, com o registrador nos bits 15:8 e o valor nos bits 7:0.

    function init_word (table : string; index : natural) return std_logic_vector;

    -- Largura de canal que dimensiona o framebuffer: 8 no indexado (paleta de 24 bits), 5 no direto (16 bits por pixel).

    function size_channel_bits (pixel_format : string) return positive;

end package hdmi_consts;

package body hdmi_consts is

    -- Valor de um dígito hexadecimal, ou 16 se o caractere não é um dígito.
    function hex_digit (c : character) return natural is

    begin

        case c is
            when '0' to '9' =>
                return character'pos(c) - character'pos('0');
            when 'a' to 'f' =>
                return character'pos(c) - character'pos('a') + 10;
            when 'A' to 'F' =>
                return character'pos(c) - character'pos('A') + 10;
            when others =>
                return 16;
        end case;

    end function hex_digit;

    function init_count (table : string) return natural is

    begin

        return table'length / ENTRY_CHARS;

    end function init_count;

    function is_valid_table (table : string) return boolean is

    begin

        if table'length mod ENTRY_CHARS /= 0 or table'length / ENTRY_CHARS > MAX_INIT_ENTRIES then
            return false;
        end if;

        for i in table'range loop

            if hex_digit(table(i)) > 15 then
                return false;
            end if;

        end loop;

        return true;

    end function is_valid_table;

    function init_word (table : string; index : natural) return std_logic_vector is

        -- Posição do primeiro caractere da entrada na cadeia.
        variable first : natural;
        -- Entrada convertida.
        variable word  : std_logic_vector(15 downto 0) := (others => '0');
        -- Valor de um dígito.
        variable digit : natural;

    begin

        first := table'left + index * ENTRY_CHARS;

        for i in 0 to ENTRY_CHARS - 1 loop

            digit := hex_digit(table(first + i));
            for b in 0 to 3 loop

                if (digit / 2 ** b) mod 2 = 1 then
                    word(15 - 4 * i - (3 - b)) := '1';
                end if;

            end loop;

        end loop;

        return word;

    end function init_word;

    function size_channel_bits (pixel_format : string) return positive is

    begin

        if pixel_format = "indexed" then
            return OUT_CHANNEL_BITS;
        else
            return DIRECT_SIZE_CHANNEL_BITS;
        end if;

    end function size_channel_bits;

end package body hdmi_consts;
