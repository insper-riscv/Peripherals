-- ==========================================================================
-- Camada física PS/2 do lado do hospedeiro, um canal
-- ==========================================================================
-- Fala com um dispositivo PS/2 (teclado ou mouse) por duas linhas open-drain.
-- Cada instância é independente: não há estado compartilhado, então dois
-- canais convivem lado a lado (teclado no canal 0 e mouse no canal 1, num
-- cabo Y).
--
-- Entrada: as linhas passam por um sincronizador de dois estágios e por um
-- filtro de glitch. O quadro do dispositivo tem 11 bits (início em '0', oito
-- de dados do menos para o mais significativo, paridade ímpar e parada em
-- '1'), amostrado a cada borda de descida do clock filtrado. Um quadro válido
-- produz um pulso de o_rx_valid com o byte em o_rx_data; um quadro com início,
-- paridade ou parada inválidos, ou interrompido além de timeout_cycles,
-- produz um pulso de o_rx_error.
--
-- Saída: o byte de i_tx_data aceito com i_tx_valid e o_tx_ready espera a
-- linha livre. O hospedeiro segura o clock em '0' por inhibit_cycles, baixa
-- os dados (bit de início), solta o clock e entrega os oito bits e a
-- paridade ímpar a cada borda de descida gerada pelo dispositivo; solta os
-- dados e confere o bit de reconhecimento. Falta de reconhecimento ou de
-- clock além de timeout_cycles produz um pulso de o_rx_error.
--
-- Os generics têm como padrão um clock de sistema de 50 MHz. O reset
-- do sistema deve durar pelo menos dois ciclos, para o sincronizador
-- carregar o nível das linhas.
-- ==========================================================================

library ieee;
use ieee.std_logic_1164.all;

entity ps2_host is
    generic (
        -- Ciclos de clock que um nível das linhas precisa durar para passar no filtro de glitch.
        filter_cycles  : positive := 8;
        -- Ciclos com o clock segurado em '0' antes de uma transmissão (mínimo de 100 us).
        inhibit_cycles : positive := 6000;
        -- Ciclos sem borda de clock que abortam um quadro em andamento (padrão de 20 ms a 50 MHz).
        timeout_cycles : positive := 1000000
    );
    port (
        -- Clock do sistema.
        i_clk      : in    std_logic;
        -- Reset, ativo em nível baixo.
        i_rst_n    : in    std_logic;
        -- Linha de clock do conector, open-drain.
        io_ps2_clk : inout std_logic;
        -- Linha de dados do conector, open-drain.
        io_ps2_dat : inout std_logic;
        -- Último byte recebido, válido a partir do pulso de o_rx_valid.
        o_rx_data  : out   std_logic_vector(7 downto 0);
        -- Pulso de um ciclo por byte recebido com paridade correta.
        o_rx_valid : out   std_logic;
        -- Pulso de um ciclo em erro de paridade, de quadro, de reconhecimento ou de tempo.
        o_rx_error : out   std_logic;
        -- Byte a enviar ao dispositivo.
        i_tx_data  : in    std_logic_vector(7 downto 0);
        -- Pedido de envio de i_tx_data, aceito no ciclo em que o_tx_ready vale '1'.
        i_tx_valid : in    std_logic;
        -- O transmissor aceita um novo byte.
        o_tx_ready : out   std_logic
    );
end entity ps2_host;

architecture rtl of ps2_host is

    -- Estados da máquina que dirige as duas linhas.
    type state_t is (S_IDLE, S_RX, S_INHIBIT, S_WAIT_START, S_TX, S_RELEASE, S_ACK);

    -- Estado atual.
    signal state : state_t;

    -- Linhas lidas dos pinos com 'H' tratado como '1'.
    signal pins_raw  : std_logic_vector(1 downto 0);
    -- Linhas sincronizadas ao clock do sistema.
    signal pins_sync : std_logic_vector(1 downto 0);
    -- Clock filtrado.
    signal clk_f     : std_logic;
    -- Dados filtrados.
    signal dat_f     : std_logic;
    -- Clock filtrado do ciclo anterior, para detectar a borda de descida.
    signal clk_prev  : std_logic;
    -- Borda de descida do clock filtrado neste ciclo.
    signal fall      : std_logic;

    -- Segura o clock em '0'.
    signal clk_low : std_logic;
    -- Segura os dados em '0'.
    signal dat_low : std_logic;

    -- Registrador de deslocamento do quadro recebido (oito bits de dados).
    signal rx_shift  : std_logic_vector(7 downto 0);
    -- Bit de paridade recebido.
    signal rx_parity : std_logic;
    -- Quantidade de bordas de descida já tratadas no quadro.
    signal bit_count : natural range 0 to 10;
    -- Byte de dados e paridade ímpar do quadro a enviar.
    signal tx_frame  : std_logic_vector(8 downto 0);
    -- Há um byte aceito esperando a linha livre ou em envio.
    signal tx_busy   : std_logic;
    -- Contador de ciclos da inibição do clock ou do tempo sem borda.
    signal timer     : natural range 0 to timeout_cycles;

    -- Paridade ímpar de um byte: o bit que torna ímpar o total de uns do quadro.
    function odd_parity (data : std_logic_vector(7 downto 0)) return std_logic is
        -- Redução por ou-exclusivo dos bits.
        variable acc : std_logic := '0';
    begin

        for i in data'range loop

            acc := acc xor data(i);

        end loop;

        return not acc;

    end function odd_parity;

begin

    pins_raw(0) <= to_x01(io_ps2_clk);
    pins_raw(1) <= to_x01(io_ps2_dat);

    u_sync : entity work.synchronizer
        generic map (
            stages     => 2,
            data_width => 2
        )
        port map (
            i_clk => i_clk,
            i_d   => pins_raw,
            o_d   => pins_sync
        );

    u_filter_clk : entity work.ps2_filter
        generic map (
            filter_cycles => filter_cycles
        )
        port map (
            i_clk   => i_clk,
            i_rst_n => i_rst_n,
            i_d     => pins_sync(0),
            o_d     => clk_f
        );

    u_filter_dat : entity work.ps2_filter
        generic map (
            filter_cycles => filter_cycles
        )
        port map (
            i_clk   => i_clk,
            i_rst_n => i_rst_n,
            i_d     => pins_sync(1),
            o_d     => dat_f
        );

    u_drive_clk : entity work.tristate_buffer_1bit
        port map (
            i_d      => '0',
            i_enable => clk_low,
            o_d      => io_ps2_clk
        );

    u_drive_dat : entity work.tristate_buffer_1bit
        port map (
            i_d      => '0',
            i_enable => dat_low,
            o_d      => io_ps2_dat
        );

    fall       <= clk_prev and not clk_f;
    o_tx_ready <= '1' when state = S_IDLE and tx_busy = '0' else '0';

    p_fsm : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            clk_prev   <= clk_f;
            o_rx_valid <= '0';
            o_rx_error <= '0';

            if i_rst_n = '0' then
                state     <= S_IDLE;
                clk_prev  <= '1';
                clk_low   <= '0';
                dat_low   <= '0';
                tx_busy   <= '0';
                bit_count <= 0;
                timer     <= 0;
                rx_shift  <= (others => '0');
                rx_parity <= '0';
                tx_frame  <= (others => '0');
                o_rx_data <= (others => '0');
            else
                -- Tempo sem borda: reinicia a cada borda de descida e conta nos quadros em andamento.
                if fall = '1' or state = S_IDLE then
                    timer <= 0;
                elsif timer < timeout_cycles then
                    timer <= timer + 1;
                end if;

                case state is

                    when S_IDLE =>

                        if i_tx_valid = '1' and tx_busy = '0' then
                            tx_frame <= odd_parity(i_tx_data) & i_tx_data;
                            tx_busy  <= '1';
                        elsif fall = '1' then
                            bit_count <= 1;
                            if dat_f = '0' then
                                state <= S_RX;
                            else
                                o_rx_error <= '1';
                            end if;
                        elsif tx_busy = '1' and clk_f = '1' then
                            state   <= S_INHIBIT;
                            clk_low <= '1';
                            timer   <= 0;
                        end if;

                    when S_RX =>

                        if fall = '1' then
                            if bit_count <= 8 then
                                rx_shift <= dat_f & rx_shift(7 downto 1);
                                bit_count <= bit_count + 1;
                            elsif bit_count = 9 then
                                rx_parity <= dat_f;
                                bit_count <= bit_count + 1;
                            else
                                state <= S_IDLE;
                                if dat_f = '1' and odd_parity(rx_shift) = rx_parity then
                                    o_rx_valid <= '1';
                                    o_rx_data  <= rx_shift;
                                else
                                    o_rx_error <= '1';
                                end if;
                            end if;
                        elsif timer = timeout_cycles then
                            state      <= S_IDLE;
                            o_rx_error <= '1';
                        end if;

                    when S_INHIBIT =>

                        -- O clock segurado em '0' mantém o filtro em '0'; o timer conta a inibição.
                        if timer = inhibit_cycles - 1 then
                            dat_low <= '1';
                            clk_low <= '0';
                            state   <= S_WAIT_START;
                            timer   <= 0;
                        else
                            timer <= timer + 1;
                        end if;

                    when S_WAIT_START =>

                        if fall = '1' then
                            dat_low   <= not tx_frame(0);
                            bit_count <= 1;
                            state     <= S_TX;
                        elsif timer = timeout_cycles then
                            dat_low    <= '0';
                            tx_busy    <= '0';
                            state      <= S_IDLE;
                            o_rx_error <= '1';
                        end if;

                    when S_TX =>

                        if fall = '1' then
                            dat_low   <= not tx_frame(bit_count);
                            bit_count <= bit_count + 1;
                            if bit_count = 8 then
                                state <= S_RELEASE;
                            end if;
                        elsif timer = timeout_cycles then
                            dat_low    <= '0';
                            tx_busy    <= '0';
                            state      <= S_IDLE;
                            o_rx_error <= '1';
                        end if;

                    when S_RELEASE =>

                        if fall = '1' then
                            dat_low <= '0';
                            state   <= S_ACK;
                        elsif timer = timeout_cycles then
                            dat_low    <= '0';
                            tx_busy    <= '0';
                            state      <= S_IDLE;
                            o_rx_error <= '1';
                        end if;

                    when S_ACK =>

                        if fall = '1' then
                            tx_busy <= '0';
                            state   <= S_IDLE;
                            if dat_f = '1' then
                                o_rx_error <= '1';
                            end if;
                        elsif timer = timeout_cycles then
                            tx_busy    <= '0';
                            state      <= S_IDLE;
                            o_rx_error <= '1';
                        end if;

                end case;
            end if;
        end if;

    end process p_fsm;

end architecture rtl;
