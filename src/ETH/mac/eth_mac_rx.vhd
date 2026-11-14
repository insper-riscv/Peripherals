-- =============================================================================
-- Receptor MAC em MII (domínio do RX_CLK do PHY)
--
-- Procura o SFD (nibble 0xD depois de nibbles 0x5) enquanto RX_DV está ativo,
-- junta os nibbles em bytes (o baixo chega primeiro), confere o CRC-32 sobre
-- todos os bytes, FCS incluso, e entrega os bytes do quadro sem o FCS à FIFO
-- assíncrona. Uma linha de atraso de quatro bytes retém o FCS. Ao fim do quadro
-- (RX_DV volta a '0') entrega uma palavra final com o bit 8 em '1' e as flags
-- do quadro nos bits 5 a 0 (índices RXF_* de eth_consts).
--
-- Palavra da FIFO: bit 8 em '0' é um byte nos bits 7 a 0; bit 8 em '1' é a
-- palavra final. Com a FIFO cheia o byte é perdido e a flag de overflow marca o
-- quadro; a palavra final espera espaço e, enquanto espera, um quadro novo é
-- ignorado e conta como perdido na flag RXF_MISSED do próximo quadro.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.eth_consts.all;

entity eth_mac_rx is
    port (
        -- Clock do domínio (RX_CLK do PHY).
        i_clk     : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst     : in    std_logic;
        -- Dados do MII vindos do PHY.
        i_rxd     : in    std_logic_vector(3 downto 0);
        -- RX_DV do MII.
        i_rx_dv   : in    std_logic;
        -- RX_ER do MII.
        i_rx_er   : in    std_logic;
        -- Escrita de uma palavra na FIFO.
        o_wr_en   : out   std_logic;
        -- Palavra a escrever na FIFO.
        o_wr_data : out   std_logic_vector(8 downto 0);
        -- A FIFO está cheia.
        i_full    : in    std_logic
    );
end entity eth_mac_rx;

architecture rtl of eth_mac_rx is

    -- Estados do receptor.
    type state_t is (S_WAIT, S_DATA, S_IGNORE);
    -- Linha de atraso de quatro bytes.
    type delay_t is array(0 to 3) of std_logic_vector(7 downto 0);

    -- Estado atual.
    signal state        : state_t := S_WAIT;
    -- Dados do MII registrados.
    signal rxd_q        : std_logic_vector(3 downto 0) := (others => '0');
    -- RX_DV registrado.
    signal dv_q         : std_logic := '0';
    -- RX_ER registrado.
    signal er_q         : std_logic := '0';
    -- Nibble baixo do byte em montagem.
    signal low_nibble   : std_logic_vector(3 downto 0) := (others => '0');
    -- O próximo nibble é o alto.
    signal phase        : std_logic := '0';
    -- Linha de atraso que retém o FCS.
    signal delay        : delay_t := (others => (others => '0'));
    -- Bytes na linha de atraso.
    signal delay_count  : natural range 0 to 4 := 0;
    -- Bytes recebidos no quadro, saturado em MIN_RX_BYTES.
    signal total_bytes  : natural range 0 to MIN_RX_BYTES := 0;
    -- Flags do quadro em andamento.
    signal flags        : std_logic_vector(5 downto 0) := (others => '0');
    -- Há uma palavra final esperando espaço na FIFO.
    signal pending_last : std_logic := '0';
    -- Flags da palavra final que espera.
    signal pending_flags : std_logic_vector(5 downto 0) := (others => '0');
    -- Um quadro foi ignorado desde a última palavra final.
    signal missed       : std_logic := '0';
    -- O CRC do quadro é um resíduo íntegro.
    signal residue_ok   : std_logic;
    -- O CRC volta ao valor inicial.
    signal crc_clear    : std_logic;
    -- O CRC absorve o nibble deste ciclo.
    signal crc_enable   : std_logic;

    -- A FIFO está cheia ou vai ficar com a escrita já registrada.
    signal full_now     : std_logic;

    -- Escrita registrada na FIFO.
    signal wr_en_reg    : std_logic := '0';
    -- Palavra registrada para a FIFO.
    signal wr_data_reg  : std_logic_vector(8 downto 0) := (others => '0');

begin

    full_now <= i_full or wr_en_reg;

    crc_clear  <= '1' when state /= S_DATA else '0';
    crc_enable <= '1' when state = S_DATA and dv_q = '1' else '0';

    u_crc : entity work.eth_crc32
        port map (
            i_clk        => i_clk,
            i_rst        => i_rst,
            i_clear      => crc_clear,
            i_enable     => crc_enable,
            i_nibble     => rxd_q,
            o_crc        => open,
            o_residue_ok => residue_ok
        );

    p_fsm : process (i_clk) is
        -- Byte completo no ciclo.
        variable byte      : std_logic_vector(7 downto 0);
        -- Flags do quadro que termina neste ciclo.
        variable end_flags : std_logic_vector(5 downto 0);
    begin

        if rising_edge(i_clk) then
            rxd_q     <= i_rxd;
            dv_q      <= i_rx_dv;
            er_q      <= i_rx_er;
            wr_en_reg <= '0';

            if i_rst = '1' then
                state        <= S_WAIT;
                phase        <= '0';
                delay_count  <= 0;
                total_bytes  <= 0;
                flags        <= (others => '0');
                pending_last <= '0';
                missed       <= '0';
                dv_q         <= '0';
            else
                -- Palavra final que esperava espaço.
                if pending_last = '1' and full_now = '0' then
                    wr_en_reg    <= '1';
                    wr_data_reg  <= '1' & "00" & pending_flags;
                    pending_last <= '0';
                end if;

                case state is
                    when S_WAIT =>
                        phase       <= '0';
                        delay_count <= 0;
                        total_bytes <= 0;
                        flags       <= (others => '0');
                        if dv_q = '1' then
                            if rxd_q = NIBBLE_SFD_HIGH then
                                if pending_last = '1' then
                                    missed <= '1';
                                    state  <= S_IGNORE;
                                else
                                    state <= S_DATA;
                                end if;
                            elsif rxd_q /= NIBBLE_PREAMBLE then
                                state <= S_IGNORE;
                            end if;
                        end if;

                    when S_IGNORE =>
                        if dv_q = '0' then
                            state <= S_WAIT;
                        end if;

                    when S_DATA =>
                        if dv_q = '1' then
                            if er_q = '1' then
                                flags(RXF_PHY) <= '1';
                            end if;
                            if phase = '0' then
                                low_nibble <= rxd_q;
                                phase      <= '1';
                            else
                                phase <= '0';
                                byte  := rxd_q & low_nibble;
                                if total_bytes < MIN_RX_BYTES then
                                    total_bytes <= total_bytes + 1;
                                end if;
                                delay(0) <= byte;
                                for i in 1 to 3 loop
                                    delay(i) <= delay(i - 1);
                                end loop;
                                if delay_count < 4 then
                                    delay_count <= delay_count + 1;
                                elsif full_now = '1' or pending_last = '1' then
                                    flags(RXF_OVERFLOW) <= '1';
                                else
                                    wr_en_reg   <= '1';
                                    wr_data_reg <= '0' & delay(3);
                                end if;
                            end if;
                        else
                            end_flags := flags;
                            end_flags(RXF_CRC)   := not residue_ok;
                            end_flags(RXF_ALIGN) := phase;
                            if total_bytes < MIN_RX_BYTES then
                                end_flags(RXF_RUNT) := '1';
                            end if;
                            end_flags(RXF_MISSED) := missed;
                            missed <= '0';
                            if full_now = '1' or pending_last = '1' then
                                pending_last  <= '1';
                                pending_flags <= end_flags;
                            else
                                wr_en_reg   <= '1';
                                wr_data_reg <= '1' & "00" & end_flags;
                            end if;
                            state <= S_WAIT;
                        end if;
                end case;
            end if;
        end if;

    end process p_fsm;

    o_wr_en   <= wr_en_reg;
    o_wr_data <= wr_data_reg;

end architecture rtl;
