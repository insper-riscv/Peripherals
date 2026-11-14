-- =============================================================================
-- Modelo comportamental do núcleo altera_modular_adc (variante autônoma)
--
-- Só para a simulação: o GHDL não tem o modelo do IP da Intel, e este modelo
-- reproduz o que o max10_adc enxerga dele, a interface Avalon-ST de comando e
-- resposta, como o código-fonte do núcleo a implementa. Um comando válido é
-- levado a termo em conversion_cycles ciclos; ao fim o núcleo ergue o ready e
-- a resposta por um ciclo, com o canal do comando, o startofpacket e o
-- endofpacket que ele trouxe. Com rsp_late a resposta sai um ciclo depois do
-- ready. Depois do ready o modelo ignora o comando por um ciclo, o tempo de o
-- mestre baixar o valid, e entre dois comandos há ao menos um ciclo sem ready.
--
-- A tensão de cada canal chega por i_analog (12 bits por canal, o canal 0 nos
-- bits 11:0), já em contagens do conversor. O comando 31 (recalibração) não
-- tem resposta. O modelo acusa, por assert, o comando que muda ou cai antes do
-- ready, que o protocolo proíbe.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.max10_adc_consts.all;

entity max10_adc_core_model is
    generic (
        -- Ciclos de clock de uma conversão, do comando ao ready.
        conversion_cycles : positive := 12;
        -- A resposta sai um ciclo depois do ready.
        rsp_late          : boolean  := false
    );
    port (
        -- Clock do núcleo.
        i_clk         : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst         : in    std_logic;
        -- Valor de cada canal, 12 bits por canal.
        i_analog      : in    std_logic_vector(ADC_CHANNELS * ADC_SAMPLE_BITS - 1 downto 0);
        -- Comando válido.
        i_cmd_valid   : in    std_logic;
        -- Número do canal do comando.
        i_cmd_channel : in    std_logic_vector(ADC_CHANNEL_BITS - 1 downto 0);
        -- Primeiro comando do pacote.
        i_cmd_sop     : in    std_logic;
        -- Último comando do pacote.
        i_cmd_eop     : in    std_logic;
        -- Comando aceito.
        o_cmd_ready   : out   std_logic;
        -- Resposta válida.
        o_rsp_valid   : out   std_logic;
        -- Número do canal da resposta.
        o_rsp_channel : out   std_logic_vector(ADC_CHANNEL_BITS - 1 downto 0);
        -- Amostra da resposta.
        o_rsp_data    : out   std_logic_vector(ADC_SAMPLE_BITS - 1 downto 0);
        -- Primeira resposta do pacote.
        o_rsp_sop     : out   std_logic;
        -- Última resposta do pacote.
        o_rsp_eop     : out   std_logic
    );
end entity max10_adc_core_model;

architecture sim of max10_adc_core_model is

    -- Fases do modelo.
    type state_t is (S_IDLE, S_CONVERT, S_LATE, S_GAP);

    -- Fase atual.
    signal state   : state_t;
    -- Ciclos que faltam para o fim da conversão.
    signal left    : natural range 0 to conversion_cycles;
    -- Canal do comando em conversão.
    signal channel : std_logic_vector(ADC_CHANNEL_BITS - 1 downto 0) := (others => '0');
    -- Startofpacket do comando em conversão.
    signal sop     : std_logic;
    -- Endofpacket do comando em conversão.
    signal eop     : std_logic;
    -- Amostra do comando em conversão.
    signal data    : std_logic_vector(ADC_SAMPLE_BITS - 1 downto 0)  := (others => '0');

begin

    p_core : process (i_clk) is
        -- Canal do comando como inteiro.
        variable v_channel : natural;
    begin

        if rising_edge(i_clk) then
            o_cmd_ready <= '0';
            o_rsp_valid <= '0';
            o_rsp_sop   <= '0';
            o_rsp_eop   <= '0';
            if i_rst = '1' then
                state <= S_IDLE;
                left  <= 0;
            else
                case state is

                    when S_IDLE =>

                        if i_cmd_valid = '1' then
                            v_channel := to_integer(unsigned(i_cmd_channel));
                            channel   <= i_cmd_channel;
                            sop       <= i_cmd_sop;
                            eop       <= i_cmd_eop;
                            if v_channel < ADC_CHANNELS then
                                data <= i_analog(v_channel * ADC_SAMPLE_BITS + ADC_SAMPLE_BITS - 1
                                                 downto v_channel * ADC_SAMPLE_BITS);
                            else
                                data <= (others => '0');
                            end if;
                            left  <= conversion_cycles;
                            state <= S_CONVERT;
                        end if;

                    when S_CONVERT =>

                        assert i_cmd_valid = '1' and i_cmd_channel = channel and i_cmd_sop = sop and i_cmd_eop = eop
                            report "o comando mudou ou caiu antes do ready"
                            severity failure;
                        if left = 1 then
                            o_cmd_ready <= '1';
                            if unsigned(channel) /= 31 then
                                if rsp_late then
                                    state <= S_LATE;
                                else
                                    o_rsp_valid <= '1';
                                    o_rsp_sop   <= sop;
                                    o_rsp_eop   <= eop;
                                    state       <= S_GAP;
                                end if;
                            else
                                state <= S_GAP;
                            end if;
                        else
                            left <= left - 1;
                        end if;

                    when S_GAP =>

                        state <= S_IDLE;

                    when S_LATE =>

                        o_rsp_valid <= '1';
                        o_rsp_sop   <= sop;
                        o_rsp_eop   <= eop;
                        state       <= S_IDLE;

                end case;
            end if;
        end if;

    end process p_core;

    o_rsp_channel <= channel;
    o_rsp_data    <= data;

end architecture sim;
