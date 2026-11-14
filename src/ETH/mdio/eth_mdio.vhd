-- =============================================================================
-- Mestre MDIO (IEEE 802.3, cláusula 22)
--
-- Executa uma transação de leitura ou de escrita de um registrador de 16 bits
-- de um PHY. O quadro tem 32 bits de preâmbulo em '1', o início 01, o código
-- de operação (01 escrita, 10 leitura), o endereço do PHY (5 bits), o endereço
-- do registrador (5 bits), a virada de barramento (TA) e 16 bits de dado, todos
-- com o bit mais significativo primeiro. MDC é gerado dividindo i_clk: cada
-- meio período dura half_period ciclos. O mestre muda MDIO na borda de descida
-- de MDC e lê o PHY na borda de subida, depois de sincronizar a entrada.
--
-- Na escrita o mestre dirige a virada de barramento (10). Na leitura solta a
-- linha no primeiro bit da virada, e o PHY responde '0' no segundo; se esse bit
-- chega em '1' ninguém respondeu e o_no_ack vale '1' até a próxima transação.
-- MDC fica em '0' fora das transações.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity eth_mdio is
    generic (
        -- Frequência do clock i_clk em hertz.
        clk_freq_hz : positive := 50_000_000;
        -- Frequência desejada de MDC em hertz.
        mdc_freq_hz : positive := 2_500_000
    );
    port (
        -- Clock do módulo.
        i_clk         : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst         : in    std_logic;
        -- Inicia uma transação, pulso de um ciclo, ignorado com o_busy em '1'.
        i_start       : in    std_logic;
        -- Operação: '1' escreve e '0' lê.
        i_write       : in    std_logic;
        -- Endereço do PHY.
        i_phy_addr    : in    std_logic_vector(4 downto 0);
        -- Endereço do registrador.
        i_reg_addr    : in    std_logic_vector(4 downto 0);
        -- Dado a escrever.
        i_wdata       : in    std_logic_vector(15 downto 0);
        -- Dado lido, válido depois de o_done.
        o_rdata       : out   std_logic_vector(15 downto 0);
        -- Transação em andamento.
        o_busy        : out   std_logic;
        -- Pulso de um ciclo ao fim da transação.
        o_done        : out   std_logic;
        -- O PHY não respondeu à última leitura.
        o_no_ack      : out   std_logic;
        -- Clock de gerenciamento.
        o_mdc         : out   std_logic;
        -- Entrada de dados do pino MDIO.
        i_mdio        : in    std_logic;
        -- Saída de dados para o pino MDIO.
        o_mdio_out    : out   std_logic;
        -- Habilita o driver do pino MDIO, '1' dirige a linha.
        o_mdio_oe     : out   std_logic
    );
end entity eth_mdio;

architecture rtl of eth_mdio is

    -- Ciclos de i_clk em cada meio período de MDC, arredondado para cima.
    constant HALF_PERIOD : positive := (clk_freq_hz + 2 * mdc_freq_hz - 1) / (2 * mdc_freq_hz);
    -- Bits de preâmbulo.
    constant PREAMBLE_BITS : natural := 32;
    -- Bits do quadro depois do preâmbulo.
    constant FRAME_BITS    : natural := 32;
    -- Índice, dentro do quadro, do primeiro bit da virada de barramento.
    constant TA_FIRST      : natural := 14;

    -- Entrada MDIO sincronizada, em vetor de um bit.
    signal mdio_sync : std_logic_vector(0 downto 0);
    -- Há transação em andamento.
    signal active    : std_logic := '0';
    -- Contador do meio período de MDC.
    signal divider   : natural range 0 to HALF_PERIOD - 1 := 0;
    -- Nível de MDC.
    signal mdc       : std_logic := '0';
    -- Bit em andamento, de 0 a 63.
    signal bit_idx   : natural range 0 to PREAMBLE_BITS + FRAME_BITS - 1 := 0;
    -- Quadro de 32 bits depois do preâmbulo, deslocado a cada bit.
    signal frame     : std_logic_vector(FRAME_BITS - 1 downto 0) := (others => '0');
    -- Operação de leitura em andamento.
    signal reading   : std_logic := '0';
    -- Dado lido, deslocado a cada bit de dado.
    signal rdata     : std_logic_vector(15 downto 0) := (others => '0');
    -- Saída do pino MDIO.
    signal mdio_out  : std_logic := '1';
    -- Habilitação do driver.
    signal mdio_oe   : std_logic := '0';
    -- Falta de resposta do PHY.
    signal no_ack    : std_logic := '0';
    -- Pulso de fim registrado.
    signal done      : std_logic := '0';

begin

    u_sync : entity work.synchronizer
        generic map (
            stages     => 2,
            data_width => 1
        )
        port map (
            i_clk  => i_clk,
            i_rst  => i_rst,
            i_d(0) => i_mdio,
            o_d    => mdio_sync
        );

    p_fsm : process (i_clk) is
        -- Índice do bit dentro do quadro de 32 bits.
        variable frame_idx : natural range 0 to FRAME_BITS - 1;
    begin

        if rising_edge(i_clk) then
            done <= '0';
            if i_rst = '1' then
                active   <= '0';
                mdc      <= '0';
                divider  <= 0;
                mdio_out <= '1';
                mdio_oe  <= '0';
                no_ack   <= '0';
            elsif active = '0' then
                mdc <= '0';
                if i_start = '1' then
                    active   <= '1';
                    divider  <= 0;
                    bit_idx  <= 0;
                    reading  <= not i_write;
                    no_ack   <= '0';
                    -- Início 01, operação, endereços e virada; o dado fecha o quadro.
                    if i_write = '1' then
                        frame <= "01" & "01" & i_phy_addr & i_reg_addr & "10" & i_wdata;
                    else
                        frame <= "01" & "10" & i_phy_addr & i_reg_addr & "10" & x"0000";
                    end if;
                    -- O primeiro bit do preâmbulo sai já com a linha dirigida em '1'.
                    mdio_out <= '1';
                    mdio_oe  <= '1';
                end if;
            else
                if divider < HALF_PERIOD - 1 then
                    divider <= divider + 1;
                else
                    divider <= 0;
                    mdc     <= not mdc;
                    if mdc = '1' then
                        -- Borda de descida: o próximo bit é colocado na linha.
                        if bit_idx = PREAMBLE_BITS + FRAME_BITS - 1 then
                            active  <= '0';
                            mdio_oe <= '0';
                            done    <= '1';
                        else
                            bit_idx <= bit_idx + 1;
                            if bit_idx + 1 >= PREAMBLE_BITS then
                                frame_idx := bit_idx + 1 - PREAMBLE_BITS;
                                mdio_out  <= frame(FRAME_BITS - 1 - frame_idx);
                                -- Na leitura, o mestre solta a linha no primeiro bit da virada.
                                if reading = '1' and frame_idx >= TA_FIRST then
                                    mdio_oe <= '0';
                                end if;
                            end if;
                        end if;
                    else
                        -- Borda de subida: o PHY é lido nos bits de virada e de dado.
                        if reading = '1' and bit_idx >= PREAMBLE_BITS + TA_FIRST then
                            if bit_idx = PREAMBLE_BITS + TA_FIRST + 1 then
                                no_ack <= mdio_sync(0);
                            elsif bit_idx > PREAMBLE_BITS + TA_FIRST + 1 then
                                rdata <= rdata(14 downto 0) & mdio_sync(0);
                            end if;
                        end if;
                    end if;
                end if;
            end if;
        end if;

    end process p_fsm;

    o_rdata    <= rdata;
    o_busy     <= active;
    o_done     <= done;
    o_no_ack   <= no_ack;
    o_mdc      <= mdc;
    o_mdio_out <= mdio_out;
    o_mdio_oe  <= mdio_oe;

end architecture rtl;
