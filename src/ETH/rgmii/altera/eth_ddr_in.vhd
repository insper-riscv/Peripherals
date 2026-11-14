-- =============================================================================
-- Registrador DDR de entrada da Intel (altddio_in)
--
-- Invólucro fino do megafunction altddio_in, a única instância dele no MAC
-- Ethernet. Exclusivo da FPGA (precisa da biblioteca altera_mf), então não é
-- analisado pelo GHDL da imagem de ferramentas; na simulação o arquivo de mesmo
-- nome da pasta sim faz o papel desta entidade. O megafunction entrega, a cada
-- borda de subida, o dado dessa mesma borda em dataout_h e o da borda de
-- descida anterior em dataout_l; o par de um ciclo de i_clk (o dado da borda de
-- subida e o da borda de descida que a segue) só fica alinhado depois de
-- registrar dataout_h uma vez, o que este invólucro faz. Assim o_q_rise e
-- o_q_fall saem juntos, um ciclo depois do par chegar ao pino, como no modelo
-- da simulação.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

library altera_mf;
use altera_mf.altera_mf_components.all;

entity eth_ddr_in is
    generic (
        -- Largura em bits do dado.
        width : positive := 5
    );
    port (
        -- Clock de amostragem nas duas bordas.
        i_clk    : in    std_logic;
        -- Dado do pino.
        i_d      : in    std_logic_vector(width - 1 downto 0);
        -- Dado amostrado na borda de subida.
        o_q_rise : out   std_logic_vector(width - 1 downto 0);
        -- Dado amostrado na borda de descida que segue a de subida.
        o_q_fall : out   std_logic_vector(width - 1 downto 0)
    );
end entity eth_ddr_in;

architecture rtl of eth_ddr_in is

    -- Dado da borda de subida, na saída do megafunction.
    signal rise_raw : std_logic_vector(width - 1 downto 0);
    -- Dado da borda de subida, atrasado de um ciclo para alinhar com o da borda de descida.
    signal rise_q   : std_logic_vector(width - 1 downto 0) := (others => '0');

begin

    u_ddio : component altddio_in
        generic map (
            width                  => width,
            invert_input_clocks    => "OFF",
            intended_device_family => "Cyclone IV E",
            lpm_hint               => "UNUSED",
            lpm_type               => "altddio_in"
        )
        port map (
            datain    => i_d,
            inclock   => i_clk,
            dataout_h => rise_raw,
            dataout_l => o_q_fall
        );

    p_align : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            rise_q <= rise_raw;
        end if;

    end process p_align;

    o_q_rise <= rise_q;

end architecture rtl;
