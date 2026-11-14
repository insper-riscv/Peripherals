-- =============================================================================
-- Registrador DDR de saída da Intel (altddio_out)
--
-- Invólucro fino do megafunction altddio_out, a única instância dele no MAC
-- Ethernet. Exclusivo da FPGA (precisa da biblioteca altera_mf), então não é
-- analisado pelo GHDL da imagem de ferramentas; na simulação o arquivo de mesmo
-- nome da pasta sim faz o papel desta entidade. O megafunction registra
-- i_d_rise e i_d_fall na borda de subida de i_clk e coloca i_d_rise no pino na
-- metade alta do clock e i_d_fall na metade baixa.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

library altera_mf;
use altera_mf.altera_mf_components.all;

entity eth_ddr_out is
    generic (
        -- Largura em bits do dado.
        width : positive := 5
    );
    port (
        -- Clock da saída, nas duas bordas.
        i_clk    : in    std_logic;
        -- Dado da metade alta do clock.
        i_d_rise : in    std_logic_vector(width - 1 downto 0);
        -- Dado da metade baixa do clock.
        i_d_fall : in    std_logic_vector(width - 1 downto 0);
        -- Dado do pino.
        o_q      : out   std_logic_vector(width - 1 downto 0)
    );
end entity eth_ddr_out;

architecture rtl of eth_ddr_out is

begin

    u_ddio : component altddio_out
        generic map (
            width                  => width,
            extend_oe_disable      => "OFF",
            intended_device_family => "Cyclone IV E",
            invert_output          => "OFF",
            lpm_hint               => "UNUSED",
            lpm_type               => "altddio_out",
            oe_reg                 => "UNREGISTERED",
            power_up_high          => "OFF"
        )
        port map (
            datain_h => i_d_rise,
            datain_l => i_d_fall,
            outclock => i_clk,
            dataout  => o_q
        );

end architecture rtl;
