-- =============================================================================
-- Transmissor MAC em MII e GMII (domínio do clock de envio)
--
-- A cada pulso de i_start envia um quadro lido do buffer de envio: preâmbulo de
-- sete bytes 0x55, SFD 0xD5, os i_length bytes do buffer, zeros até 60 bytes
-- quando o quadro é mais curto, o FCS (CRC-32 do destino até o preenchimento,
-- complementado, byte menos significativo primeiro) e o intervalo de 96 bits
-- entre quadros. As saídas são registradas.
--
-- Com i_wide em '0' envia um nibble por habilitação, o baixo primeiro, nos
-- quatro bits baixos de o_txd, como o MII de 10 e 100 Mbit/s exige. Com i_wide
-- em '1' envia um byte por habilitação em o_txd inteiro, como o GMII de
-- 1000 Mbit/s. i_ce habilita o avanço do sequenciador: fica em '1' no MII (onde
-- o clock já tem a taxa do nibble) e a 1000 Mbit/s, e pulsa uma vez a cada
-- tempo de nibble quando o clock é o de 125 MHz e a taxa é 100 ou 10 Mbit/s.
-- i_wide só muda com o transmissor parado.
--
-- O buffer é lido com latência de um ciclo. No modo de nibble o endereço de
-- o_ram_addr é o da palavra do próximo byte, parado por dois tempos de nibble
-- antes de i_ram_data ser usado. No modo de byte o endereço é o da palavra do
-- byte seguinte ao de fetch_idx, para que a palavra já esteja lida quando o
-- byte for usado. i_length deve valer de 1 ao tamanho do buffer em bytes e
-- ficar estável durante o envio. i_start é memorizado até a habilitação
-- seguinte do estado parado. o_done dá um pulso quando o intervalo termina e o
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
        -- Clock do domínio (TX_CLK do PHY no MII, clock de 125 MHz no GMII).
        i_clk      : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst      : in    std_logic;
        -- Habilitação de avanço do sequenciador.
        i_ce       : in    std_logic := '1';
        -- '1' envia um byte por habilitação, '0' envia um nibble.
        i_wide     : in    std_logic := '0';
        -- Inicia um quadro, pulso de um ciclo.
        i_start    : in    std_logic;
        -- Comprimento do quadro em bytes, sem FCS e sem preenchimento.
        i_length   : in    std_logic_vector(buffer_addr_bits + 2 downto 0);
        -- Endereço de palavra lido no buffer.
        o_ram_addr : out   std_logic_vector(buffer_addr_bits - 1 downto 0);
        -- Palavra lida, um ciclo depois do endereço.
        i_ram_data : in    std_logic_vector(31 downto 0);
        -- Dados para o PHY: o byte do GMII ou o nibble do MII nos quatro bits baixos.
        o_txd      : out   std_logic_vector(7 downto 0);
        -- Habilitação de transmissão.
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
    -- Contador de unidades (nibbles ou bytes) do estado atual.
    signal count      : natural range 0 to 31 := 0;
    -- Índice do byte em envio.
    signal byte_idx   : unsigned(buffer_addr_bits + 2 downto 0) := (others => '0');
    -- Índice do byte lido da memória, sempre um à frente de byte_idx.
    signal fetch_idx  : unsigned(buffer_addr_bits + 2 downto 0) := (others => '0');
    -- Índice cuja palavra o buffer recebe como endereço.
    signal ram_idx    : unsigned(buffer_addr_bits + 2 downto 0) := (others => '0');
    -- Total de bytes antes do FCS, com o preenchimento.
    signal total      : unsigned(buffer_addr_bits + 2 downto 0) := (others => '0');
    -- Comprimento do quadro guardado no início do envio.
    signal length     : unsigned(buffer_addr_bits + 2 downto 0) := (others => '0');
    -- Byte em envio.
    signal cur_byte   : std_logic_vector(7 downto 0) := (others => '0');
    -- Fase do byte no modo de nibble, '0' envia o nibble baixo e '1' o alto.
    signal phase      : std_logic := '0';
    -- Nibble que o CRC absorve neste ciclo, ou a metade baixa do byte.
    signal crc_nibble : std_logic_vector(3 downto 0);
    -- O CRC absorve o byte inteiro neste ciclo.
    signal crc_wide   : std_logic;
    -- O CRC absorve o dado deste ciclo.
    signal crc_enable : std_logic;
    -- O CRC volta ao valor inicial.
    signal crc_clear  : std_logic;
    -- Estado do CRC.
    signal crc        : std_logic_vector(31 downto 0);
    -- Byte da memória indicado por fetch_idx, ou zero no preenchimento.
    signal fetch_byte : std_logic_vector(7 downto 0);
    -- Palavra de fetch_idx dividida em quatro bytes.
    signal lane       : std_logic_vector(7 downto 0);
    -- Último valor de count do preâmbulo, antes do SFD.
    signal preamble_last : natural range 0 to 31;
    -- Último valor de count do FCS.
    signal fcs_last   : natural range 0 to 31;
    -- Último valor de count do intervalo entre quadros.
    signal gap_last   : natural range 0 to 31;

    -- Complemento do CRC deslocado para deixar a unidade de count nos bits baixos.
    signal fcs_shifted : unsigned(31 downto 0);
    -- Unidade do FCS indicada por count: o byte de 8 bits, ou o nibble nos quatro bits baixos.
    signal fcs_lane    : std_logic_vector(7 downto 0);

    -- Saída registrada.
    signal txd_reg    : std_logic_vector(7 downto 0) := (others => '0');
    -- Habilitação registrada.
    signal tx_en_reg  : std_logic := '0';
    -- Pulso de fim registrado.
    signal done_reg   : std_logic := '0';
    -- Pedido de início memorizado até a habilitação.
    signal start_pending : std_logic := '0';

begin

    -- A palavra lida contém o byte que fetch_idx indica pelos dois bits baixos.
    with fetch_idx(1 downto 0) select lane <=
        i_ram_data(7 downto 0)   when "00",
        i_ram_data(15 downto 8)  when "01",
        i_ram_data(23 downto 16) when "10",
        i_ram_data(31 downto 24) when others;

    -- Depois do fim do quadro do software, o byte é zero (preenchimento).
    fetch_byte <= lane when fetch_idx < length else (others => '0');

    preamble_last <= PREAMBLE_BYTES when i_wide = '1' else PREAMBLE_NIBBLES;
    fcs_last      <= FCS_BYTES - 1 when i_wide = '1' else FCS_NIBBLES - 1;
    gap_last      <= GAP_BYTES - 1 when i_wide = '1' else GAP_NIBBLES - 1;

    fcs_shifted <= shift_right(unsigned(not crc), 8 * count) when i_wide = '1' else
                   shift_right(unsigned(not crc), 4 * count);
    fcs_lane    <= std_logic_vector(fcs_shifted(7 downto 0)) when i_wide = '1' else
                   "0000" & std_logic_vector(fcs_shifted(3 downto 0));

    -- No modo de byte a palavra seguinte é pedida um byte antes.
    ram_idx    <= fetch_idx + 1 when i_wide = '1' else fetch_idx;
    o_ram_addr <= std_logic_vector(ram_idx(buffer_addr_bits + 1 downto 2));

    crc_nibble <= cur_byte(3 downto 0) when phase = '0' or i_wide = '1' else cur_byte(7 downto 4);
    crc_wide   <= i_wide;
    crc_enable <= '1' when state = S_DATA and i_ce = '1' else '0';
    crc_clear  <= '1' when state = S_IDLE or state = S_PREAMBLE else '0';

    u_crc : entity work.eth_crc32
        port map (
            i_clk       => i_clk,
            i_rst       => i_rst,
            i_clear     => crc_clear,
            i_enable    => crc_enable,
            i_nibble    => crc_nibble,
            i_wide      => crc_wide,
            i_nibble_hi => cur_byte(7 downto 4),
            o_crc       => crc,
            o_residue_ok => open
        );

    p_fsm : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            done_reg <= '0';
            if i_start = '1' then
                start_pending <= '1';
            end if;
            if i_rst = '1' then
                state         <= S_IDLE;
                tx_en_reg     <= '0';
                txd_reg       <= (others => '0');
                count         <= 0;
                start_pending <= '0';
            elsif i_ce = '1' then
                case state is
                    when S_IDLE =>
                        tx_en_reg <= '0';
                        count     <= 0;
                        fetch_idx <= (others => '0');
                        byte_idx  <= (others => '0');
                        phase     <= '0';
                        if i_start = '1' or start_pending = '1' then
                            start_pending <= '0';
                            length        <= unsigned(i_length);
                            if unsigned(i_length) < MIN_PAYLOAD_BYTES then
                                total <= to_unsigned(MIN_PAYLOAD_BYTES, total'length);
                            else
                                total <= unsigned(i_length);
                            end if;
                            state <= S_PREAMBLE;
                        end if;

                    when S_PREAMBLE =>
                        tx_en_reg <= '1';
                        if count < preamble_last then
                            if i_wide = '1' then
                                txd_reg <= BYTE_PREAMBLE;
                            else
                                txd_reg <= "0000" & NIBBLE_PREAMBLE;
                            end if;
                            count <= count + 1;
                        else
                            -- Último elemento do SFD (nibble alto ou byte inteiro), e o primeiro byte do quadro é carregado.
                            if i_wide = '1' then
                                txd_reg <= BYTE_SFD;
                            else
                                txd_reg <= "0000" & NIBBLE_SFD_HIGH;
                            end if;
                            cur_byte  <= fetch_byte;
                            fetch_idx <= fetch_idx + 1;
                            state     <= S_DATA;
                        end if;

                    when S_DATA =>
                        if phase = '0' and i_wide = '0' then
                            txd_reg <= "0000" & cur_byte(3 downto 0);
                            phase   <= '1';
                        else
                            if i_wide = '1' then
                                txd_reg <= cur_byte;
                            else
                                txd_reg <= "0000" & cur_byte(7 downto 4);
                            end if;
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
                        txd_reg <= fcs_lane;
                        if count = fcs_last then
                            count <= 0;
                            state <= S_GAP;
                        else
                            count <= count + 1;
                        end if;

                    when S_GAP =>
                        tx_en_reg <= '0';
                        txd_reg   <= (others => '0');
                        if count = gap_last then
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
