-- =============================================================================
-- Decodificador de protocolo do mouse PS/2
--
-- Consome a interface de bytes do ps2_host (um canal PS/2) e conduz o mouse:
--   1. Inicialização: envia 0xFF (reset), espera 0xFA, 0xAA e 0x00, envia 0xF4
--      (habilita streaming) e espera 0xFA. Qualquer resposta diferente da
--      esperada, erro de quadro ou silêncio por init_timeout_cycles reinicia a
--      sequência pelo reset e gera um pulso em o_error.
--   2. Streaming: monta pacotes de 3 bytes (botões e sinais, X, Y). Um primeiro
--      byte com o bit 3 em zero é descartado (ressincronização, pulso em
--      o_error). Um pacote parado entre bytes por packet_timeout_cycles ou com
--      erro de quadro é descartado do mesmo modo.
-- O deslocamento de 9 bits é {sinal, byte}; com o bit de estouro do eixo o
-- deslocamento é cortado no limite do sinal (255 ou -256) e o_overflow vale '1'.
-- Um pulso de o_packet_valid indica pacote completo e os demais campos de
-- saída permanecem estáveis até o pacote seguinte. i_restart reinicia a
-- sequência de inicialização a qualquer momento.
-- Envio: o_tx_valid vale '1' por um único ciclo, e só no ciclo em que
-- i_tx_ready vale '1'.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.ps2_mouse_consts.all;

entity ps2_mouse_decoder is
    generic (
        -- Ciclos de clock sem resposta aceitos durante a inicialização (o autoteste do mouse leva centenas de ms).
        init_timeout_cycles   : positive := 100_000_000;
        -- Ciclos de clock sem byte aceitos no meio de um pacote.
        packet_timeout_cycles : positive := 5_000_000
    );
    port (
        -- Clock do módulo.
        i_clk        : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst        : in    std_logic;
        -- Pulso que reinicia a inicialização do mouse ('1' = reinicia).
        i_restart    : in    std_logic;
        -- Byte recebido do ps2_host.
        i_rx_data    : in    std_logic_vector(7 downto 0);
        -- Pulso de byte recebido válido ('1' = i_rx_data é um byte novo).
        i_rx_valid   : in    std_logic;
        -- Pulso de erro de paridade ou de quadro do ps2_host.
        i_rx_error   : in    std_logic;
        -- Byte a enviar ao mouse.
        o_tx_data    : out   std_logic_vector(7 downto 0);
        -- Pulso de envio ('1' = o_tx_data é aceito pelo ps2_host neste ciclo).
        o_tx_valid   : out   std_logic;
        -- O ps2_host aceita um byte novo ('1' = pronto).
        i_tx_ready   : in    std_logic;
        -- O mouse está em streaming ('1' = inicialização concluída).
        o_streaming  : out   std_logic;
        -- Pulso de pacote completo ('1' = campos de saída atualizados).
        o_packet_valid : out   std_logic;
        -- Botões do último pacote: bit 0 esquerdo, bit 1 direito, bit 2 meio.
        o_buttons    : out   std_logic_vector(2 downto 0);
        -- Deslocamento em X do último pacote (complemento de dois).
        o_dx         : out   std_logic_vector(DELTA_WIDTH - 1 downto 0);
        -- Deslocamento em Y do último pacote (complemento de dois, positivo para cima).
        o_dy         : out   std_logic_vector(DELTA_WIDTH - 1 downto 0);
        -- O último pacote trouxe estouro em X ou em Y ('1' = estouro).
        o_overflow   : out   std_logic;
        -- Pulso de erro de protocolo (resposta inesperada, quadro ruim, ressincronização ou silêncio).
        o_error      : out   std_logic
    );
end entity ps2_mouse_decoder;

architecture rtl of ps2_mouse_decoder is

    -- Estados da sequência de inicialização e do recebimento de pacotes.
    type state_t is (
        S_SEND_RESET, S_WAIT_RESET_ACK, S_WAIT_SELF_TEST, S_WAIT_DEVICE_ID,
        S_SEND_ENABLE, S_WAIT_ENABLE_ACK, S_BYTE0, S_BYTE1, S_BYTE2
    );

    -- Estado atual da máquina.
    signal state      : state_t := S_SEND_RESET;
    -- Contagem de ciclos de silêncio no estado atual.
    signal idle_count : natural range 0 to 2 ** 30 := 0;
    -- Primeiro byte do pacote em montagem (botões, sinais e estouros).
    signal byte0      : std_logic_vector(7 downto 0) := (others => '0');
    -- Segundo byte do pacote em montagem (deslocamento X de 8 bits).
    signal byte1      : std_logic_vector(7 downto 0) := (others => '0');
    -- Estado está esperando resposta do mouse na inicialização.
    signal in_init_wait : std_logic;
    -- Estado está no meio de um pacote (esperando o segundo ou o terceiro byte).
    signal in_packet    : std_logic;
    -- Envio aceito neste ciclo: pedido de envio sem reset, reinício ou erro que o cancelem.
    signal tx_fire      : std_logic;
    -- O tempo limite do estado atual esgotou.
    signal timed_out    : std_logic;
    -- Deslocamento X do pacote que acabou de completar, já cortado se houve estouro.
    signal next_dx      : std_logic_vector(DELTA_WIDTH - 1 downto 0);
    -- Deslocamento Y do pacote que acabou de completar, já cortado se houve estouro.
    signal next_dy      : std_logic_vector(DELTA_WIDTH - 1 downto 0);

    -- Maior deslocamento de 9 bits.
    constant DELTA_MAX : std_logic_vector(DELTA_WIDTH - 1 downto 0) := (DELTA_WIDTH - 1 => '0', others => '1');
    -- Menor deslocamento de 9 bits.
    constant DELTA_MIN : std_logic_vector(DELTA_WIDTH - 1 downto 0) := (DELTA_WIDTH - 1 => '1', others => '0');

    -- Monta o deslocamento de 9 bits de um eixo: {sinal, byte}, ou o limite do sinal quando há estouro.
    function axis_delta (
        sign_bit : std_logic;
        overflow : std_logic;
        value    : std_logic_vector(7 downto 0)
    ) return std_logic_vector is
    begin
        if overflow = '0' then
            return sign_bit & value;
        elsif sign_bit = '0' then
            return DELTA_MAX;
        else
            return DELTA_MIN;
        end if;
    end function axis_delta;

begin

    in_init_wait <= '1' when state = S_WAIT_RESET_ACK or state = S_WAIT_SELF_TEST or
                             state = S_WAIT_DEVICE_ID or state = S_WAIT_ENABLE_ACK else '0';
    in_packet    <= '1' when state = S_BYTE1 or state = S_BYTE2 else '0';

    timed_out <= '1' when (in_init_wait = '1' and idle_count >= init_timeout_cycles) or
                          (in_packet = '1' and idle_count >= packet_timeout_cycles) else '0';

    o_tx_data   <= CMD_RESET when state = S_SEND_RESET else CMD_ENABLE_STREAMING;
    tx_fire     <= i_tx_ready and not i_rst and not i_restart and not i_rx_error when
                   state = S_SEND_RESET or state = S_SEND_ENABLE else '0';
    o_tx_valid  <= tx_fire;
    o_streaming <= '1' when state = S_BYTE0 or state = S_BYTE1 or state = S_BYTE2 else '0';

    -- Deslocamento do pacote que completa agora: {sinal, byte} ou o limite no estouro.
    next_dx <= axis_delta(byte0(PKT_X_SIGN_BIT), byte0(PKT_X_OVERFLOW_BIT), byte1);
    next_dy <= axis_delta(byte0(PKT_Y_SIGN_BIT), byte0(PKT_Y_OVERFLOW_BIT), i_rx_data);

    -- Máquina de estados, com prioridade para reset, reinício, erro e tempo limite.
    p_fsm : process (i_clk) is
    begin
        if rising_edge(i_clk) then
            o_packet_valid <= '0';
            o_error        <= '0';
            if idle_count < 2 ** 30 then
                idle_count <= idle_count + 1;
            end if;

            if i_rst = '1' then
                state          <= S_SEND_RESET;
                idle_count     <= 0;
                byte0          <= (others => '0');
                byte1          <= (others => '0');
                o_buttons      <= (others => '0');
                o_dx           <= (others => '0');
                o_dy           <= (others => '0');
                o_overflow     <= '0';
            elsif i_restart = '1' then
                state      <= S_SEND_RESET;
                idle_count <= 0;
            elsif i_rx_error = '1' or timed_out = '1' then
                o_error    <= '1';
                idle_count <= 0;
                if in_packet = '1' or state = S_BYTE0 then
                    state <= S_BYTE0;
                else
                    state <= S_SEND_RESET;
                end if;
            elsif state = S_SEND_RESET then
                if tx_fire = '1' then
                    state      <= S_WAIT_RESET_ACK;
                    idle_count <= 0;
                end if;
            elsif state = S_SEND_ENABLE then
                if tx_fire = '1' then
                    state      <= S_WAIT_ENABLE_ACK;
                    idle_count <= 0;
                end if;
            elsif i_rx_valid = '1' then
                idle_count <= 0;
                case state is
                    when S_WAIT_RESET_ACK =>
                        if i_rx_data = RSP_ACK then
                            state <= S_WAIT_SELF_TEST;
                        else
                            o_error <= '1';
                            state   <= S_SEND_RESET;
                        end if;
                    when S_WAIT_SELF_TEST =>
                        if i_rx_data = RSP_SELF_TEST_OK then
                            state <= S_WAIT_DEVICE_ID;
                        else
                            o_error <= '1';
                            state   <= S_SEND_RESET;
                        end if;
                    when S_WAIT_DEVICE_ID =>
                        if i_rx_data = RSP_DEVICE_ID then
                            state <= S_SEND_ENABLE;
                        else
                            o_error <= '1';
                            state   <= S_SEND_RESET;
                        end if;
                    when S_WAIT_ENABLE_ACK =>
                        if i_rx_data = RSP_ACK then
                            state <= S_BYTE0;
                        else
                            o_error <= '1';
                            state   <= S_SEND_RESET;
                        end if;
                    when S_BYTE0 =>
                        if i_rx_data(SYNC_BIT) = '1' then
                            byte0 <= i_rx_data;
                            state <= S_BYTE1;
                        else
                            o_error <= '1';
                        end if;
                    when S_BYTE1 =>
                        byte1 <= i_rx_data;
                        state <= S_BYTE2;
                    when S_BYTE2 =>
                        o_buttons      <= byte0(PKT_MIDDLE_BIT) & byte0(PKT_RIGHT_BIT) & byte0(PKT_LEFT_BIT);
                        o_dx           <= next_dx;
                        o_dy           <= next_dy;
                        o_overflow     <= byte0(PKT_X_OVERFLOW_BIT) or byte0(PKT_Y_OVERFLOW_BIT);
                        o_packet_valid <= '1';
                        state          <= S_BYTE0;
                    when others =>
                        null;
                end case;
            end if;
        end if;
    end process p_fsm;

end architecture rtl;
