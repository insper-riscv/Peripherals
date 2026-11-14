-- =============================================================================
-- Periférico do ADC interno do MAX 10, mapeado em memória
--
-- Envolve a interface Avalon-ST do núcleo altera_modular_adc (comando e
-- resposta por canal) com registradores. O sequenciador (max10_adc_sequencer)
-- varre os canais da máscara; este topo guarda a configuração, decide quando
-- uma varredura começa (pedido do processador ou período vencido), guarda a
-- última amostra de cada canal com os flags de conversão e gera a interrupção
-- de fim de varredura.
--
-- Taxa de varredura: uma varredura nova começa a cada PERIOD ciclos de i_clk
-- no modo contínuo (f_varredura = f_clk / PERIOD), ou logo que a anterior
-- termina quando ela dura mais que o período. O período de reset sai de
-- clk_freq / scan_freq.
--
-- Cada canal tem um registrador de resultado: bits 11:0 a amostra, bit 12 um
-- resultado novo ainda não lido, bit 13 um resultado sobrescrito sem ser lido.
-- A leitura do registrador limpa os bits 12 e 13; uma amostra que chega no
-- mesmo ciclo da leitura fica como resultado novo.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.config_pkg.all;
use work.max10_adc_consts.all;

entity max10_adc is
    generic (
        -- Frequência de i_clk em Hz.
        clk_freq  : positive := 100_000_000;
        -- Frequência de varredura em Hz que o período tem ao sair do reset.
        scan_freq : positive := 1000
    );
    port (
        -- Clock do módulo.
        i_clk         : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst         : in    std_logic;
        -- Pulso de escrita do processador.
        i_write       : in    std_logic;
        -- Pulso de leitura do processador.
        i_read        : in    std_logic;
        -- Endereço de palavra do registrador.
        i_address     : in    std_logic_vector(ADC_ADDR_BITS - 1 downto 0);
        -- Dado de escrita do processador.
        i_data_in     : in    word_t;
        -- Dado de leitura para o processador (zero fora de uma leitura).
        o_data_out    : out   word_t;
        -- Requisição de interrupção de nível, ativa em '1'.
        o_irq         : out   std_logic;
        -- Comando válido para o núcleo do ADC.
        o_cmd_valid   : out   std_logic;
        -- Número do canal a converter.
        o_cmd_channel : out   std_logic_vector(ADC_CHANNEL_BITS - 1 downto 0);
        -- Primeiro comando da varredura.
        o_cmd_sop     : out   std_logic;
        -- Último comando da varredura.
        o_cmd_eop     : out   std_logic;
        -- O núcleo aceitou o comando.
        i_cmd_ready   : in    std_logic;
        -- Resposta válida do núcleo.
        i_rsp_valid   : in    std_logic;
        -- Número do canal da resposta.
        i_rsp_channel : in    std_logic_vector(ADC_CHANNEL_BITS - 1 downto 0);
        -- Amostra da resposta.
        i_rsp_data    : in    std_logic_vector(ADC_SAMPLE_BITS - 1 downto 0)
    );
end entity max10_adc;

architecture rtl of max10_adc is

    -- Resultados dos canais.
    type sample_array_t is array (0 to ADC_CHANNELS - 1) of std_logic_vector(ADC_SAMPLE_BITS - 1 downto 0);

    -- Período de reset calculado dos generics, nunca zero.
    function default_period return natural is
        -- Período em ciclos, antes do piso de 1.
        variable v_period : natural;
    begin

        v_period := clk_freq / scan_freq;
        if v_period < 1 then
            return 1;
        end if;

        return v_period;

    end function default_period;

    -- Período de reset como vetor de 32 bits.
    constant RESET_PERIOD : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(default_period, 32));

    -- Sequenciador ligado.
    signal ctrl_enable     : std_logic                     := '0';
    -- Varredura repetida a cada período.
    signal ctrl_continuous : std_logic                     := '0';
    -- Habilita a interrupção de fim de varredura.
    signal ctrl_irq_en     : std_logic                     := '0';
    -- Máscara de canais da varredura.
    signal mask            : std_logic_vector(ADC_CHANNELS - 1 downto 0) := (others => '0');
    -- Período entre varreduras, em ciclos de i_clk.
    signal period          : std_logic_vector(31 downto 0)             := RESET_PERIOD;
    -- Bit sticky de fim de varredura.
    signal st_done         : std_logic                     := '0';
    -- Bit sticky de início com varredura em curso.
    signal st_late         : std_logic                     := '0';
    -- Ciclos desde o último início de varredura.
    signal elapsed         : unsigned(31 downto 0)         := unsigned(RESET_PERIOD);
    -- O período venceu.
    signal due             : std_logic;
    -- Escrita no registrador de controle que pede a varredura única.
    signal manual_start    : std_logic;
    -- Início pedido, por período ou pelo processador, com o sequenciador ligado.
    signal start_wanted    : std_logic;
    -- Início entregue ao sequenciador.
    signal seq_start       : std_logic;
    -- Sequenciador ocupado.
    signal seq_busy        : std_logic;
    -- Pulso de fim de varredura.
    signal seq_done        : std_logic;
    -- O sequenciador entregou uma amostra.
    signal sample_valid    : std_logic;
    -- Canal da amostra.
    signal sample_channel  : std_logic_vector(ADC_CHANNEL_BITS - 1 downto 0);
    -- Valor da amostra.
    signal sample_data     : std_logic_vector(ADC_SAMPLE_BITS - 1 downto 0);
    -- Último resultado de cada canal.
    signal samples         : sample_array_t;
    -- Resultado novo ainda não lido, por canal.
    signal valid_flags     : std_logic_vector(ADC_CHANNELS - 1 downto 0);
    -- Resultado sobrescrito sem leitura, por canal.
    signal overrun_flags   : std_logic_vector(ADC_CHANNELS - 1 downto 0);
    -- Canal que a leitura do ciclo seleciona, ou ADC_CHANNELS se o endereço não é de canal.
    signal read_channel    : natural range 0 to ADC_CHANNELS;
    -- Palavra de estado.
    signal status_word     : word_t;
    -- Palavra lida no endereço atual.
    signal read_word       : word_t;

begin

    due          <= '1' when elapsed >= unsigned(period) else '0';
    manual_start <= i_write and i_data_in(CTRL_START_BIT) when i_address = ADDR_CTRL else '0';

    -- Com o sequenciador desligado ou fora do modo contínuo o período é dado como vencido, e o primeiro início
    -- sai logo que o modo contínuo é ligado.
    start_wanted <= ctrl_enable and (manual_start or (ctrl_continuous and due));
    seq_start    <= start_wanted and not seq_busy;

    u_sequencer : entity work.max10_adc_sequencer
        port map (
            i_clk            => i_clk,
            i_rst            => i_rst,
            i_start          => seq_start,
            i_mask           => mask,
            o_cmd_valid      => o_cmd_valid,
            o_cmd_channel    => o_cmd_channel,
            o_cmd_sop        => o_cmd_sop,
            o_cmd_eop        => o_cmd_eop,
            i_cmd_ready      => i_cmd_ready,
            i_rsp_valid      => i_rsp_valid,
            i_rsp_channel    => i_rsp_channel,
            i_rsp_data       => i_rsp_data,
            o_busy           => seq_busy,
            o_done           => seq_done,
            o_sample_valid   => sample_valid,
            o_sample_channel => sample_channel,
            o_sample_data    => sample_data
        );

    -- Registradores de configuração, contador do período e bits sticky de estado.
    p_regs : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            if i_rst = '1' then
                ctrl_enable     <= '0';
                ctrl_continuous <= '0';
                ctrl_irq_en     <= '0';
                mask            <= (others => '0');
                period          <= RESET_PERIOD;
                st_done         <= '0';
                st_late         <= '0';
                elapsed         <= unsigned(RESET_PERIOD);
            else
                -- Escrita em STATUS limpa os bits sticky em que vale '1'; um evento do mesmo ciclo prevalece.
                if i_write = '1' and i_address = ADDR_STATUS then
                    st_done <= st_done and not i_data_in(ST_DONE_BIT);
                    st_late <= st_late and not i_data_in(ST_LATE_BIT);
                end if;

                if seq_done = '1' then
                    st_done <= '1';
                end if;
                if start_wanted = '1' and seq_busy = '1' then
                    st_late <= '1';
                end if;

                if seq_start = '1' then
                    -- O ciclo do início já conta, e dois inícios ficam a PERIOD ciclos um do outro.
                    elapsed <= to_unsigned(1, elapsed'length);
                elsif ctrl_enable = '0' or ctrl_continuous = '0' then
                    elapsed <= unsigned(period);
                elsif due = '0' then
                    elapsed <= elapsed + 1;
                end if;

                if i_write = '1' then
                    case i_address is

                        when ADDR_CTRL =>
                            ctrl_enable     <= i_data_in(CTRL_ENABLE_BIT);
                            ctrl_continuous <= i_data_in(CTRL_CONTINUOUS_BIT);
                            ctrl_irq_en     <= i_data_in(CTRL_IRQ_BIT);
                        when ADDR_MASK =>
                            mask <= i_data_in(ADC_CHANNELS - 1 downto 0);
                        when ADDR_PERIOD =>
                            period <= i_data_in(31 downto 0);
                        when others =>
                            null;

                    end case;
                end if;
            end if;
        end if;

    end process p_regs;

    -- Canal que uma leitura do ciclo seleciona.
    p_read_channel : process (i_address) is
        -- Endereço como inteiro.
        variable v_address : natural;
    begin

        v_address := to_integer(unsigned(i_address));
        if v_address >= ADDR_CHANNEL_BASE and v_address < ADDR_CHANNEL_BASE + ADC_CHANNELS then
            read_channel <= v_address - ADDR_CHANNEL_BASE;
        else
            read_channel <= ADC_CHANNELS;
        end if;

    end process p_read_channel;

    -- Resultados dos canais e seus flags de conversão.
    p_samples : process (i_clk) is
        -- Canal da amostra que chegou.
        variable v_channel : natural;
    begin

        if rising_edge(i_clk) then
            if i_rst = '1' then
                samples       <= (others => (others => '0'));
                valid_flags   <= (others => '0');
                overrun_flags <= (others => '0');
            else
                -- A leitura de um canal consome o resultado e o sobrescrito.
                if i_read = '1' and read_channel < ADC_CHANNELS then
                    valid_flags(read_channel)   <= '0';
                    overrun_flags(read_channel) <= '0';
                end if;

                -- Uma amostra nova substitui o resultado; o anterior ainda não lido vira sobrescrito, a menos
                -- que seja lido no mesmo ciclo.
                if sample_valid = '1' then
                    v_channel := to_integer(unsigned(sample_channel));
                    if v_channel < ADC_CHANNELS then
                        samples(v_channel)     <= sample_data;
                        valid_flags(v_channel) <= '1';
                        if i_read = '1' and read_channel = v_channel then
                            overrun_flags(v_channel) <= '0';
                        else
                            overrun_flags(v_channel) <= overrun_flags(v_channel) or valid_flags(v_channel);
                        end if;
                    end if;
                end if;
            end if;
        end if;

    end process p_samples;

    o_irq <= st_done and ctrl_irq_en;

    status_word(ST_BUSY_BIT)                       <= seq_busy;
    status_word(ST_DONE_BIT)                       <= st_done;
    status_word(ST_LATE_BIT)                       <= st_late;
    status_word(word_t'high downto ST_LATE_BIT + 1) <= (others => '0');

    -- Leitura combinacional por endereço.
    p_read : process (all) is
    begin

        read_word <= (others => '0');
        if read_channel < ADC_CHANNELS then
            read_word(ADC_SAMPLE_BITS - 1 downto 0) <= samples(read_channel);
            read_word(CH_VALID_BIT)                 <= valid_flags(read_channel);
            read_word(CH_OVERRUN_BIT)               <= overrun_flags(read_channel);
        else
            case i_address is

                when ADDR_CTRL =>
                    read_word(CTRL_ENABLE_BIT)     <= ctrl_enable;
                    read_word(CTRL_CONTINUOUS_BIT) <= ctrl_continuous;
                    read_word(CTRL_IRQ_BIT)        <= ctrl_irq_en;
                when ADDR_MASK =>
                    read_word(ADC_CHANNELS - 1 downto 0) <= mask;
                when ADDR_PERIOD =>
                    read_word(31 downto 0) <= period;
                when ADDR_STATUS =>
                    read_word <= status_word;
                when others =>
                    null;

            end case;
        end if;

    end process p_read;

    o_data_out <= read_word when i_read = '1' else (others => '0');

end architecture rtl;
