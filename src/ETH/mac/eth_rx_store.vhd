-- =============================================================================
-- Armazenamento dos quadros recebidos (domínio do sistema)
--
-- Consome sem parar as palavras da FIFO assíncrona do receptor, confere o
-- endereço de destino dos seis primeiros bytes contra o filtro (endereço
-- próprio, difusão, grupo ou promíscuo) e grava os bytes aceitos, quatro por
-- palavra com o primeiro byte nos bits 7 a 0, no buffer de recepção. O buffer
-- guarda um quadro por vez: enquanto o programa não libera o quadro pronto
-- (i_release), os seguintes são descartados e contados. Ao fim do quadro,
-- decide pelas flags da palavra final: quadro com erro, perdido na FIFO, maior
-- que o buffer ou recusado pelo filtro não vira quadro pronto.
--
-- Os eventos de contagem (o_ev_*) são pulsos de um ciclo.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.eth_consts.all;

entity eth_rx_store is
    generic (
        -- Largura do endereço de palavra do buffer de recepção.
        buffer_addr_bits : positive := 9
    );
    port (
        -- Clock do sistema.
        i_clk          : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst          : in    std_logic;
        -- A FIFO do receptor está vazia.
        i_empty        : in    std_logic;
        -- Palavra do topo da FIFO.
        i_word         : in    std_logic_vector(8 downto 0);
        -- Retira a palavra do topo da FIFO.
        o_rd_en        : out   std_logic;
        -- Endereço MAC próprio, o primeiro octeto nos bits 7 a 0.
        i_mac_addr     : in    std_logic_vector(47 downto 0);
        -- Recebe quadros.
        i_enable       : in    std_logic;
        -- Aceita qualquer destino.
        i_promiscuous  : in    std_logic;
        -- Aceita o destino de difusão.
        i_broadcast    : in    std_logic;
        -- Aceita destinos de grupo.
        i_multicast    : in    std_logic;
        -- Entrega também quadros com erro de CRC, de PHY, de alinhamento ou curtos.
        i_accept_errors : in   std_logic;
        -- Libera o quadro pronto, pulso de um ciclo.
        i_release      : in    std_logic;
        -- Escrita de uma palavra no buffer.
        o_ram_we       : out   std_logic;
        -- Endereço de palavra da escrita.
        o_ram_addr     : out   std_logic_vector(buffer_addr_bits - 1 downto 0);
        -- Palavra a escrever.
        o_ram_data     : out   std_logic_vector(31 downto 0);
        -- Há um quadro pronto no buffer.
        o_frame_ready  : out   std_logic;
        -- Comprimento do quadro pronto em bytes, sem FCS.
        o_frame_len    : out   std_logic_vector(buffer_addr_bits + 2 downto 0);
        -- Pulso: quadro entregue ao buffer.
        o_ev_frame     : out   std_logic;
        -- Pulso: quadro com erro de CRC.
        o_ev_crc       : out   std_logic;
        -- Pulso: quadro com erro de PHY, de alinhamento ou curto.
        o_ev_phy       : out   std_logic;
        -- Pulso: quadro descartado por falta de espaço.
        o_ev_dropped   : out   std_logic;
        -- Pulso: quadro recusado pelo filtro de endereço.
        o_ev_filtered  : out   std_logic
    );
end entity eth_rx_store;

architecture rtl of eth_rx_store is

    -- Bytes que o buffer comporta.
    constant CAPACITY : natural := 2 ** (buffer_addr_bits + 2);

    -- Palavra da FIFO é consumida neste ciclo.
    signal consume      : std_logic;
    -- A palavra consumida é a final do quadro.
    signal is_last      : std_logic;
    -- Um quadro está em andamento.
    signal in_frame     : std_logic := '0';
    -- O quadro em andamento é descartado porque não há buffer livre.
    signal drop_busy    : std_logic := '0';
    -- O quadro em andamento é descartado pelo filtro.
    signal drop_filter  : std_logic := '0';
    -- O quadro em andamento passou do tamanho do buffer.
    signal too_long     : std_logic := '0';
    -- Bytes recebidos do quadro.
    signal byte_count   : unsigned(buffer_addr_bits + 2 downto 0) := (others => '0');
    -- Palavra em montagem.
    signal accum        : std_logic_vector(31 downto 0) := (others => '0');
    -- Endereço da próxima palavra a gravar.
    signal word_addr    : unsigned(buffer_addr_bits - 1 downto 0) := (others => '0');
    -- Todos os octetos de destino vistos até agora são os do endereço próprio.
    signal match_own    : std_logic := '1';
    -- Todos os octetos de destino vistos até agora são 0xFF.
    signal match_bcast  : std_logic := '1';
    -- O primeiro octeto de destino indica endereço de grupo.
    signal is_group     : std_logic := '0';
    -- Há um quadro pronto.
    signal ready        : std_logic := '0';
    -- Comprimento do quadro pronto.
    signal frame_len    : unsigned(buffer_addr_bits + 2 downto 0) := (others => '0');
    -- O quadro terminou e espera a gravação da última palavra para ficar pronto.
    signal commit       : std_logic := '0';
    -- Comprimento a publicar no commit.
    signal commit_len   : unsigned(buffer_addr_bits + 2 downto 0) := (others => '0');

    -- Escrita registrada no buffer.
    signal ram_we       : std_logic := '0';
    -- Endereço registrado da escrita.
    signal ram_addr     : unsigned(buffer_addr_bits - 1 downto 0) := (others => '0');
    -- Palavra registrada da escrita.
    signal ram_data     : std_logic_vector(31 downto 0) := (others => '0');

    -- Pulsos de evento registrados.
    signal ev_frame, ev_crc, ev_phy, ev_dropped, ev_filtered : std_logic := '0';

begin

    consume <= not i_empty;
    is_last <= i_word(8);
    o_rd_en <= consume;

    p_store : process (i_clk) is
        -- Byte da palavra consumida.
        variable byte      : std_logic_vector(7 downto 0);
        -- Endereço próprio deslocado para o octeto de índice byte_count nos bits 7 a 0.
        variable own_shift : unsigned(47 downto 0);
        -- Quantidade de bytes já recebidos antes deste, zero no primeiro.
        variable count     : unsigned(buffer_addr_bits + 2 downto 0);
        -- Posição do byte na palavra.
        variable lane      : natural range 0 to 3;
        -- Palavra em montagem com o byte já inserido.
        variable word_next : std_logic_vector(31 downto 0);
        -- Os octetos de destino vistos até este byte são os do endereço próprio.
        variable own_ok    : std_logic;
        -- Os octetos de destino vistos até este byte são 0xFF.
        variable bcast_ok  : std_logic;
        -- O quadro é descartado por falta de buffer.
        variable busy      : std_logic;
        -- O quadro é descartado pelo filtro.
        variable refused   : std_logic;
        -- O quadro passou do tamanho do buffer.
        variable long      : std_logic;
        -- Flags da palavra final.
        variable f         : std_logic_vector(5 downto 0);
        -- O quadro tem erro de recepção.
        variable has_error : std_logic;
    begin

        if rising_edge(i_clk) then
            ram_we      <= '0';
            ev_frame    <= '0';
            ev_crc      <= '0';
            ev_phy      <= '0';
            ev_dropped  <= '0';
            ev_filtered <= '0';

            if i_rst = '1' then
                in_frame   <= '0';
                ready      <= '0';
                commit     <= '0';
                byte_count <= (others => '0');
                word_addr  <= (others => '0');
                accum      <= (others => '0');
            else
                if i_release = '1' then
                    ready <= '0';
                end if;

                if commit = '1' then
                    ready     <= '1';
                    frame_len <= commit_len;
                    commit    <= '0';
                    ev_frame  <= '1';
                end if;

                if consume = '1' and is_last = '0' then
                    byte := i_word(7 downto 0);
                    -- Estado do quadro: no primeiro byte parte dos valores iniciais.
                    if in_frame = '0' then
                        count     := (others => '0');
                        busy      := ready or not i_enable;
                        refused   := '0';
                        long      := '0';
                        own_ok    := '1';
                        bcast_ok  := '1';
                        is_group  <= byte(0);
                        word_next := (others => '0');
                        word_addr <= (others => '0');
                    else
                        count     := byte_count;
                        busy      := drop_busy;
                        refused   := drop_filter;
                        long      := too_long;
                        own_ok    := match_own;
                        bcast_ok  := match_bcast;
                        word_next := accum;
                    end if;
                    lane := to_integer(count(1 downto 0));

                    if count < MAC_BYTES then
                        own_shift := shift_right(unsigned(i_mac_addr), 8 * to_integer(count(2 downto 0)));
                        if byte /= std_logic_vector(own_shift(7 downto 0)) then
                            own_ok := '0';
                        end if;
                        if byte /= x"FF" then
                            bcast_ok := '0';
                        end if;
                    end if;
                    if count = MAC_BYTES - 1 then
                        if (i_promiscuous = '0') and (own_ok = '0')
                           and not (bcast_ok = '1' and i_broadcast = '1')
                           and not (is_group = '1' and i_multicast = '1') then
                            refused := '1';
                        end if;
                    end if;

                    if count = CAPACITY then
                        long := '1';
                    end if;

                    if busy = '0' and refused = '0' and long = '0' then
                        word_next(8 * lane + 7 downto 8 * lane) := byte;
                        accum <= word_next;
                        if lane = 3 then
                            ram_we    <= '1';
                            ram_addr  <= word_addr;
                            ram_data  <= word_next;
                            word_addr <= word_addr + 1;
                            accum     <= (others => '0');
                        end if;
                    end if;
                    if long = '0' then
                        byte_count <= count + 1;
                    else
                        byte_count <= count;
                    end if;

                    in_frame    <= '1';
                    drop_busy   <= busy;
                    drop_filter <= refused;
                    too_long    <= long;
                    match_own   <= own_ok;
                    match_bcast <= bcast_ok;

                elsif consume = '1' then
                    f := i_word(5 downto 0);
                    if in_frame = '1' then
                        count := byte_count;
                    else
                        count := (others => '0');
                    end if;
                    has_error := f(RXF_CRC) or f(RXF_PHY) or f(RXF_ALIGN) or f(RXF_RUNT);
                    ev_crc     <= f(RXF_CRC);
                    ev_phy     <= f(RXF_PHY) or f(RXF_ALIGN) or f(RXF_RUNT);
                    ev_dropped <= f(RXF_MISSED);

                    if in_frame = '1' and drop_busy = '1' then
                        ev_dropped <= '1';
                    elsif in_frame = '1' and drop_filter = '1' then
                        ev_filtered <= '1';
                    elsif in_frame = '1' and too_long = '1' then
                        ev_dropped <= '1';
                    elsif f(RXF_OVERFLOW) = '1' then
                        ev_dropped <= '1';
                    elsif has_error = '1' and i_accept_errors = '0' then
                        null;
                    elsif count < MAC_BYTES then
                        ev_filtered <= '1';
                    else
                        if count(1 downto 0) /= "00" then
                            ram_we   <= '1';
                            ram_addr <= word_addr;
                            ram_data <= accum;
                        end if;
                        commit     <= '1';
                        commit_len <= count;
                    end if;
                    in_frame   <= '0';
                    byte_count <= (others => '0');
                    accum      <= (others => '0');
                end if;
            end if;
        end if;

    end process p_store;

    o_ram_we      <= ram_we;
    o_ram_addr    <= std_logic_vector(ram_addr);
    o_ram_data    <= ram_data;
    o_frame_ready <= ready;
    o_frame_len   <= std_logic_vector(frame_len) when ready = '1' else (others => '0');
    o_ev_frame    <= ev_frame;
    o_ev_crc      <= ev_crc;
    o_ev_phy      <= ev_phy;
    o_ev_dropped  <= ev_dropped;
    o_ev_filtered <= ev_filtered;

end architecture rtl;
