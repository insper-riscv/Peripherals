-- =============================================================================
-- Memória de duas portas com clocks independentes e escrita por faixas de bytes
--
-- Porta de escrita no clock i_wclk, com uma habilitação por faixa (i_we), e
-- porta de leitura no clock i_rclk, com saída registrada (o_rdata vale o dado
-- do endereço i_raddr da borda anterior). Cada faixa é uma matriz própria de
-- lane_width bits, o que o Quartus mapeia em blocos M10K com habilitação de
-- bytes. A leitura e a escrita simultâneas do mesmo endereço em clocks
-- diferentes devolvem o dado antigo ou o novo, sem efeito no restante do
-- circuito (no_rw_check).
--
-- A memória lê e escreve só endereços de 0 a depth - 1; quem a instancia deve
-- garantir a faixa.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity video_dpram is
    generic (
        -- Número de faixas de escrita independentes.
        lanes      : positive := 4;
        -- Largura de cada faixa em bits.
        lane_width : positive := 8;
        -- Número de palavras da memória.
        depth      : positive := 256;
        -- Largura do endereço em bits.
        addr_width : positive := 8
    );
    port (
        -- Clock da porta de escrita.
        i_wclk  : in    std_logic;
        -- Habilitação de escrita de cada faixa ('1' = grava a faixa).
        i_we    : in    std_logic_vector(lanes - 1 downto 0);
        -- Endereço de escrita.
        i_waddr : in    std_logic_vector(addr_width - 1 downto 0);
        -- Dado de escrita, as faixas lado a lado (faixa 0 nos bits menos significativos).
        i_wdata : in    std_logic_vector(lanes * lane_width - 1 downto 0);

        -- Clock da porta de leitura.
        i_rclk  : in    std_logic;
        -- Endereço de leitura.
        i_raddr : in    std_logic_vector(addr_width - 1 downto 0);
        -- Dado lido, registrado em i_rclk (latência de um ciclo).
        o_rdata : out   std_logic_vector(lanes * lane_width - 1 downto 0)
    );
end entity video_dpram;

architecture rtl of video_dpram is

begin

    gen_lane : for lane in 0 to lanes - 1 generate

        -- Matriz de uma faixa, uma palavra de lane_width bits por endereço.
        type lane_mem_t is array(0 to depth - 1) of std_logic_vector(lane_width - 1 downto 0);

        -- Conteúdo da faixa, zerado ao energizar.
        signal mem : lane_mem_t := (others => (others => '0'));

        -- Pede ao Quartus blocos M10K sem lógica de bypass entre as portas.
        attribute ramstyle : string;
        attribute ramstyle of mem : signal is "M10K, no_rw_check";

    begin

        p_write : process (i_wclk) is
        begin

            if rising_edge(i_wclk) then
                if i_we(lane) = '1' then
                    mem(to_integer(unsigned(i_waddr))) <= i_wdata(lane * lane_width + lane_width - 1 downto lane * lane_width);
                end if;
            end if;

        end process p_write;

        p_read : process (i_rclk) is
        begin

            if rising_edge(i_rclk) then
                o_rdata(lane * lane_width + lane_width - 1 downto lane * lane_width) <= mem(to_integer(unsigned(i_raddr)));
            end if;

        end process p_read;

    end generate gen_lane;

end architecture rtl;
