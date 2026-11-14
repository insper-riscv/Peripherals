-- =============================================================================
-- Transmissor MAC em MII (domínio do TX_CLK do PHY)
--
-- A cada pulso de i_start envia um quadro lido do buffer de envio: preâmbulo de
-- sete bytes 0x55, SFD 0xD5, os i_length bytes do buffer, zeros até 60 bytes
-- quando o quadro é mais curto, o FCS (CRC-32 do destino até o preenchimento,
-- complementado, byte menos significativo primeiro) e o intervalo de 96 bits
-- entre quadros. Cada byte sai em dois nibbles, o baixo primeiro, como o MII
-- exige. As saídas são registradas.
--
-- O buffer é lido com latência de um ciclo: o endereço de o_ram_addr é o da
-- palavra do próximo byte, parado por dois ciclos antes de i_ram_data ser
-- usado. i_length deve valer de 1 ao tamanho do buffer em bytes e ficar
-- estável durante o envio. o_done dá um pulso quando o intervalo termina e o
-- transmissor volta a aceitar i_start.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.eth_consts.all;

entity eth_mac_tx is
    generic (
        -- Largura do endereço de palavra do buffer de envio.
        buffer_addr_bits : positive := 9
    );
    port (
        -- Clock do domínio (TX_CLK do PHY).
        i_clk      : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst      : in    std_logic;
        -- Inicia um quadro, pulso de um ciclo.
        i_start    : in    std_logic;
        -- Comprimento do quadro em bytes, sem FCS e sem preenchimento.
        i_length   : in    std_logic_vector(buffer_addr_bits + 2 downto 0);
        -- Endereço de palavra lido no buffer.
        o_ram_addr : out   std_logic_vector(buffer_addr_bits - 1 downto 0);
        -- Palavra lida, um ciclo depois do endereço.
        i_ram_data : in    std_logic_vector(31 downto 0);
        -- Dados do MII para o PHY.
        o_txd      : out   std_logic_vector(3 downto 0);
        -- Habilitação de transmissão do MII.
        o_tx_en    : out   std_logic;
        -- Transmissão em andamento, inclusive o intervalo entre quadros.
        o_busy     : out   std_logic;
        -- Pulso de um ciclo ao fim do quadro e do intervalo.
        o_done     : out   std_logic
    );
end entity eth_mac_tx;

architecture rtl of eth_mac_tx is

    -- Estados do sequenciador.
    type state_t is (S_IDLE, S_PREAMBLE, S_DATA, S_FCS, S_GAP);

    -- Estado atual.
    signal state      : state_t := S_IDLE;
    -- Contador de nibbles do estado atual.
    signal count      : natural range 0 to 31 := 0;
    -- Índice do byte em envio.
    signal byte_idx   : unsigned(buffer_addr_bits + 2 downto 0) := (others => '0');
    -- Índice do byte lido da memória, sempre um à frente de byte_idx.
    signal fetch_idx  : unsigned(buffer_addr_bits + 2 downto 0) := (others => '0');
    -- Total de bytes antes do FCS, com o preenchimento.
    signal total      : unsigned(buffer_addr_bits + 2 downto 0) := (others => '0');
    -- Comprimento do quadro guardado no início do envio.
    signal length     : unsigned(buffer_addr_bits + 2 downto 0) := (others => '0');
    -- Byte em envio.
    signal cur_byte   : std_logic_vector(7 downto 0) := (others => '0');
    -- Fase do byte, '0' envia o nibble baixo e '1' o alto.
    signal phase      : std_logic := '0';
    -- Nibble que o CRC absorve neste ciclo.
    signal crc_nibble : std_logic_vector(3 downto 0);
    -- O CRC absorve o nibble deste ciclo.
    signal crc_enable : std_logic;
    -- O CRC volta ao valor inicial.
    signal crc_clear  : std_logic;
    -- Estado do CRC.
    signal crc        : std_logic_vector(31 downto 0);
    -- Byte da memória indicado por fetch_idx, ou zero no preenchimento.
    signal fetch_byte : std_logic_vector(7 downto 0);
    -- Palavra de fetch_idx dividida em quatro bytes.
    signal lane       : std_logic_vector(7 downto 0);

    -- Complemento do CRC deslocado para deixar o nibble de count nos quatro bits baixos.
    signal fcs_shifted : unsigned(31 downto 0);
    -- Nibble do FCS indicado por count, o complemento do CRC a partir do nibble menos significativo.
    signal fcs_nibble : std_logic_vector(3 downto 0);

    -- Saída registrada do MII.
    signal txd_reg    : std_logic_vector(3 downto 0) := (others => '0');
    -- Habilitação registrada do MII.
    signal tx_en_reg  : std_logic := '0';
    -- Pulso de fim registrado.
    signal done_reg   : std_logic := '0';

begin

    -- A palavra lida contém o byte que fetch_idx indica pelos dois bits baixos.
    with fetch_idx(1 downto 0) select lane <=
        i_ram_data(7 downto 0)   when "00",
        i_ram_data(15 downto 8)  when "01",
        i_ram_data(23 downto 16) when "10",
        i_ram_data(31 downto 24) when others;

    -- Depois do fim do quadro do software, o byte é zero (preenchimento).
    fetch_byte <= lane when fetch_idx < length else (others => '0');

    fcs_shifted <= shift_right(unsigned(not crc), 4 * count);
    fcs_nibble  <= std_logic_vector(fcs_shifted(3 downto 0));

    o_ram_addr <= std_logic_vector(fetch_idx(buffer_addr_bits + 1 downto 2));

    crc_nibble <= cur_byte(3 downto 0) when phase = '0' else cur_byte(7 downto 4);
    crc_enable <= '1' when state = S_DATA else '0';
    crc_clear  <= '1' when state = S_IDLE or state = S_PREAMBLE else '0';

    u_crc : entity work.eth_crc32
        port map (
            i_clk        => i_clk,
            i_rst        => i_rst,
            i_clear      => crc_clear,
            i_enable     => crc_enable,
            i_nibble     => crc_nibble,
            o_crc        => crc,
            o_residue_ok => open
        );

    p_fsm : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            done_reg <= '0';
            if i_rst = '1' then
                state     <= S_IDLE;
                tx_en_reg <= '0';
                txd_reg   <= (others => '0');
                count     <= 0;
            else
                case state is
                    when S_IDLE =>
                        tx_en_reg <= '0';
                        count     <= 0;
                        fetch_idx <= (others => '0');
                        byte_idx  <= (others => '0');
                        phase     <= '0';
                        if i_start = '1' then
                            length <= unsigned(i_length);
                            if unsigned(i_length) < MIN_PAYLOAD_BYTES then
                                total <= to_unsigned(MIN_PAYLOAD_BYTES, total'length);
                            else
                                total <= unsigned(i_length);
                            end if;
                            state <= S_PREAMBLE;
                        end if;

                    when S_PREAMBLE =>
                        tx_en_reg <= '1';
                        if count < PREAMBLE_NIBBLES then
                            txd_reg <= NIBBLE_PREAMBLE;
                            count   <= count + 1;
                        else
                            -- Nibble alto do SFD, e o primeiro byte do quadro é carregado.
                            txd_reg   <= NIBBLE_SFD_HIGH;
                            cur_byte  <= fetch_byte;
                            fetch_idx <= fetch_idx + 1;
                            state     <= S_DATA;
                        end if;

                    when S_DATA =>
                        if phase = '0' then
                            txd_reg <= cur_byte(3 downto 0);
                            phase   <= '1';
                        else
                            txd_reg  <= cur_byte(7 downto 4);
                            phase    <= '0';
                            byte_idx <= byte_idx + 1;
                            if byte_idx + 1 = total then
                                count <= 0;
                                state <= S_FCS;
                            else
                                cur_byte  <= fetch_byte;
                                fetch_idx <= fetch_idx + 1;
                            end if;
                        end if;

                    when S_FCS =>
                        txd_reg <= fcs_nibble;
                        if count = FCS_NIBBLES - 1 then
                            count <= 0;
                            state <= S_GAP;
                        else
                            count <= count + 1;
                        end if;

                    when S_GAP =>
                        tx_en_reg <= '0';
                        txd_reg   <= (others => '0');
                        if count = GAP_NIBBLES - 1 then
                            done_reg <= '1';
                            state    <= S_IDLE;
                        else
                            count <= count + 1;
                        end if;
                end case;
            end if;
        end if;

    end process p_fsm;

    o_txd   <= txd_reg;
    o_tx_en <= tx_en_reg;
    o_busy  <= '0' when state = S_IDLE else '1';
    o_done  <= done_reg;

end architecture rtl;
