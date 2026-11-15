-- ==========================================================================
-- Controlador do acelerômetro ADXL345 por I2C (DE0-Nano e DE10-Lite)
-- ==========================================================================
-- O ADXL345 entra no modo I2C quando a seleção de chip fica em nível alto, e
-- este controlador a mantém em '1' em o_adxl_cs_n. A sequência é a do
-- controlador SPI (adxl345), com o mesmo mapa de registradores: ao ser
-- habilitado, configura o chip e depois lê, em intervalos fixos ou a cada
-- aviso de dado pronto no pino de interrupção escolhido, os seis bytes dos
-- eixos X, Y e Z. Cada eixo vira um registrador de 32 bits com o valor de 16
-- bits em complemento de dois estendido em sinal. A linha é a do núcleo
-- i2c_core (o mesmo do mestre I2C), com SCL e SDA em dreno aberto.
--
-- Endereço do escravo, de 7 bits: 0x1D com o pino SDO em nível alto e 0x53 com
-- SDO em nível baixo. O generic address_select_high escolhe o endereço e o
-- nível que o controlador põe em o_adxl_sdo, para as placas em que o SDO é um
-- pino da FPGA (DE10-Lite); onde o SDO é fixo na placa, o_adxl_sdo fica livre.
--
-- Sequência de configuração, depois de ENABLE ou de uma escrita em CONTROL:
--   0. lê DEVID (0x00), que fica no registrador DEVID;
--   1. BW_RATE (0x2C) recebe o código de taxa de RATE;
--   2. DATA_FORMAT (0x31) recebe FULL_RES e RANGE;
--   3. INT_MAP (0x2F) leva o dado pronto para INT1 (INT_PIN em 0) ou INT2;
--   4. INT_ENABLE (0x2E) recebe 0x80 (dado pronto);
--   5. POWER_CTL (0x2D) recebe 0x08 (medição).
-- Cada escrita de registrador é início, endereço do escravo com escrita,
-- endereço do registrador, valor e parada. A leitura em rajada de DATAX0
-- (0x32) a DATAZ1 (0x37) é início, endereço com escrita, endereço do
-- registrador, repetição de início, endereço com leitura, cinco bytes com ACK e
-- um com NACK e parada.
--
-- Os endereços e valores vêm da folha de dados do ADXL345, que não está no
-- repositório, então são suposições a conferir (ver adxl345_consts).
--
-- Mapa de registradores, em endereços de palavra:
--
--   0 X        R      eixo X, 16 bits em complemento de dois estendidos
--   1 Y        R      eixo Y
--   2 Z        R      eixo Z
--   3 STATUS   R/W1C  bit 0 BUSY, 1 SAMPLE (amostra nova), 2 VALID (já houve
--                     uma amostra), 3 CONFIGURED, 4 NACK (o escravo não
--                     respondeu), 5 ARB_LOST (arbitragem perdida), 6 INT1 e 7
--                     INT2 (nível sincronizado dos pinos); limpam por escrita de
--                     1 os bits 1, 4 e 5
--   4 CONTROL  R/W    bit 0 ENABLE, 1 IRQ_ENABLE, 3:2 RANGE (0 a 3 para
--                     2, 4, 8 e 16 g), 4 FULL_RES, 5 USE_INT (leitura pelo
--                     pino de interrupção em vez do tempo), 6 INT_PIN (0 INT1,
--                     1 INT2), 11:8 RATE
--   5 PERIOD   R/W    bits 23:0, ciclos entre amostras sem USE_INT
--   6 DEVID    R      bits 7:0, último DEVID lido
--   7 DIVIDER  R/W    bits 15:0, SCL = clock / (5 * (DIVIDER + 1)), mínimo 2
--
-- Uma escrita em CONTROL repete a configuração na próxima oportunidade e um
-- NACK ou uma arbitragem perdida encerra a sequência até a próxima escrita em
-- CONTROL. A saída o_irq é de nível e vale SAMPLE com IRQ_ENABLE.
-- ==========================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.config_pkg.all;
use work.i2c_consts.all;
use work.adxl345_consts.all;

entity adxl345_i2c is
    generic (
        -- Frequência do clock do módulo, em hertz.
        clock_hz            : positive := 50_000_000;
        -- Frequência de SCL depois do reset, em hertz (o chip aceita até 400 kHz).
        scl_hz              : positive := 100_000;
        -- Amostras por segundo depois do reset, quando o intervalo é por tempo.
        sample_hz           : positive := 100;
        -- Intervalo mínimo entre uma parada e o início seguinte, em nanossegundos.
        bus_free_ns         : positive := 1300;
        -- Verdadeiro com SDO em nível alto (endereço 0x1D); falso com SDO em nível baixo (0x53).
        address_select_high : boolean  := false
    );
    port (
        -- Clock do módulo.
        i_clk          : in    std_logic;
        -- Reset síncrono, ativo em nível alto.
        i_rst          : in    std_logic;
        -- Dado de escrita vindo do processador.
        i_data_in      : in    word_t;
        -- Endereço de palavra do registrador, entre zero e sete.
        i_address      : in    std_logic_vector(2 downto 0);
        -- Pulso de escrita do processador.
        i_write        : in    std_logic;
        -- Dado de leitura devolvido ao processador.
        o_data_out     : out   word_t;
        -- Requisição de interrupção de nível.
        o_irq          : out   std_logic;
        -- Seleção de chip do acelerômetro, sempre em '1' (modo I2C).
        o_adxl_cs_n    : out   std_logic;
        -- Seleção de endereço (SDO) do acelerômetro, conforme address_select_high.
        o_adxl_sdo     : out   std_logic;
        -- Puxa SCL para baixo quando '1' (o topo da placa liga o tristate).
        o_adxl_scl_low : out   std_logic;
        -- Puxa SDA para baixo quando '1' (o topo da placa liga o tristate).
        o_adxl_sda_low : out   std_logic;
        -- Nível lido do pino SCL.
        i_adxl_scl     : in    std_logic;
        -- Nível lido do pino SDA.
        i_adxl_sda     : in    std_logic;
        -- Interrupção 1 do acelerômetro, ativa em nível alto.
        i_adxl_int1    : in    std_logic;
        -- Interrupção 2 do acelerômetro, ativa em nível alto.
        i_adxl_int2    : in    std_logic
    );
end entity adxl345_i2c;

architecture rtl of adxl345_i2c is

    -- Divisor do reset, que mantém SCL em scl_hz ou abaixo, nunca abaixo do mínimo do núcleo.
    function default_divider return natural is
        -- Divisor em construção.
        variable div : natural;
    begin

        div := (clock_hz + 5 * scl_hz - 1) / (5 * scl_hz);

        if div < MIN_DIVIDER + 1 then
            return MIN_DIVIDER;
        end if;

        return div - 1;

    end function default_divider;

    -- Endereço de 7 bits do escravo.
    function slave_address return std_logic_vector is
    begin

        if address_select_high then
            return I2C_ADDR_SDO_HIGH;
        end if;

        return I2C_ADDR_SDO_LOW;

    end function slave_address;

    -- Divisor do reset como vetor.
    constant RESET_DIVIDER  : std_logic_vector(15 downto 0) := std_logic_vector(to_unsigned(default_divider, 16));
    -- Intervalo entre amostras depois do reset, em ciclos.
    constant RESET_PERIOD   : natural                       := clock_hz / sample_hz;
    -- Ciclos de espera entre transações, com a linha livre.
    constant GAP_CYCLES     : positive                      := (bus_free_ns * (clock_hz / 1000) + 999_999) / 1_000_000;
    -- Endereço do escravo com o bit de escrita.
    constant ADDR_WRITE     : std_logic_vector(7 downto 0)  := slave_address & '0';
    -- Endereço do escravo com o bit de leitura.
    constant ADDR_READ      : std_logic_vector(7 downto 0)  := slave_address & '1';
    -- Último passo da configuração.
    constant LAST_CONFIG    : natural                       := 5;
    -- Passo da leitura dos eixos.
    constant SAMPLE_STEP    : natural                       := 6;
    -- Bytes lidos em cada passo de leitura: o DEVID e os seis dos eixos.
    constant DEVID_BYTES    : natural                       := 1;
    -- Bytes lidos dos eixos.
    constant AXIS_BYTES     : natural                       := 6;
    -- Índice de comando que só gera a parada, usado para soltar a linha depois de um NACK.
    constant STOP_ONLY_IDX  : natural                       := 9;
    -- Índice do primeiro comando de leitura de byte numa transação de leitura.
    constant FIRST_READ_IDX : natural                       := 3;
    -- Índice do último comando de uma transação de escrita.
    constant LAST_WRITE_IDX : natural                       := 2;

    -- Estados da sequência.
    type state_t is (S_IDLE, S_ISSUE, S_WAIT, S_GAP);

    -- Estado da sequência.
    signal state       : state_t;
    -- Passo da sequência: configuração de 0 a 5 e leitura dos eixos em 6.
    signal step        : natural range 0 to SAMPLE_STEP;
    -- Índice do comando dentro da transação do passo.
    signal idx         : natural range 0 to STOP_ONLY_IDX;
    -- A transação em curso falhou por NACK ou arbitragem perdida.
    signal failed      : std_logic;
    -- O comando em curso já recebeu NACK.
    signal nack_seen   : std_logic;
    -- O comando em curso perdeu a arbitragem.
    signal arb_seen    : std_logic;
    -- Contagem do intervalo com a linha livre.
    signal gap_cnt     : natural range 0 to GAP_CYCLES;
    -- Bytes lidos dos eixos, o primeiro nos bits baixos.
    signal raw         : std_logic_vector(47 downto 0);

    -- Entrada do núcleo: pulso que carrega um comando.
    signal cmd_valid : std_logic;
    -- Entrada do núcleo: comando com início.
    signal cmd_start : std_logic;
    -- Entrada do núcleo: comando com parada.
    signal cmd_stop  : std_logic;
    -- Entrada do núcleo: comando de leitura de um byte.
    signal cmd_read  : std_logic;
    -- Entrada do núcleo: comando de envio de um byte.
    signal cmd_write : std_logic;
    -- Entrada do núcleo: resposta NACK ao byte lido.
    signal cmd_nack  : std_logic;
    -- Entrada do núcleo: byte a enviar.
    signal cmd_tx    : std_logic_vector(7 downto 0);
    -- Divisor do clock do núcleo.
    signal divider   : std_logic_vector(15 downto 0);

    -- Saída do núcleo: comando em execução.
    signal core_busy     : std_logic;
    -- Saída do núcleo: fim de comando.
    signal core_done     : std_logic;
    -- Saída do núcleo: NACK no byte enviado.
    signal core_nack     : std_logic;
    -- Saída do núcleo: arbitragem perdida.
    signal core_arb_lost : std_logic;
    -- Saída do núcleo: último byte recebido.
    signal core_rx       : std_logic_vector(7 downto 0);
    -- SCL e SDA sincronizados, SCL no bit 0.
    signal bus_sync      : std_logic_vector(1 downto 0);
    -- INT1 e INT2 sincronizados, INT1 no bit 0.
    signal int_sync      : std_logic_vector(1 downto 0);

    -- Eixo X.
    signal axis_x      : std_logic_vector(15 downto 0);
    -- Eixo Y.
    signal axis_y      : std_logic_vector(15 downto 0);
    -- Eixo Z.
    signal axis_z      : std_logic_vector(15 downto 0);
    -- Último DEVID lido.
    signal devid       : std_logic_vector(7 downto 0);
    -- Varredura habilitada.
    signal enable      : std_logic;
    -- Habilitação da interrupção de amostra.
    signal irq_enable  : std_logic;
    -- Escala do acelerômetro.
    signal range_sel   : std_logic_vector(1 downto 0);
    -- Resolução plena.
    signal full_res    : std_logic;
    -- Disparo da leitura pelo pino de interrupção em vez do tempo.
    signal use_int     : std_logic;
    -- Pino que leva o dado pronto: '0' INT1, '1' INT2.
    signal int_pin     : std_logic;
    -- Código de taxa de BW_RATE.
    signal rate        : std_logic_vector(3 downto 0);
    -- Intervalo entre amostras, em ciclos.
    signal period      : unsigned(23 downto 0);
    -- Contagem do intervalo entre amostras.
    signal timer       : unsigned(23 downto 0);
    -- Intervalo de tempo cumprido, à espera de uma leitura.
    signal pending     : std_logic;
    -- A configuração precisa ser refeita.
    signal reconfig    : std_logic;
    -- A configuração terminou.
    signal configured  : std_logic;
    -- Marca persistente de amostra nova.
    signal sample_flag : std_logic;
    -- Já houve uma amostra.
    signal valid       : std_logic;
    -- Marca persistente de NACK.
    signal st_nack     : std_logic;
    -- Marca persistente de arbitragem perdida.
    signal st_arb_lost : std_logic;

    -- Endereço do registrador do chip que o passo acessa.
    function step_register (s : natural) return std_logic_vector is
    begin

        case s is

            when 0 =>

                return REG_DEVID;

            when 1 =>

                return REG_BW_RATE;

            when 2 =>

                return REG_DATA_FORMAT;

            when 3 =>

                return REG_INT_MAP;

            when 4 =>

                return REG_INT_ENABLE;

            when 5 =>

                return REG_POWER_CTL;

            when others =>

                return REG_DATAX0;

        end case;

    end function step_register;

    -- Bytes que o passo lê, ou zero quando o passo é uma escrita.
    function step_reads (s : natural) return natural is
    begin

        if s = 0 then
            return DEVID_BYTES;
        elsif s = SAMPLE_STEP then
            return AXIS_BYTES;
        end if;

        return 0;

    end function step_reads;

    -- Índice do último comando da transação do passo.
    function last_index (s : natural) return natural is
    begin

        if step_reads(s) = 0 then
            return LAST_WRITE_IDX;
        end if;

        return FIRST_READ_IDX + step_reads(s) - 1;

    end function last_index;

begin

    o_adxl_cs_n <= '1';
    o_adxl_sdo  <= '1' when address_select_high else '0';
    o_irq       <= irq_enable and sample_flag;

    u_bus_sync : entity work.synchronizer
        generic map (
            stages     => 2,
            data_width => 2
        )
        port map (
            i_clk => i_clk,
            i_rst => i_rst,
            i_d   => i_adxl_sda & i_adxl_scl,
            o_d   => bus_sync
        );

    u_int_sync : entity work.synchronizer
        generic map (
            stages     => 2,
            data_width => 2
        )
        port map (
            i_clk => i_clk,
            i_rst => i_rst,
            i_d   => i_adxl_int2 & i_adxl_int1,
            o_d   => int_sync
        );

    u_core : entity work.i2c_core
        port map (
            i_clk        => i_clk,
            i_rst        => i_rst,
            i_enable     => enable,
            i_abort      => '0',
            i_divider    => divider,
            i_cmd_valid  => cmd_valid,
            i_cmd_start  => cmd_start,
            i_cmd_stop   => cmd_stop,
            i_cmd_read   => cmd_read,
            i_cmd_write  => cmd_write,
            i_cmd_nack   => cmd_nack,
            i_tx_data    => cmd_tx,
            i_scl        => bus_sync(0),
            i_sda        => bus_sync(1),
            o_busy       => core_busy,
            o_bus_active => open,
            o_done       => core_done,
            o_nack       => core_nack,
            o_arb_lost   => core_arb_lost,
            o_rx_data    => core_rx,
            o_scl_low    => o_adxl_scl_low,
            o_sda_low    => o_adxl_sda_low
        );

    p_sequencer : process (i_clk) is

        -- Valor da escrita de registrador do passo atual.
        variable value : std_logic_vector(7 downto 0);
        -- Verdadeiro no ciclo em que uma amostra nova fica pronta.
        variable sample_event : boolean;
        -- O comando que acabou teve NACK.
        variable nacked : boolean;
        -- O comando que acabou perdeu a arbitragem.
        variable lost   : boolean;
        -- O disparo da leitura está ativo.
        variable trigger : boolean;

    begin

        if rising_edge(i_clk) then
            cmd_valid    <= '0';
            sample_event := false;

            if i_rst = '1' then
                state       <= S_IDLE;
                step        <= 0;
                idx         <= 0;
                failed      <= '0';
                nack_seen   <= '0';
                arb_seen    <= '0';
                gap_cnt     <= 0;
                raw         <= (others => '0');
                cmd_start   <= '0';
                cmd_stop    <= '0';
                cmd_read    <= '0';
                cmd_write   <= '0';
                cmd_nack    <= '0';
                cmd_tx      <= (others => '0');
                axis_x      <= (others => '0');
                axis_y      <= (others => '0');
                axis_z      <= (others => '0');
                devid       <= (others => '0');
                enable      <= '0';
                irq_enable  <= '0';
                range_sel   <= "00";
                full_res    <= '0';
                use_int     <= '0';
                int_pin     <= '0';
                rate        <= "1010";
                period      <= to_unsigned(RESET_PERIOD, 24);
                divider     <= RESET_DIVIDER;
                timer       <= (others => '0');
                pending     <= '0';
                reconfig    <= '1';
                configured  <= '0';
                sample_flag <= '0';
                valid       <= '0';
                st_nack     <= '0';
                st_arb_lost <= '0';
            else
                -- Intervalo entre amostras.
                if enable = '1' and configured = '1' then
                    if timer >= period then
                        timer   <= (others => '0');
                        pending <= '1';
                    else
                        timer <= timer + 1;
                    end if;
                end if;

                trigger := (use_int = '0' and pending = '1')
                           or (use_int = '1' and int_pin = '0' and int_sync(0) = '1')
                           or (use_int = '1' and int_pin = '1' and int_sync(1) = '1');

                if enable = '0' and state /= S_IDLE then
                    -- Desligar o controlador abandona a transação, e o núcleo solta as linhas.
                    state  <= S_IDLE;
                    failed <= '0';
                end if;

                case state is

                    when S_IDLE =>

                        if enable = '1' then
                            if reconfig = '1' then
                                reconfig   <= '0';
                                configured <= '0';
                                step       <= 0;
                                idx        <= 0;
                                state      <= S_ISSUE;
                            elsif trigger then
                                pending <= '0';
                                step    <= SAMPLE_STEP;
                                idx     <= 0;
                                state   <= S_ISSUE;
                            end if;
                        end if;

                    when S_ISSUE =>

                        if core_busy = '0' then
                            value := (others => '0');

                            case step is

                                when 1 =>

                                    value := "0000" & rate;

                                when 2 =>

                                    value := "0000" & full_res & '0' & range_sel;

                                when 3 =>

                                    value := int_pin & "0000000";

                                when 4 =>

                                    value := INT_DATA_READY;

                                when 5 =>

                                    value := POWER_MEASURE;

                                when others =>

                                    null;

                            end case;

                            cmd_start <= '0';
                            cmd_stop  <= '0';
                            cmd_read  <= '0';
                            cmd_write <= '1';
                            cmd_nack  <= '0';
                            cmd_tx    <= (others => '0');

                            if idx = 0 then
                                cmd_start <= '1';
                                cmd_tx    <= ADDR_WRITE;
                            elsif idx = 1 then
                                cmd_tx <= step_register(step);
                            elsif idx = STOP_ONLY_IDX then
                                cmd_write <= '0';
                                cmd_stop  <= '1';
                            elsif step_reads(step) = 0 then
                                cmd_stop <= '1';
                                cmd_tx   <= value;
                            elsif idx = LAST_WRITE_IDX then
                                cmd_start <= '1';
                                cmd_tx    <= ADDR_READ;
                            else
                                cmd_write <= '0';
                                cmd_read  <= '1';

                                if idx = last_index(step) then
                                    cmd_stop <= '1';
                                    cmd_nack <= '1';
                                end if;
                            end if;

                            cmd_valid <= '1';
                            nack_seen <= '0';
                            arb_seen  <= '0';
                            state     <= S_WAIT;
                        end if;

                    when S_WAIT =>

                        nacked := nack_seen = '1' or core_nack = '1';
                        lost   := arb_seen = '1' or core_arb_lost = '1';

                        if core_nack = '1' then
                            nack_seen <= '1';
                        end if;

                        if core_arb_lost = '1' then
                            arb_seen <= '1';
                        end if;

                        if core_done = '1' then
                            if idx = STOP_ONLY_IDX or lost or (nacked and cmd_stop = '1') then
                                -- A linha já foi solta: fim da transação com falha.
                                failed  <= '1';
                                gap_cnt <= 1;
                                state   <= S_GAP;

                                if nacked then
                                    st_nack <= '1';
                                end if;

                                if lost then
                                    st_arb_lost <= '1';
                                end if;
                            elsif nacked then
                                -- O comando não levava parada: uma parada solta a linha.
                                st_nack <= '1';
                                failed  <= '1';
                                idx     <= STOP_ONLY_IDX;
                                state   <= S_ISSUE;
                            else
                                if cmd_read = '1' then
                                    raw <= core_rx & raw(47 downto 8);

                                    if step = 0 then
                                        devid <= core_rx;
                                    end if;
                                end if;

                                if idx = last_index(step) then
                                    gap_cnt <= 1;
                                    state   <= S_GAP;
                                else
                                    idx   <= idx + 1;
                                    state <= S_ISSUE;
                                end if;
                            end if;
                        end if;

                    when S_GAP =>

                        if gap_cnt /= GAP_CYCLES then
                            gap_cnt <= gap_cnt + 1;
                        elsif failed = '1' then
                            failed <= '0';
                            state  <= S_IDLE;
                        elsif step = SAMPLE_STEP then
                            axis_x       <= raw(15 downto 0);
                            axis_y       <= raw(31 downto 16);
                            axis_z       <= raw(47 downto 32);
                            sample_event := true;
                            valid        <= '1';
                            state        <= S_IDLE;
                        elsif step = LAST_CONFIG then
                            configured <= '1';
                            timer      <= (others => '0');
                            state      <= S_IDLE;
                        else
                            step  <= step + 1;
                            idx   <= 0;
                            state <= S_ISSUE;
                        end if;

                end case;

                if i_write = '1' then
                    case i_address is

                        when "011" =>

                            sample_flag <= sample_flag and not i_data_in(1);
                            st_nack     <= st_nack and not i_data_in(4);
                            st_arb_lost <= st_arb_lost and not i_data_in(5);

                        when "100" =>

                            enable     <= i_data_in(0);
                            irq_enable <= i_data_in(1);
                            range_sel  <= i_data_in(3 downto 2);
                            full_res   <= i_data_in(4);
                            use_int    <= i_data_in(5);
                            int_pin    <= i_data_in(6);
                            rate       <= i_data_in(11 downto 8);
                            reconfig   <= '1';

                        when "101" =>

                            period <= unsigned(i_data_in(23 downto 0));

                        when "111" =>

                            if unsigned(i_data_in(15 downto 0)) < MIN_DIVIDER then
                                divider <= std_logic_vector(to_unsigned(MIN_DIVIDER, 16));
                            else
                                divider <= i_data_in(15 downto 0);
                            end if;

                        when others =>

                            null;

                    end case;
                end if;

                -- Uma amostra nova tem prioridade sobre a limpeza.
                if sample_event then
                    sample_flag <= '1';
                end if;
            end if;
        end if;

    end process p_sequencer;

    p_readback : process (
                          i_address, axis_x, axis_y, axis_z, state, sample_flag, valid, configured, st_nack, st_arb_lost,
                          int_sync, enable, irq_enable, range_sel, full_res, use_int, int_pin, rate, period, devid,
                          divider
                         ) is

        -- Valor montado para o registrador selecionado.
        variable value : word_t;

    begin

        value := (others => '0');

        case i_address is

            when "000" =>

                value := std_logic_vector(resize(signed(axis_x), 32));

            when "001" =>

                value := std_logic_vector(resize(signed(axis_y), 32));

            when "010" =>

                value := std_logic_vector(resize(signed(axis_z), 32));

            when "011" =>

                value(0) := '1' when state /= S_IDLE else '0';
                value(1) := sample_flag;
                value(2) := valid;
                value(3) := configured;
                value(4) := st_nack;
                value(5) := st_arb_lost;
                value(6) := int_sync(0);
                value(7) := int_sync(1);

            when "100" =>

                value(0)           := enable;
                value(1)           := irq_enable;
                value(3 downto 2)  := range_sel;
                value(4)           := full_res;
                value(5)           := use_int;
                value(6)           := int_pin;
                value(11 downto 8) := rate;

            when "101" =>

                value(23 downto 0) := std_logic_vector(period);

            when "110" =>

                value(7 downto 0) := devid;

            when others =>

                value(15 downto 0) := divider;

        end case;

        o_data_out <= value;

    end process p_readback;

end architecture rtl;
