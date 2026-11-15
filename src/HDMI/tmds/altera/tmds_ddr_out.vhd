-- =============================================================================
-- Registrador DDR de saída da Intel (altddio_out) do transmissor TMDS
--
-- Invólucro fino do megafunction altddio_out, a única instância dele no
-- transmissor TMDS. Exclusivo da FPGA (precisa da biblioteca altera_mf), então
-- não é analisado pelo GHDL da imagem de ferramentas; na simulação o arquivo de
-- mesmo nome da pasta sim faz o papel desta entidade. O megafunction registra
-- i_d_h e i_d_l na borda de subida de i_clk e coloca i_d_h no pino na metade
-- alta do clock e i_d_l na metade baixa.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

library altera_mf;
use altera_mf.altera_mf_components.all;

entity tmds_ddr_out is
    generic (
        -- Largura em bits do dado.
        width         : positive := 4;
        -- Família da FPGA, no texto que o megafunction aceita.
        device_family : string   := "Cyclone 10 LP"
    );
    port (
        -- Clock da saída, nas duas bordas.
        i_clk : in    std_logic;
        -- Dado da metade alta do clock.
        i_d_h : in    std_logic_vector(width - 1 downto 0);
        -- Dado da metade baixa do clock.
        i_d_l : in    std_logic_vector(width - 1 downto 0);
        -- Dado do pino.
        o_q   : out   std_logic_vector(width - 1 downto 0)
    );
end entity tmds_ddr_out;

architecture rtl of tmds_ddr_out is

begin

    u_ddio : component altddio_out
        generic map (
            width                  => width,
            extend_oe_disable      => "OFF",
            intended_device_family => device_family,
            invert_output          => "OFF",
            lpm_hint               => "UNUSED",
            lpm_type               => "altddio_out",
            oe_reg                 => "UNREGISTERED",
            power_up_high          => "OFF"
        )
        port map (
            datain_h => i_d_h,
            datain_l => i_d_l,
            outclock => i_clk,
            dataout  => o_q
        );

end architecture rtl;
