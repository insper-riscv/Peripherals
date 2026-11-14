-- =============================================================================
-- Camada RGMII: conversão entre o RGMII do PHY e o GMII do MAC
--
-- Leva o GMII de oito bits do MAC (um byte por ciclo de 125 MHz) ao RGMII de
-- quatro bits por borda e traz o RGMII do PHY de volta ao GMII. Os registradores
-- DDR dos pinos ficam em eth_ddr_in e eth_ddr_out, e esta entidade só liga os
-- sinais e gera o clock e a habilitação do envio.
--
-- Envio (domínio de i_tx_clk, 125 MHz livre): a 1000 Mbit/s o nibble baixo do
-- byte sai na borda de subida e o alto na de descida, e TX_CTL leva TX_EN na
-- subida e TX_EN xor TX_ER na descida. A 100 e 10 Mbit/s o RGMII usa um nibble
-- por ciclo de TXC de 25 e 2,5 MHz: o MAC avança a cada o_tx_ce (um ciclo de cada
-- cinco ou de cada cinquenta de i_tx_clk), o nibble sai nas duas bordas e TXC é
-- sintetizado com ciclo de trabalho de 50 % pelas duas metades do ciclo de
-- i_tx_clk. TXC sai pelo registrador DDR clocado por i_tx_clk_dly, o mesmo
-- clock deslocado de 90 graus quando o MAC atrasa o clock em relação aos dados,
-- ou i_tx_clk quando o PHY insere o atraso. Com shifted_txc em true os
-- níveis de TXC são registrados uma vez no clock deslocado antes do registrador
-- DDR, e o caminho de i_tx_clk a esse registrador tem um quarto de ciclo para
-- fechar.
--
-- Recepção (domínio de i_rgmii_rxc, o RXC do PHY): o nibble da borda de subida é
-- RXD[3:0] do GMII, o da borda de descida é RXD[7:4], RX_DV é RX_CTL da subida e
-- RX_ER é RX_CTL da subida xor RX_CTL da descida. Os pares saem registrados na
-- borda de subida, um ciclo depois de chegarem. A 10 e 100 Mbit/s o MAC lê só
-- RXD[3:0]; RXD[7:4] é o nibble da borda de descida e é ignorado.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.eth_gmii_consts.all;

entity eth_rgmii is
    generic (
        -- Verdadeiro quando i_tx_clk_dly é i_tx_clk deslocado de 90 graus, falso quando é o próprio i_tx_clk.
        shifted_txc : boolean := true
    );
    port (
        -- Clock livre de 125 MHz do envio.
        i_tx_clk     : in    std_logic;
        -- Clock de TXC, i_tx_clk ou o mesmo clock deslocado de 90 graus.
        i_tx_clk_dly : in    std_logic;
        -- Velocidade do enlace no domínio do envio (SPEED_10, SPEED_100 ou SPEED_1000).
        i_tx_speed   : in    std_logic_vector(1 downto 0);
        -- Habilitação de avanço do MAC de envio.
        o_tx_ce      : out   std_logic;
        -- Dados do GMII vindos do MAC de envio (um nibble nos quatro bits baixos a 10 e 100 Mbit/s).
        i_gmii_txd   : in    std_logic_vector(7 downto 0);
        -- TX_EN do GMII.
        i_gmii_tx_en : in    std_logic;
        -- TX_ER do GMII.
        i_gmii_tx_er : in    std_logic;
        -- TXC do RGMII, pino ENETn_GTX_CLK.
        o_rgmii_txc  : out   std_logic;
        -- TXD do RGMII, pinos ENETn_TX_DATA.
        o_rgmii_txd  : out   std_logic_vector(3 downto 0);
        -- TX_CTL do RGMII, pino ENETn_TX_EN.
        o_rgmii_tx_ctl : out std_logic;

        -- RXC do RGMII, pino ENETn_RX_CLK, que também é o clock do receptor.
        i_rgmii_rxc     : in    std_logic;
        -- RXD do RGMII, pinos ENETn_RX_DATA.
        i_rgmii_rxd  : in    std_logic_vector(3 downto 0);
        -- RX_CTL do RGMII, pino ENETn_RX_DV.
        i_rgmii_rx_ctl : in  std_logic;
        -- Dados do GMII para o MAC de recepção.
        o_gmii_rxd   : out   std_logic_vector(7 downto 0);
        -- RX_DV do GMII.
        o_gmii_rx_dv : out   std_logic;
        -- RX_ER do GMII.
        o_gmii_rx_er : out   std_logic
    );
end entity eth_rgmii;

architecture rtl of eth_rgmii is

    -- Ciclos de i_tx_clk por ciclo de TXC na velocidade atual.
    signal period     : natural range 1 to 50;
    -- Posição do ciclo de i_tx_clk dentro do ciclo de TXC.
    signal phase      : natural range 0 to 49 := 0;
    -- Nível de TXC na metade alta do ciclo de i_tx_clk, metade que a subida de TXC abre.
    signal txc_high_h : std_logic;
    -- Nível de TXC na metade baixa do ciclo de i_tx_clk.
    signal txc_high_l : std_logic;
    -- Níveis de TXC das duas metades, entregues ao registrador DDR de TXC.
    signal txc_pair   : std_logic_vector(1 downto 0) := "00";
    -- Habilitação do MAC de envio, um ciclo antes de o ciclo de TXC começar.
    signal tx_ce      : std_logic;
    -- A velocidade é de 1000 Mbit/s.
    signal gigabit    : std_logic;

    -- Dado de envio da borda de subida: nibble baixo e TX_CTL.
    signal tx_rise    : std_logic_vector(4 downto 0);
    -- Dado de envio da borda de descida: nibble alto (ou o baixo repetido) e TX_CTL.
    signal tx_fall    : std_logic_vector(4 downto 0);
    -- Saída do registrador DDR de envio.
    signal tx_q       : std_logic_vector(4 downto 0);
    -- Saída do registrador DDR de TXC, em vetor de um bit.
    signal txc_q      : std_logic_vector(0 downto 0);
    -- Entrada do registrador DDR de recepção.
    signal rx_pins    : std_logic_vector(4 downto 0);
    -- Dado da borda de subida da recepção.
    signal rx_rise    : std_logic_vector(4 downto 0);
    -- Dado da borda de descida da recepção.
    signal rx_fall    : std_logic_vector(4 downto 0);

begin

    gigabit <= '1' when i_tx_speed = SPEED_1000 else '0';

    with i_tx_speed select period <=
        50 when SPEED_10,
        5  when SPEED_100,
        1  when others;

    -- O ciclo de TXC tem period ciclos de i_tx_clk e 2 * period metades; a primeira metade abre a subida.
    txc_high_h <= '1' when 2 * phase < period else '0';
    txc_high_l <= '1' when 2 * phase + 1 < period else '0';

    -- O MAC avança um ciclo antes de a fase zero chegar: o byte novo chega ao pino com a subida de TXC.
    tx_ce   <= '1' when phase >= period - 1 else '0';
    o_tx_ce <= tx_ce;

    p_phase : process (i_tx_clk) is
    begin

        if rising_edge(i_tx_clk) then
            if tx_ce = '1' then
                phase <= 0;
            else
                phase <= phase + 1;
            end if;
        end if;

    end process p_phase;

    -- A 1000 Mbit/s o nibble alto sai na borda de descida; abaixo disso repete-se o nibble baixo.
    tx_rise <= i_gmii_tx_en & i_gmii_txd(3 downto 0);
    tx_fall <= (i_gmii_tx_en xor i_gmii_tx_er) & i_gmii_txd(7 downto 4) when gigabit = '1' else
               (i_gmii_tx_en xor i_gmii_tx_er) & i_gmii_txd(3 downto 0);

    u_tx_ddr : entity work.eth_ddr_out
        generic map (
            width => 5
        )
        port map (
            i_clk    => i_tx_clk,
            i_d_rise => tx_rise,
            i_d_fall => tx_fall,
            o_q      => tx_q
        );

    g_txc_shifted : if shifted_txc generate

        -- Com TXC deslocado, os níveis passam por um registrador do clock deslocado, que os recebe 90 graus
        -- depois de lançados por i_tx_clk e os entrega ao registrador DDR um ciclo de TXC depois.
        p_txc_pair : process (i_tx_clk_dly) is
        begin

            if rising_edge(i_tx_clk_dly) then
                txc_pair <= txc_high_h & txc_high_l;
            end if;

        end process p_txc_pair;

    else generate

        txc_pair <= txc_high_h & txc_high_l;

    end generate g_txc_shifted;

    u_txc_ddr : entity work.eth_ddr_out
        generic map (
            width => 1
        )
        port map (
            i_clk       => i_tx_clk_dly,
            i_d_rise(0) => txc_pair(1),
            i_d_fall(0) => txc_pair(0),
            o_q         => txc_q
        );

    o_rgmii_txd    <= tx_q(3 downto 0);
    o_rgmii_tx_ctl <= tx_q(4);
    o_rgmii_txc    <= txc_q(0);

    rx_pins <= i_rgmii_rx_ctl & i_rgmii_rxd;

    u_rx_ddr : entity work.eth_ddr_in
        generic map (
            width => 5
        )
        port map (
            i_clk    => i_rgmii_rxc,
            i_d      => rx_pins,
            o_q_rise => rx_rise,
            o_q_fall => rx_fall
        );

    o_gmii_rxd   <= rx_fall(3 downto 0) & rx_rise(3 downto 0);
    o_gmii_rx_dv <= rx_rise(4);
    o_gmii_rx_er <= rx_rise(4) xor rx_fall(4);

end architecture rtl;
