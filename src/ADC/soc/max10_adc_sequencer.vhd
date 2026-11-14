-- =============================================================================
-- Sequenciador de varredura do ADC do MAX 10
--
-- Percorre os canais marcados numa máscara, do menor número ao maior, e leva
-- cada um ao núcleo altera_modular_adc pela interface Avalon-ST de comando
-- (valid, channel, startofpacket, endofpacket, ready) e recolhe a amostra pela
-- interface de resposta (valid, channel, data). Um pedido de início com o
-- sequenciador livre trava a máscara e inicia a varredura; o pedido com ele
-- ocupado é ignorado.
--
-- Protocolo com o núcleo, como o código-fonte do núcleo o implementa: o
-- comando fica válido até o ready, que o núcleo ergue por um ciclo quando a
-- conversão termina, junto da resposta (ou antes dela, nunca depois). O
-- startofpacket marca o primeiro canal da varredura e o endofpacket o último.
-- Uma resposta só vale com um comando em andamento e com o número de canal que
-- foi pedido; qualquer outra é ignorada.
--
-- Fases: S_IDLE espera o início; S_PICK escolhe o próximo canal pendente ou
-- encerra; S_CMD mantém o comando válido; S_RSP espera a resposta de um
-- comando já aceito; S_FINISH dura um ciclo, com o pulso de o_done e o
-- o_busy ainda em '1', de modo que o fim de varredura e a queda de o_busy
-- aparecem juntos ao software.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.max10_adc_consts.all;

entity max10_adc_sequencer is
    port (
        -- Clock do módulo.
        i_clk            : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst            : in    std_logic;
        -- Pedido de início de varredura (um ciclo); ignorado com o sequenciador ocupado.
        i_start          : in    std_logic;
        -- Máscara de canais da varredura, lida no ciclo do início.
        i_mask           : in    std_logic_vector(ADC_CHANNELS - 1 downto 0);
        -- Comando válido para o núcleo.
        o_cmd_valid      : out   std_logic;
        -- Número do canal a converter.
        o_cmd_channel    : out   std_logic_vector(ADC_CHANNEL_BITS - 1 downto 0);
        -- Primeiro comando da varredura.
        o_cmd_sop        : out   std_logic;
        -- Último comando da varredura.
        o_cmd_eop        : out   std_logic;
        -- O núcleo aceitou o comando.
        i_cmd_ready      : in    std_logic;
        -- Resposta válida do núcleo.
        i_rsp_valid      : in    std_logic;
        -- Número do canal da resposta.
        i_rsp_channel    : in    std_logic_vector(ADC_CHANNEL_BITS - 1 downto 0);
        -- Amostra da resposta.
        i_rsp_data       : in    std_logic_vector(ADC_SAMPLE_BITS - 1 downto 0);
        -- Varredura em curso (inclui o ciclo do pulso de o_done).
        o_busy           : out   std_logic;
        -- Pulso de um ciclo no fim da varredura.
        o_done           : out   std_logic;
        -- Pulso de um ciclo: o_sample_channel e o_sample_data trazem uma amostra aceita.
        o_sample_valid   : out   std_logic;
        -- Número do canal da amostra aceita.
        o_sample_channel : out   std_logic_vector(ADC_CHANNEL_BITS - 1 downto 0);
        -- Valor da amostra aceita.
        o_sample_data    : out   std_logic_vector(ADC_SAMPLE_BITS - 1 downto 0)
    );
end entity max10_adc_sequencer;

architecture rtl of max10_adc_sequencer is

    -- Fases do sequenciador.
    type state_t is (S_IDLE, S_PICK, S_CMD, S_RSP, S_FINISH);

    -- Fase atual.
    signal state     : state_t                                  := S_IDLE;
    -- Canais da varredura ainda sem amostra, o atual incluído.
    signal pending   : std_logic_vector(ADC_CHANNELS - 1 downto 0) := (others => '0');
    -- Canal em conversão.
    signal current   : natural range 0 to ADC_CHANNELS - 1       := 0;
    -- O canal em conversão é o primeiro da varredura.
    signal first     : std_logic                                := '0';
    -- Pendentes sem o canal atual.
    signal rest      : std_logic_vector(ADC_CHANNELS - 1 downto 0);
    -- A resposta do ciclo é a do comando em andamento.
    signal rsp_match : std_logic;
    -- A resposta do ciclo é aceita.
    signal accept    : std_logic;

    -- Menor índice com bit em '1' (zero se não há nenhum).
    function lowest_set (mask : std_logic_vector) return natural is
    begin

        for i in mask'low to mask'high loop

            if mask(i) = '1' then
                return i;
            end if;

        end loop;

        return 0;

    end function lowest_set;

begin

    p_rest : process (pending, current) is
    begin

        rest          <= pending;
        rest(current) <= '0';

    end process p_rest;

    rsp_match <= '1' when i_rsp_valid = '1' and to_integer(unsigned(i_rsp_channel)) = current else '0';

    -- Uma resposta é aceita no ciclo do ready (que a traz junto) ou depois dele.
    accept <= rsp_match when (state = S_CMD and i_cmd_ready = '1') or state = S_RSP else '0';

    o_cmd_valid   <= '1' when state = S_CMD else '0';
    o_cmd_channel <= std_logic_vector(to_unsigned(current, ADC_CHANNEL_BITS));
    o_cmd_sop     <= first;
    o_cmd_eop     <= '1' when unsigned(rest) = 0 else '0';

    o_busy <= '0' when state = S_IDLE else '1';
    o_done <= '1' when state = S_FINISH else '0';

    o_sample_valid   <= accept;
    o_sample_channel <= i_rsp_channel;
    o_sample_data    <= i_rsp_data;

    p_sequence : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            if i_rst = '1' then
                state   <= S_IDLE;
                pending <= (others => '0');
                current <= 0;
                first   <= '0';
            else
                case state is

                    when S_IDLE =>

                        if i_start = '1' then
                            pending <= i_mask;
                            first   <= '1';
                            state   <= S_PICK;
                        end if;

                    when S_PICK =>

                        if unsigned(pending) = 0 then
                            state <= S_FINISH;
                        else
                            current <= lowest_set(pending);
                            state   <= S_CMD;
                        end if;

                    when S_CMD =>

                        if accept = '1' then
                            pending(current) <= '0';
                            first            <= '0';
                            state            <= S_PICK;
                        elsif i_cmd_ready = '1' then
                            state <= S_RSP;
                        end if;

                    when S_RSP =>

                        if accept = '1' then
                            pending(current) <= '0';
                            first            <= '0';
                            state            <= S_PICK;
                        end if;

                    when S_FINISH =>

                        state <= S_IDLE;

                end case;
            end if;
        end if;

    end process p_sequence;

end architecture rtl;
