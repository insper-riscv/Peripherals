-- ==========================================================================
-- Controlador do acelerômetro ADXL345 por SPI (DE0-Nano e DE10-Lite)
-- ==========================================================================
-- O ADXL345 é um acelerômetro de três eixos com resolução de até 13 bits e
-- interface SPI de três ou quatro fios ou I2C. Este controlador usa o SPI
-- (modo 3, bit mais significativo primeiro, 8 bits por palavra) sobre o
-- mestre genérico: ao ser habilitado, configura o chip e depois lê, em
-- intervalos fixos ou a cada aviso de dado pronto em INT1, os seis bytes dos
-- eixos X, Y e Z. Cada eixo vira um registrador de 32 bits com o valor de 16
-- bits em complemento de dois estendido em sinal. O acesso por I2C é por
-- software, com o mestre I2C do repositório, e não passa por aqui.
--
-- Sequência de configuração, depois de ENABLE ou de uma escrita em CONTROL:
--   1. lê DEVID (0x00), que fica no registrador DEVID;
--   2. BW_RATE (0x2C) recebe o código de taxa de RATE;
--   3. DATA_FORMAT (0x31) recebe SPI (um com três fios), FULL_RES e RANGE;
--   4. INT_ENABLE (0x2E) recebe 0x80 (dado pronto, em INT1 por padrão);
--   5. POWER_CTL (0x2D) recebe 0x08 (medição).
-- A leitura periódica é a leitura em rajada de DATAX0 (0x32) a DATAZ1 (0x37),
-- com o comando 0xF2 (leitura, rajada e endereço 0x32). Com o fio de dados
-- compartilhado (três fios) o mestre solta MOSI durante os seis bytes lidos.
--
-- Os endereços e valores acima vêm da folha de dados do ADXL345, que não está
-- no repositório (os manuais das placas só dão a interface), então são
-- suposições a conferir: DEVID vale 0xE5 segundo a folha de dados, e o
-- controlador não decide nada pelo valor lido.
--
-- Mapa de registradores, em endereços de palavra:
--
--   0 X        R      eixo X, 16 bits em complemento de dois estendidos
--   1 Y        R      eixo Y
--   2 Z        R      eixo Z
--   3 STATUS   R/W1C  bit 0 BUSY, 1 SAMPLE (amostra nova, limpa por escrita
--                     de 1), 2 VALID (já houve uma amostra), 3 CONFIGURED
--   4 CONTROL  R/W    bit 0 ENABLE, 1 IRQ_ENABLE, 3:2 RANGE (0 a 3 para
--                     2, 4, 8 e 16 g), 4 FULL_RES, 5 USE_INT1, 11:8 RATE
--   5 PERIOD   R/W    bits 23:0, ciclos entre amostras sem USE_INT1
--   6 DEVID    R      bits 7:0, último DEVID lido
--   7 DIVIDER  R/W    bits 15:0, SCLK = clock / (2 * (DIVIDER + 1))
--
-- Uma escrita em CONTROL repete a configuração na próxima oportunidade. A
-- saída o_irq é de nível e vale SAMPLE com IRQ_ENABLE.
-- ==========================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.config_pkg.all;

entity adxl345 is
    generic (
        -- Frequência do clock do módulo, em hertz.
        clock_hz   : positive := 50_000_000;
        -- Frequência de SCLK depois do reset, em hertz (o chip aceita até 5 MHz).
        sclk_hz    : positive := 1_000_000;
        -- Amostras por segundo depois do reset, quando o intervalo é por tempo.
        sample_hz  : positive := 100;
        -- Intervalo mínimo com a seleção de chip em nível alto, em nanossegundos.
        cs_high_ns : positive := 300;
        -- Verdadeiro com o fio de dados compartilhado (SPI de três fios).
        three_wire : boolean := true
    );
    port (
        -- Clock do módulo.
        i_clk         : in    std_logic;
        -- Reset síncrono, ativo em nível alto.
        i_rst         : in    std_logic;
        -- Dado de escrita vindo do processador.
        i_data_in     : in    word_t;
        -- Endereço de palavra do registrador, entre zero e sete.
        i_address     : in    std_logic_vector(2 downto 0);
        -- Pulso de escrita do processador.
        i_write       : in    std_logic;
        -- Dado de leitura devolvido ao processador.
        o_data_out    : out   word_t;
        -- Requisição de interrupção de nível.
        o_irq         : out   std_logic;
        -- Seleção de chip do acelerômetro, ativa em nível baixo.
        o_adxl_cs_n   : out   std_logic;
        -- Relógio serial do acelerômetro.
        o_adxl_sclk   : out   std_logic;
        -- Dado do controlador para o acelerômetro (SDI, ou SDIO nos três fios).
        o_adxl_mosi   : out   std_logic;
        -- Habilitação do driver de MOSI, em 0 quando o chip fala.
        o_adxl_mosi_oe : out  std_logic;
        -- Dado do acelerômetro para o controlador (SDO, ou SDIO nos três fios).
        i_adxl_miso   : in    std_logic;
        -- Interrupção 1 do acelerômetro (dado pronto), ativa em nível alto.
        i_adxl_int1   : in    std_logic
    );
end entity adxl345;

architecture rtl of adxl345 is

    -- Divisor do reset, que mantém SCLK em sclk_hz ou abaixo.
    constant RESET_DIVIDER : natural := (clock_hz + 2 * sclk_hz - 1) / (2 * sclk_hz) - 1;
    -- Intervalo entre amostras depois do reset, em ciclos.
    constant RESET_PERIOD  : natural := clock_hz / sample_hz;
    -- Ciclos com a seleção de chip em nível alto entre transações.
    constant CS_HIGH_CYCLES : positive := (cs_high_ns * (clock_hz / 1000) + 999_999) / 1_000_000;

    -- Comando de leitura de DEVID (leitura, endereço 0x00).
    constant CMD_DEVID       : std_logic_vector(7 downto 0) := x"80";
    -- Comando de escrita de BW_RATE.
    constant CMD_BW_RATE     : std_logic_vector(7 downto 0) := x"2C";
    -- Comando de escrita de DATA_FORMAT.
    constant CMD_DATA_FORMAT : std_logic_vector(7 downto 0) := x"31";
    -- Comando de escrita de INT_ENABLE.
    constant CMD_INT_ENABLE  : std_logic_vector(7 downto 0) := x"2E";
    -- Comando de escrita de POWER_CTL.
    constant CMD_POWER_CTL   : std_logic_vector(7 downto 0) := x"2D";
    -- Comando de leitura em rajada a partir de DATAX0.
    constant CMD_BURST_DATA  : std_logic_vector(7 downto 0) := x"F2";
    -- Valor de INT_ENABLE: dado pronto.
    constant INT_DATA_READY  : std_logic_vector(7 downto 0) := x"80";
    -- Valor de POWER_CTL: medição.
    constant POWER_MEASURE   : std_logic_vector(7 downto 0) := x"08";

    -- Último passo da configuração.
    constant LAST_CONFIG_STEP : natural := 4;
    -- Bit SPI de DATA_FORMAT: um com o fio de dados compartilhado.
    function spi_bit return std_logic is
    begin

        if three_wire then
            return '1';
        end if;

        return '0';

    end function spi_bit;

    -- Passo da leitura dos eixos.
    constant SAMPLE_STEP      : natural := 5;
    -- Largura da palavra SPI, em bits, na codificação do mestre.
    constant WORD_BITS        : std_logic_vector(5 downto 0) := "001000";

    -- Estados da transação.
    type state_t is (S_IDLE, S_LOAD, S_CMD, S_CMD_WAIT, S_DATA, S_DATA_WAIT, S_END);

    -- Estado da transação.
    signal state      : state_t;
    -- Passo da sequência: configuração de 0 a 4 e leitura dos eixos em 5.
    signal step       : natural range 0 to SAMPLE_STEP;
    -- Byte de comando da transação.
    signal cmd        : std_logic_vector(7 downto 0);
    -- Byte escrito, nas transações de escrita.
    signal wdata      : std_logic_vector(7 downto 0);
    -- Verdadeiro nas transações de escrita.
    signal is_write   : std_logic;
    -- Bytes a ler nas transações de leitura.
    signal read_count : natural range 0 to 6;
    -- Posição do byte de dados em andamento.
    signal byte_idx   : natural range 0 to 6;
    -- Contagem do intervalo de seleção de chip em nível alto.
    signal gap_cnt    : natural range 0 to CS_HIGH_CYCLES;
    -- Bytes lidos dos eixos, o primeiro nos bits baixos.
    signal raw        : std_logic_vector(47 downto 0);
    -- Linha de seleção de chip.
    signal cs_n       : std_logic;

    -- Entrada do mestre SPI: pulso de início.
    signal spi_start : std_logic;
    -- Entrada do mestre SPI: byte transmitido.
    signal spi_tx    : std_logic_vector(7 downto 0);
    -- Entrada do mestre SPI: em 0 o mestre solta MOSI.
    signal spi_drive : std_logic;
    -- Saída do mestre SPI: fim de palavra.
    signal spi_done  : std_logic;
    -- Saída do mestre SPI: byte recebido.
    signal spi_rx    : std_logic_vector(7 downto 0);
    -- MISO sincronizada com o clock.
    signal miso_sync : std_logic_vector(0 downto 0);
    -- INT1 sincronizada com o clock.
    signal int1_sync : std_logic_vector(0 downto 0);

    -- Eixos X, Y e Z.
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
    -- Disparo da leitura pelo INT1 em vez do tempo.
    signal use_int1    : std_logic;
    -- Código de taxa de BW_RATE.
    signal rate        : std_logic_vector(3 downto 0);
    -- Intervalo entre amostras, em ciclos.
    signal period      : unsigned(23 downto 0);
    -- Divisor de clock do SCLK.
    signal divider     : std_logic_vector(15 downto 0);
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

begin

    o_adxl_cs_n <= cs_n;
    o_irq       <= irq_enable and sample_flag;

    u_miso_sync : entity work.synchronizer
        generic map (
            stages     => 2,
            data_width => 1
        )
        port map (
            i_clk => i_clk,
            i_rst => i_rst,
            i_d(0) => i_adxl_miso,
            o_d   => miso_sync
        );

    u_int1_sync : entity work.synchronizer
        generic map (
            stages     => 2,
            data_width => 1
        )
        port map (
            i_clk => i_clk,
            i_rst => i_rst,
            i_d(0) => i_adxl_int1,
            o_d   => int1_sync
        );

    u_master : entity work.spi_master
        generic map (
            divider_width => 16,
            word_width    => 8
        )
        port map (
            i_clk       => i_clk,
            i_rst       => i_rst,
            i_cpol      => '1',
            i_cpha      => '1',
            i_lsb_first => '0',
            i_word_bits => WORD_BITS,
            i_divider   => divider,
            i_tx_drive  => spi_drive,
            i_start     => spi_start,
            i_tx_data   => spi_tx,
            o_busy      => open,
            o_done      => spi_done,
            o_rx_data   => spi_rx,
            o_sclk      => o_adxl_sclk,
            o_mosi      => o_adxl_mosi,
            o_mosi_oe   => o_adxl_mosi_oe,
            i_miso      => miso_sync(0)
        );

    p_sequencer : process (i_clk) is

        -- Valor de DATA_FORMAT da configuração atual.
        variable data_format : std_logic_vector(7 downto 0);
        -- Verdadeiro no ciclo em que uma amostra nova fica pronta.
        variable sample_event : boolean;

    begin

        if rising_edge(i_clk) then
            spi_start    <= '0';
            sample_event := false;

            if i_rst = '1' then
                state       <= S_IDLE;
                step        <= 0;
                cmd         <= (others => '0');
                wdata       <= (others => '0');
                is_write    <= '0';
                read_count  <= 0;
                byte_idx    <= 0;
                gap_cnt     <= 0;
                raw         <= (others => '0');
                cs_n        <= '1';
                spi_tx      <= (others => '0');
                spi_drive   <= '1';
                axis_x      <= (others => '0');
                axis_y      <= (others => '0');
                axis_z      <= (others => '0');
                devid       <= (others => '0');
                enable      <= '0';
                irq_enable  <= '0';
                range_sel   <= "00";
                full_res    <= '0';
                use_int1    <= '0';
                rate        <= "1010";
                period      <= to_unsigned(RESET_PERIOD, 24);
                divider     <= std_logic_vector(to_unsigned(RESET_DIVIDER, 16));
                timer       <= (others => '0');
                pending     <= '0';
                reconfig    <= '1';
                configured  <= '0';
                sample_flag <= '0';
                valid       <= '0';
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

                case state is

                    when S_IDLE =>

                        if enable = '1' then
                            if reconfig = '1' then
                                reconfig   <= '0';
                                configured <= '0';
                                step       <= 0;
                                state      <= S_LOAD;
                            elsif (use_int1 = '0' and pending = '1') or (use_int1 = '1' and int1_sync(0) = '1') then
                                pending <= '0';
                                step    <= SAMPLE_STEP;
                                state   <= S_LOAD;
                            end if;
                        end if;

                    when S_LOAD =>

                        data_format := '0' & spi_bit & "00" & full_res & '0' & range_sel;
                        is_write    <= '1';
                        read_count  <= 0;
                        byte_idx    <= 0;

                        case step is

                            when 0 =>

                                cmd        <= CMD_DEVID;
                                is_write   <= '0';
                                read_count <= 1;

                            when 1 =>

                                cmd   <= CMD_BW_RATE;
                                wdata <= "0000" & rate;

                            when 2 =>

                                cmd   <= CMD_DATA_FORMAT;
                                wdata <= data_format;

                            when 3 =>

                                cmd   <= CMD_INT_ENABLE;
                                wdata <= INT_DATA_READY;

                            when 4 =>

                                cmd   <= CMD_POWER_CTL;
                                wdata <= POWER_MEASURE;

                            when 5 =>

                                cmd        <= CMD_BURST_DATA;
                                is_write   <= '0';
                                read_count <= 6;

                        end case;

                        cs_n  <= '0';
                        state <= S_CMD;

                    when S_CMD =>

                        spi_start <= '1';
                        spi_tx    <= cmd;
                        spi_drive <= '1';
                        state     <= S_CMD_WAIT;

                    when S_CMD_WAIT =>

                        if spi_done = '1' then
                            state <= S_DATA;
                        end if;

                    when S_DATA =>

                        spi_start <= '1';
                        spi_tx    <= wdata when is_write = '1' else (others => '0');
                        spi_drive <= is_write;
                        state     <= S_DATA_WAIT;

                    when S_DATA_WAIT =>

                        if spi_done = '1' then
                            if is_write = '0' then
                                raw <= spi_rx & raw(47 downto 8);

                                if step = 0 then
                                    devid <= spi_rx;
                                end if;
                            end if;

                            if is_write = '1' or byte_idx + 1 = read_count then
                                cs_n    <= '1';
                                gap_cnt <= 1;
                                state   <= S_END;
                            else
                                byte_idx <= byte_idx + 1;
                                state    <= S_DATA;
                            end if;
                        end if;

                    when S_END =>

                        if gap_cnt /= CS_HIGH_CYCLES then
                            gap_cnt <= gap_cnt + 1;
                        elsif step = SAMPLE_STEP then
                            axis_x      <= raw(15 downto 0);
                            axis_y      <= raw(31 downto 16);
                            axis_z      <= raw(47 downto 32);
                            sample_event := true;
                            valid        <= '1';
                            state       <= S_IDLE;
                        elsif step = LAST_CONFIG_STEP then
                            configured <= '1';
                            timer      <= (others => '0');
                            state      <= S_IDLE;
                        else
                            step  <= step + 1;
                            state <= S_LOAD;
                        end if;

                end case;

                if i_write = '1' then
                    case i_address is

                        when "011" =>

                            sample_flag <= sample_flag and not i_data_in(1);

                        when "100" =>

                            enable     <= i_data_in(0);
                            irq_enable <= i_data_in(1);
                            range_sel  <= i_data_in(3 downto 2);
                            full_res   <= i_data_in(4);
                            use_int1   <= i_data_in(5);
                            rate       <= i_data_in(11 downto 8);
                            reconfig   <= '1';

                        when "101" =>

                            period <= unsigned(i_data_in(23 downto 0));

                        when "111" =>

                            divider <= i_data_in(15 downto 0);

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
                          i_address, axis_x, axis_y, axis_z, state, sample_flag, valid, configured, enable, irq_enable,
                          range_sel, full_res, use_int1, rate, period, devid, divider
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

            when "100" =>

                value(0)            := enable;
                value(1)            := irq_enable;
                value(3 downto 2)   := range_sel;
                value(4)            := full_res;
                value(5)            := use_int1;
                value(11 downto 8)  := rate;

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
