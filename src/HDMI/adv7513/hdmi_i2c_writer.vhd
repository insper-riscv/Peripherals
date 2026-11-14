-- =============================================================================
-- Escritor I2C de registrador (somente escrita, mestre único)
--
-- Domínio do clock do sistema. Cada pedido (pulso em i_start) gera uma
-- transação completa de escrita de um registrador de um escravo de 7 bits:
-- condição de partida, endereço do escravo com o bit de escrita, endereço do
-- registrador, valor e condição de parada, com um bit de confirmação (ACK)
-- depois de cada byte. O bit de cada confirmação é amostrado no meio do pulso
-- de SCL; se algum deles vale '1' (o escravo não confirmou), o_nack sobe junto
-- com o pulso de o_done, e a transação segue até o fim mesmo assim.
--
-- Temporização: cada bit dura quatro quartos de período de SCL, e um quarto
-- dura clk_freq / (4 x i2c_freq) ciclos de clock (arredondado para baixo, no
-- mínimo um). O barramento é de dreno aberto: o periférico nunca leva SDA nem
-- SCL a '1', só os libera (o_sda_oe e o_scl_oe em '0'), e a camada de tristate
-- do topo coloca o pino em alta impedância. O resistor de pull-up da placa
-- leva a linha a '1'. O alongamento de SCL pelo escravo não é tratado.
--
-- i_sda deve chegar sincronizada em i_clk. Um pedido enquanto o_busy vale '1'
-- é ignorado.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.utils_pkg.all;

entity hdmi_i2c_writer is
    generic (
        -- Frequência do clock do sistema em Hz.
        clk_freq : positive                     := 100_000_000;
        -- Frequência de SCL em Hz.
        i2c_freq : positive                     := 100_000;
        -- Endereço de 7 bits do escravo.
        dev_addr : std_logic_vector(6 downto 0) := "0111001"
    );
    port (
        -- Clock do sistema.
        i_clk    : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst    : in    std_logic;

        -- Pulso de um ciclo que pede a escrita de i_value em i_reg.
        i_start  : in    std_logic;
        -- Endereço do registrador do escravo.
        i_reg    : in    std_logic_vector(7 downto 0);
        -- Valor a escrever no registrador.
        i_value  : in    std_logic_vector(7 downto 0);

        -- A transação está em andamento ('1' do pedido até o pulso de o_done).
        o_busy   : out   std_logic;
        -- Pulso de um ciclo no fim da transação.
        o_done   : out   std_logic;
        -- Alguma confirmação não veio ('1' durante e depois do pulso de o_done, até o próximo pedido).
        o_nack   : out   std_logic;

        -- Nível da linha SDA lido do pino, já sincronizado em i_clk.
        i_sda    : in    std_logic;
        -- Valor que o periférico leva a SDA quando a habilita (sempre '0').
        o_sda_out : out   std_logic;
        -- Habilitação de saída de SDA ('1' = SDA puxada para baixo).
        o_sda_oe : out   std_logic;
        -- Valor que o periférico leva a SCL quando a habilita (sempre '0').
        o_scl_out : out   std_logic;
        -- Habilitação de saída de SCL ('1' = SCL puxada para baixo).
        o_scl_oe : out   std_logic
    );
end entity hdmi_i2c_writer;

architecture rtl of hdmi_i2c_writer is

    -- Ciclos de clock de um quarto de bit de SCL.
    constant QUARTER : positive := pick(clk_freq / (4 * i2c_freq) > 0, clk_freq / (4 * i2c_freq), 1);

    -- Estados da transação.
    type state_t is (S_IDLE, S_START, S_DATA, S_STOP);

    -- Estado atual.
    signal state    : state_t                       := S_IDLE;
    -- Quarto de bit atual (0 a 3).
    signal phase    : natural range 0 to 3          := 0;
    -- Ciclos já contados do quarto de bit atual.
    signal tick_cnt : natural range 0 to QUARTER - 1 := 0;
    -- Bit atual dentro do byte (0 a 7 são dados, 8 é a confirmação).
    signal bit_idx  : natural range 0 to 8          := 0;
    -- Byte atual da transação (0 endereço do escravo, 1 registrador, 2 valor).
    signal byte_idx : natural range 0 to 2          := 0;
    -- Bytes a enviar, o próximo bit no bit mais alto.
    signal shifter  : std_logic_vector(23 downto 0) := (others => '0');
    -- SDA puxada para baixo.
    signal sda_low  : std_logic                     := '0';
    -- SCL puxada para baixo.
    signal scl_low  : std_logic                     := '0';
    -- Alguma confirmação faltou na transação atual.
    signal nack_q   : std_logic                     := '0';
    -- Pulso de fim de transação.
    signal done_q   : std_logic                     := '0';

begin

    o_busy    <= to_sl(state /= S_IDLE);
    o_done    <= done_q;
    o_nack    <= nack_q;
    o_sda_out <= '0';
    o_scl_out <= '0';
    o_sda_oe  <= sda_low;
    o_scl_oe  <= scl_low;

    p_fsm : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            done_q <= '0';

            if i_rst = '1' then
                state    <= S_IDLE;
                phase    <= 0;
                tick_cnt <= 0;
                bit_idx  <= 0;
                byte_idx <= 0;
                sda_low  <= '0';
                scl_low  <= '0';
                nack_q   <= '0';
            elsif state = S_IDLE then
                if i_start = '1' then
                    shifter  <= dev_addr & '0' & i_reg & i_value;
                    nack_q   <= '0';
                    state    <= S_START;
                    phase    <= 0;
                    tick_cnt <= 0;
                end if;
            elsif tick_cnt /= QUARTER - 1 then
                tick_cnt <= tick_cnt + 1;
            else
                tick_cnt <= 0;
                phase    <= pick(phase = 3, 0, phase + 1);

                case state is
                    when S_START =>
                        -- Partida: SDA cai com SCL alta, depois SCL cai.
                        case phase is
                            when 1 =>
                                sda_low <= '1';
                            when 2 =>
                                scl_low <= '1';
                            when 3 =>
                                state    <= S_DATA;
                                bit_idx  <= 0;
                                byte_idx <= 0;
                            when others =>
                                null;
                        end case;
                    when S_DATA =>
                        -- Bit: dado com SCL baixa, SCL alta, amostra da confirmação, SCL baixa.
                        case phase is
                            when 0 =>
                                if bit_idx = 8 then
                                    sda_low <= '0';
                                else
                                    sda_low <= not shifter(23);
                                end if;
                            when 1 =>
                                scl_low <= '0';
                            when 2 =>
                                if bit_idx = 8 and i_sda = '1' then
                                    nack_q <= '1';
                                end if;
                            when others =>
                                scl_low <= '1';
                                if bit_idx = 8 then
                                    bit_idx <= 0;
                                    if byte_idx = 2 then
                                        state <= S_STOP;
                                    else
                                        byte_idx <= byte_idx + 1;
                                    end if;
                                else
                                    bit_idx <= bit_idx + 1;
                                    shifter <= shifter(22 downto 0) & '0';
                                end if;
                        end case;
                    when others =>
                        -- Parada: SDA baixa, SCL sobe, SDA sobe com SCL alta.
                        case phase is
                            when 0 =>
                                sda_low <= '1';
                            when 1 =>
                                scl_low <= '0';
                            when 2 =>
                                sda_low <= '0';
                            when others =>
                                state  <= S_IDLE;
                                done_q <= '1';
                        end case;
                end case;
            end if;
        end if;

    end process p_fsm;

end architecture rtl;
