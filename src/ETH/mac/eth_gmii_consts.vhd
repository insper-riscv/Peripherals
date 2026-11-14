-- =============================================================================
-- Constantes da seleção de velocidade e do caminho GMII do MAC Ethernet
--
-- Endereço e campos do registrador SPEED, códigos de velocidade, e o registrador
-- 17 do PHY que informa a velocidade negociada. Os códigos de velocidade
-- coincidem com os bits 15 a 14 do registrador 17 do Marvell 88E1111 (00 para
-- 10, 01 para 100 e 10 para 1000 Mbit/s). A posição dos campos do registrador 17
-- vem do datasheet do chip, que não está na pasta Docs: não confirmada no manual
-- da placa.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.eth_consts.all;

package eth_gmii_consts is

    -- Endereço de palavra do registrador SPEED (palavra 14).
    constant SPEED_ADDR : std_logic_vector(ETH_ADDR_WIDTH - 1 downto 0) := "001110";

    -- Código de velocidade: 10 Mbit/s.
    constant SPEED_10   : std_logic_vector(1 downto 0) := "00";
    -- Código de velocidade: 100 Mbit/s.
    constant SPEED_100  : std_logic_vector(1 downto 0) := "01";
    -- Código de velocidade: 1000 Mbit/s.
    constant SPEED_1000 : std_logic_vector(1 downto 0) := "10";

    -- Modo do registrador SPEED: velocidade lida do PHY por MDIO.
    constant MODE_AUTO : std_logic_vector(1 downto 0) := "00";
    -- Modo do registrador SPEED: velocidade forçada em 10 Mbit/s.
    constant MODE_10   : std_logic_vector(1 downto 0) := "01";
    -- Modo do registrador SPEED: velocidade forçada em 100 Mbit/s.
    constant MODE_100  : std_logic_vector(1 downto 0) := "10";
    -- Modo do registrador SPEED: velocidade forçada em 1000 Mbit/s.
    constant MODE_1000 : std_logic_vector(1 downto 0) := "11";

    -- Primeiro bit do campo ACTIVE (velocidade em uso) de SPEED.
    constant SPEED_ACTIVE_LSB   : natural := 4;
    -- Bit de SPEED: o PHY informou enlace ativo na última consulta.
    constant SPEED_LINK         : natural := 8;
    -- Bit de SPEED: o PHY informou full duplex na última consulta.
    constant SPEED_FULL_DUPLEX  : natural := 9;
    -- Bit de SPEED: o PHY informou velocidade e duplex resolvidos na última consulta.
    constant SPEED_RESOLVED     : natural := 10;

    -- Registrador do PHY com a velocidade e o enlace (PHY Specific Status, 17), não confirmado no manual.
    constant PHY_STATUS_REG : std_logic_vector(4 downto 0) := "10001";
    -- Bit do registrador 17 do PHY: velocidade e duplex resolvidos (bit 11).
    constant PHY_STATUS_RESOLVED : natural := 11;
    -- Bit do registrador 17 do PHY: duplex, '1' é full (bit 13).
    constant PHY_STATUS_DUPLEX   : natural := 13;
    -- Bit do registrador 17 do PHY: enlace em tempo real (bit 10).
    constant PHY_STATUS_LINK     : natural := 10;

    -- Largura do dado do PHY em função do modo: 8 bits no GMII, 4 bits no MII.
    function phy_data_width (
        gigabit : boolean
    ) return positive;

end package eth_gmii_consts;

package body eth_gmii_consts is

    function phy_data_width (
        gigabit : boolean
    ) return positive is
    begin
        if gigabit then
            return 8;
        end if;
        return 4;
    end function phy_data_width;

end package body eth_gmii_consts;
