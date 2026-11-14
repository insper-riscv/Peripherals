-- =============================================================================
-- Seleção de velocidade do MAC Ethernet (domínio do sistema)
--
-- Guarda o registrador SPEED, que escolhe a velocidade do enlace: automática,
-- lida do PHY por MDIO, ou forçada em 10, 100 ou 1000 Mbit/s. No modo
-- automático consulta o registrador de estado do PHY (PHY_STATUS_REG) a cada
-- poll_cycles ciclos e adota a velocidade que ele informa quando o enlace está
-- ativo e a velocidade resolvida; sem consulta válida mantém a velocidade
-- anterior, que começa em 1000 Mbit/s. A consulta usa o mestre MDIO do MAC e
-- só começa com o mestre livre e sem pedido do programa; enquanto dura,
-- o_mdio_hold vale '1' e o MAC mostra o mestre ocupado ao programa.
--
-- Registrador SPEED (palavra SPEED_ADDR): bits 1 a 0 escolhem o modo (MODE_*) e
-- são os únicos de escrita; bits 5 a 4 mostram a velocidade em uso, e os bits 8,
-- 9 e 10 mostram enlace, full duplex e resolvido da última consulta que o PHY
-- respondeu.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.eth_consts.all;
use work.eth_gmii_consts.all;

entity eth_speed is
    generic (
        -- Endereço do PHY a consultar (PHYADDR do chip).
        phy_addr    : natural range 0 to 31 := 16;
        -- Ciclos do sistema entre o fim de uma consulta e o início da seguinte.
        poll_cycles : positive := 50_000
    );
    port (
        -- Clock do sistema.
        i_clk           : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst           : in    std_logic;
        -- Pulso de escrita do núcleo.
        i_write         : in    std_logic;
        -- Endereço de palavra.
        i_address       : in    std_logic_vector(ETH_ADDR_WIDTH - 1 downto 0);
        -- Dado de escrita.
        i_data_in       : in    std_logic_vector(31 downto 0);
        -- Palavra do registrador SPEED, a valer quando i_address é SPEED_ADDR.
        o_data_out      : out   std_logic_vector(31 downto 0);
        -- O programa inicia uma transação MDIO neste ciclo (pulso do registrador).
        i_sw_start      : in    std_logic;
        -- O mestre MDIO está ocupado.
        i_mdio_busy     : in    std_logic;
        -- Pulso de fim de transação do mestre MDIO.
        i_mdio_done     : in    std_logic;
        -- O PHY não respondeu à leitura.
        i_mdio_no_ack   : in    std_logic;
        -- Dado lido do PHY.
        i_mdio_rdata    : in    std_logic_vector(15 downto 0);
        -- Inicia a leitura do registrador de estado do PHY, pulso de um ciclo.
        o_mdio_start    : out   std_logic;
        -- Endereço do PHY consultado.
        o_mdio_phy_addr : out   std_logic_vector(4 downto 0);
        -- Endereço do registrador de estado do PHY.
        o_mdio_reg_addr : out   std_logic_vector(4 downto 0);
        -- A consulta usa o mestre MDIO e o programa deve vê-lo ocupado.
        o_mdio_hold     : out   std_logic;
        -- Velocidade em uso (SPEED_10, SPEED_100 ou SPEED_1000).
        o_speed         : out   std_logic_vector(1 downto 0)
    );
end entity eth_speed;

architecture rtl of eth_speed is

    -- Estados da consulta.
    type state_t is (S_IDLE, S_REQUEST, S_WAIT);

    -- Estado atual da consulta.
    signal state     : state_t := S_IDLE;
    -- Modo escolhido pelo programa.
    signal mode      : std_logic_vector(1 downto 0) := MODE_AUTO;
    -- Velocidade que o PHY informou por último.
    signal learned   : std_logic_vector(1 downto 0) := SPEED_1000;
    -- Enlace informado na última consulta respondida.
    signal link      : std_logic := '0';
    -- Full duplex informado na última consulta respondida.
    signal duplex    : std_logic := '0';
    -- Resolvido informado na última consulta respondida.
    signal resolved  : std_logic := '0';
    -- Ciclos até a próxima consulta.
    signal remaining : natural range 0 to poll_cycles := poll_cycles;
    -- Velocidade em uso.
    signal speed     : std_logic_vector(1 downto 0);
    -- Velocidade forçada pelo modo, o código do modo menos um.
    signal forced    : std_logic_vector(1 downto 0);

begin

    with mode select forced <=
        SPEED_10   when MODE_10,
        SPEED_100  when MODE_100,
        SPEED_1000 when others;

    speed <= learned when mode = MODE_AUTO else forced;

    p_fsm : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            if i_rst = '1' then
                state     <= S_IDLE;
                mode      <= MODE_AUTO;
                learned   <= SPEED_1000;
                link      <= '0';
                duplex    <= '0';
                resolved  <= '0';
                remaining <= poll_cycles;
            else
                if i_write = '1' and i_address = SPEED_ADDR then
                    mode <= i_data_in(1 downto 0);
                end if;

                case state is
                    when S_IDLE =>
                        if remaining > 0 then
                            remaining <= remaining - 1;
                        elsif i_mdio_busy = '0' and i_sw_start = '0' then
                            state <= S_REQUEST;
                        end if;

                    when S_REQUEST =>
                        -- Um pedido do programa no mesmo ciclo tem a vez, e a consulta recomeça depois.
                        if i_sw_start = '1' then
                            state     <= S_IDLE;
                            remaining <= poll_cycles;
                        else
                            state <= S_WAIT;
                        end if;

                    when S_WAIT =>
                        if i_mdio_done = '1' then
                            if i_mdio_no_ack = '0' then
                                link     <= i_mdio_rdata(PHY_STATUS_LINK);
                                duplex   <= i_mdio_rdata(PHY_STATUS_DUPLEX);
                                resolved <= i_mdio_rdata(PHY_STATUS_RESOLVED);
                                if i_mdio_rdata(PHY_STATUS_LINK) = '1' and i_mdio_rdata(PHY_STATUS_RESOLVED) = '1'
                                   and i_mdio_rdata(15 downto 14) /= "11" then
                                    learned <= i_mdio_rdata(15 downto 14);
                                end if;
                            end if;
                            state     <= S_IDLE;
                            remaining <= poll_cycles;
                        end if;
                end case;
            end if;
        end if;

    end process p_fsm;

    o_mdio_start    <= '1' when state = S_REQUEST and i_sw_start = '0' else '0';
    o_mdio_phy_addr <= std_logic_vector(to_unsigned(phy_addr, 5));
    o_mdio_reg_addr <= PHY_STATUS_REG;
    o_mdio_hold     <= '0' when state = S_IDLE else '1';
    o_speed         <= speed;

    o_data_out <= (31 downto 11 => '0') & resolved & duplex & link & "00" & speed & "00" & mode;

end architecture rtl;
