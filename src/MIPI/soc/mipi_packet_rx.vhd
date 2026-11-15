-- =============================================================================
-- Camada de pacotes do CSI-2
--
-- Junta os bytes das lanes em grupos (o byte n do pacote vem da lane n mod
-- lanes), confere o ECC do cabeçalho de quatro bytes, separa a carga útil dos
-- dois bytes de CRC-16 que fecham um pacote longo e confere o CRC. Dá às lanes
-- o sinal de busca e destrava todas no fim de cada pacote, de modo que o
-- próximo pacote começa por um novo byte de sincronismo.
--
-- O tamanho do pacote vem do cabeçalho (contagem de palavras da carga útil),
-- então o último grupo de um pacote pode ter menos bytes que lanes, e nesse
-- caso só as primeiras lanes entregam byte. Um pacote curto (tipo de dado de 0
-- a 15) não tem carga útil nem CRC. Um cabeçalho com ECC errado derruba o
-- pacote sem correção do bit, porque o tamanho dele é desconhecido.
--
-- A defasagem entre as lanes aceita é de até três ciclos de i_clk. Se só
-- parte das lanes se alinha e as demais não se alinham em oito ciclos, a
-- busca recomeça.
--
-- Saídas de evento, todas de um ciclo, exceto o tipo, a contagem e o formato
-- do cabeçalho, que valem até o cabeçalho seguinte:
--   - o_hdr_valid e o_hdr_bad, cabeçalho com ECC correto e com ECC errado;
--   - o_pix_valid, grupo de bytes de carga útil, com o_pix_mask dizendo quais
--     bytes do grupo existem (o último grupo pode ser parcial);
--   - o_pkt_end, pacote completo, com o_crc_ok válido junto dele.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.mipi_consts.all;
use work.utils_pkg.all;

entity mipi_packet_rx is
    generic (
        -- Quantidade de lanes de dados, 1, 2 ou 4.
        lanes : positive range 1 to 4 := 2
    );
    port (
        -- Clock do receptor.
        i_clk         : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst         : in    std_logic;
        -- Lanes alinhadas ao byte de sincronismo, uma por lane.
        i_lane_locked : in    std_logic_vector(lanes - 1 downto 0);
        -- Byte válido de cada lane, um pulso por byte.
        i_lane_valid  : in    std_logic_vector(lanes - 1 downto 0);
        -- Byte de cada lane, a lane 0 nos bits menos significativos.
        i_lane_data   : in    std_logic_vector(lanes * 8 - 1 downto 0);
        -- Permite a busca de sincronismo; um ciclo em '0' destrava todas as lanes.
        o_arm         : out   std_logic;
        -- Cabeçalho com ECC correto.
        o_hdr_valid   : out   std_logic;
        -- Cabeçalho com ECC errado.
        o_hdr_bad     : out   std_logic;
        -- O pacote do cabeçalho é longo ('1') ou curto ('0').
        o_hdr_long    : out   std_logic;
        -- Tipo de dado do cabeçalho.
        o_hdr_dt      : out   std_logic_vector(5 downto 0);
        -- Contagem de palavras do cabeçalho (bytes da carga útil, ou o dado de um pacote curto).
        o_hdr_wc      : out   std_logic_vector(15 downto 0);
        -- Grupo de bytes de carga útil.
        o_pix_valid   : out   std_logic;
        -- Bytes do grupo, a lane 0 nos bits menos significativos.
        o_pix_data    : out   std_logic_vector(lanes * 8 - 1 downto 0);
        -- Bytes do grupo que fazem parte da carga útil.
        o_pix_mask    : out   std_logic_vector(lanes - 1 downto 0);
        -- Fim de um pacote.
        o_pkt_end     : out   std_logic;
        -- CRC do pacote conferido, '1' quando correto (sempre '1' num pacote curto).
        o_crc_ok      : out   std_logic
    );
end entity mipi_packet_rx;

architecture rtl of mipi_packet_rx is

    -- Fases do receptor de pacotes.
    type state_t is (st_hunt, st_receive, st_unlock);

    -- Maior posição de byte de um pacote, cabeçalho, 65535 bytes de carga útil e CRC.
    constant MAX_POS : natural := HEADER_BYTES + 65535 + CRC_BYTES;
    -- Ciclos de espera pelas outras lanes depois que a primeira se alinha.
    constant SYNC_WINDOW : natural := 8;

    -- Fase atual.
    signal state     : state_t                                  := st_hunt;
    -- Posição, no pacote, do primeiro byte do próximo grupo.
    signal pos       : natural range 0 to MAX_POS               := 0;
    -- Total de bytes do pacote, o cabeçalho enquanto o tamanho não se sabe.
    signal total     : natural range 0 to MAX_POS               := HEADER_BYTES;
    -- Bytes do cabeçalho montado.
    signal header    : std_logic_vector(31 downto 0)            := (others => '0');
    -- CRC-16 corrente da carga útil.
    signal crc       : std_logic_vector(15 downto 0)            := CRC_INIT;
    -- CRC recebido do transmissor.
    signal crc_rx    : std_logic_vector(15 downto 0)            := (others => '0');
    -- Contagem de palavras do pacote em curso.
    signal wc        : natural range 0 to 65535                 := 0;
    -- Bytes recebidos de cada lane, esperando o grupo completar.
    signal held_data : std_logic_vector(lanes * 8 - 1 downto 0) := (others => '0');
    -- Lanes com byte guardado.
    signal held_flag : std_logic_vector(lanes - 1 downto 0)     := (others => '0');
    -- Ciclos desde o alinhamento da primeira lane.
    signal wait_cnt  : natural range 0 to SYNC_WINDOW           := 0;

begin

    o_arm <= '0' when state = st_unlock else '1';

    p_packet : process (i_clk) is

        -- Quantidade de bytes esperados no próximo grupo.
        variable need     : natural range 0 to lanes;
        -- Posição do byte tratado dentro do pacote.
        variable index    : natural range 0 to MAX_POS + lanes;
        -- Byte da lane tratada.
        variable value    : std_logic_vector(7 downto 0);
        -- Grupo pronto para ser consumido.
        variable ready    : boolean;
        -- Cabeçalho depois de incluir os bytes deste grupo.
        variable hdr_v    : std_logic_vector(31 downto 0);
        -- CRC depois de incluir os bytes deste grupo.
        variable crc_v    : std_logic_vector(15 downto 0);
        -- CRC recebido depois de incluir os bytes deste grupo.
        variable crc_rx_v : std_logic_vector(15 downto 0);
        -- Máscara de carga útil deste grupo.
        variable mask_v   : std_logic_vector(lanes - 1 downto 0);
        -- Marcas de byte guardado depois de consumir ou receber.
        variable flag_v   : std_logic_vector(lanes - 1 downto 0);

    begin

        if rising_edge(i_clk) then
            o_hdr_valid <= '0';
            o_hdr_bad   <= '0';
            o_pix_valid <= '0';
            o_pkt_end   <= '0';

            flag_v := held_flag;

            for lane in 0 to lanes - 1 loop

                if i_lane_valid(lane) = '1' then
                    held_data(lane * 8 + 7 downto lane * 8) <= i_lane_data(lane * 8 + 7 downto lane * 8);
                end if;

            end loop;

            case state is
                when st_hunt =>
                    if i_lane_locked = (lanes - 1 downto 0 => '1') then
                        state     <= st_receive;
                        pos       <= 0;
                        total     <= HEADER_BYTES;
                        flag_v    := (others => '0');
                        wait_cnt  <= 0;
                    elsif i_lane_locked /= (lanes - 1 downto 0 => '0') then
                        wait_cnt <= wait_cnt + 1;

                        if wait_cnt = SYNC_WINDOW - 1 then
                            state    <= st_unlock;
                            wait_cnt <= 0;
                        end if;
                    else
                        wait_cnt <= 0;
                    end if;
                when st_unlock =>
                    state  <= st_hunt;
                    flag_v := (others => '0');
                when st_receive =>
                    if total - pos < lanes then
                        need := total - pos;
                    else
                        need := lanes;
                    end if;

                    ready := true;

                    for lane in 0 to lanes - 1 loop

                        if lane < need and held_flag(lane) = '0' then
                            ready := false;
                        end if;

                    end loop;

                    if ready then
                        hdr_v    := header;
                        crc_v    := crc;
                        crc_rx_v := crc_rx;
                        mask_v   := (others => '0');
                        flag_v   := (others => '0');

                        for lane in 0 to lanes - 1 loop

                            index := pos + lane;
                            value := held_data(lane * 8 + 7 downto lane * 8);

                            if lane < need then
                                if index < HEADER_BYTES then
                                    hdr_v(index * 8 + 7 downto index * 8) := value;
                                elsif index < HEADER_BYTES + wc then
                                    crc_v          := csi2_crc_next(crc_v, value);
                                    mask_v(lane)   := '1';
                                elsif index = HEADER_BYTES + wc then
                                    crc_rx_v(7 downto 0) := value;
                                else
                                    crc_rx_v(15 downto 8) := value;
                                end if;
                            end if;

                        end loop;

                        header <= hdr_v;
                        crc    <= crc_v;
                        crc_rx <= crc_rx_v;
                        pos    <= pos + need;

                        if pos + need = HEADER_BYTES then
                            -- Último grupo do cabeçalho: confere o ECC e decide o tamanho do pacote.
                            if csi2_ecc(hdr_v(23 downto 0)) /= hdr_v(29 downto 24) then
                                o_hdr_bad <= '1';
                                state     <= st_unlock;
                            else
                                o_hdr_valid <= '1';
                                o_hdr_dt    <= hdr_v(5 downto 0);
                                o_hdr_wc    <= hdr_v(23 downto 8);
                                wc          <= to_integer(unsigned(hdr_v(23 downto 8)));
                                crc         <= CRC_INIT;

                                if unsigned(hdr_v(5 downto 0)) > SHORT_MAX then
                                    o_hdr_long <= '1';
                                    total      <= HEADER_BYTES + to_integer(unsigned(hdr_v(23 downto 8))) + CRC_BYTES;
                                else
                                    o_hdr_long <= '0';
                                    o_pkt_end  <= '1';
                                    o_crc_ok   <= '1';
                                    state      <= st_unlock;
                                end if;
                            end if;
                        elsif pos >= HEADER_BYTES then
                            o_pix_data  <= held_data;
                            o_pix_mask  <= mask_v;
                            o_pix_valid <= to_sl(mask_v /= (lanes - 1 downto 0 => '0'));

                            if pos + need = total then
                                o_pkt_end <= '1';
                                o_crc_ok  <= to_sl(crc_rx_v = crc_v);
                                state     <= st_unlock;
                            end if;
                        end if;
                    end if;
                when others =>
                    state <= st_hunt;
            end case;

            for lane in 0 to lanes - 1 loop

                if i_lane_valid(lane) = '1' then
                    flag_v(lane) := '1';
                end if;

            end loop;

            held_flag <= flag_v;

            if i_rst = '1' then
                state     <= st_hunt;
                o_hdr_long <= '0';
                o_hdr_dt  <= (others => '0');
                o_hdr_wc  <= (others => '0');
                o_pix_data <= (others => '0');
                o_pix_mask <= (others => '0');
                o_crc_ok  <= '0';
                held_flag <= (others => '0');
                wait_cnt  <= 0;
            end if;
        end if;

    end process p_packet;

end architecture rtl;
