-- =============================================================================
-- GPIO só de entrada, sem driver de pino
--
-- Um grupo de 1 a 32 pinos que a FPGA nunca dirige: cada pino de i_pins é só
-- uma entrada, sem tristate nem saída. Serve aos pinos que a placa liga a um
-- circuito externo (chaves DIP, botões e pinos de entrada dedicados) e que o
-- Quartus recusa como pino bidirecional ou de saída (erro 169009). O arquivo
-- de registradores é o do gpio_group com todos os pinos fixos em entrada, então
-- o mapa e o driver são os do GPIO:
--
--   0 DIR         lê zero, a direção é fixa em entrada
--   1 a 4         saída (OUT_*), guardam o valor escrito, que não chega a pino algum
--   5 IRQ_MASK    máscara global de interrupção por pino
--   6 RISE_MASK   máscara de subida
--   7 FALL_MASK   máscara de descida
--   8 IRQ_STAT    pendências; a leitura limpa os bits lidos
--   9 PINS        pinos sincronizados (dois flip-flops) e com a polaridade aplicada
--  10 LEVEL_MASK  modo de nível por pino
--
-- A interrupção é opcional: com IRQ_MASK em zero, que é o valor do reset,
-- nenhum pino pede interrupção e o bloco só entrega o nível dos pinos. A
-- escrita em DIR não tem efeito e a escrita nos registradores de saída só altera o
-- valor que eles leem de volta. O bloco usa
-- 16 palavras de endereço, uma janela de 64 bytes.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.config_pkg.all;

entity gpio_input is
    generic (
        -- Número de pinos do bloco, de 1 a 32.
        width      : positive range 1 to 32            := 32;
        -- Bit em '1' marca o pino ativo em nível baixo: o programa lê o nível invertido.
        active_low : std_logic_vector(width - 1 downto 0) := (others => '0')
    );
    port (
        -- Clock do módulo.
        i_clk      : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst      : in    std_logic;
        -- Dado de escrita vindo do processador.
        i_data_in  : in    word_t;
        -- Endereço de palavra dentro do bloco.
        i_address  : in    std_logic_vector(3 downto 0);
        -- Pulso de escrita do processador.
        i_write    : in    std_logic;
        -- Pulso de leitura do processador (a leitura de IRQ_STAT limpa as pendências).
        i_read     : in    std_logic;
        -- Dado de leitura, combinacional no endereço.
        o_data_out : out   word_t;
        -- Interrupção de nível, '1' enquanto algum pino tem pendência.
        o_irq      : out   std_logic;
        -- Nível dos pinos físicos, assíncrono.
        i_pins     : in    std_logic_vector(width - 1 downto 0)
    );
end entity gpio_input;

architecture rtl of gpio_input is

    -- Código de direção fixa em entrada de cada pino, repetido width vezes.
    function all_inputs return std_logic_vector is
        -- Vetor de códigos em construção.
        variable codes : std_logic_vector(2 * width - 1 downto 0);
    begin

        for i in 0 to width - 1 loop
            codes(2 * i + 1 downto 2 * i) := "01";
        end loop;

        return codes;

    end function all_inputs;

begin

    u_group : entity work.gpio_group
        generic map (
            width      => width,
            dir_modes  => all_inputs,
            active_low => active_low
        )
        port map (
            i_clk      => i_clk,
            i_rst      => i_rst,
            i_data_in  => i_data_in,
            i_address  => i_address,
            i_write    => i_write,
            i_read     => i_read,
            o_data_out => o_data_out,
            o_irq      => o_irq,
            i_pins     => i_pins,
            o_pins_drv => open,
            o_pins_en  => open
        );

end architecture rtl;
