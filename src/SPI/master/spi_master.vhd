-- ==========================================================================
-- Mestre SPI de uma palavra, nos quatro modos
-- ==========================================================================
-- Troca uma palavra de 1 a word_width bits por pedido de início. O modo
-- (CPOL e CPHA), a largura da palavra, a ordem dos bits (mais ou menos
-- significativo primeiro) e o divisor são capturados no início de cada
-- palavra. O período de SCLK vale 2 * (divisor + 1) ciclos de i_clk, e a
-- palavra tem uma meia-espera em repouso, n períodos completos e termina na
-- última borda de trailing, que devolve SCLK ao nível de repouso (CPOL).
--
-- Bordas, com "leading" a que sai do repouso e "trailing" a que volta a ele:
--   CPHA 0  o primeiro bit já está em MOSI antes da primeira borda leading,
--           e o próximo bit sai a cada borda trailing.
--   CPHA 1  o primeiro bit já está em MOSI antes da primeira borda leading,
--           e o próximo bit sai a cada borda leading depois da primeira.
-- Nos dois casos a entrada MISO é amostrada na borda trailing, o instante
-- mais tardio do bit antes da mudança seguinte do escravo, e já deve estar
-- sincronizada com i_clk. Com a amostra tardia o divisor mínimo é 1
-- (SCLK = i_clk / 4). Em repouso SCLK acompanha i_cpol, então o modo só deve
-- mudar com a seleção de chip desativada. MOSI fica em nível alto fora da
-- palavra. Com i_tx_drive em 0 a palavra só escuta, e o_mosi_oe cai durante
-- ela e continua em 0 até a palavra seguinte (barramento de três fios).
-- Ao fim da palavra o pulso o_done dura um ciclo e o_rx_data guarda a palavra
-- recebida, alinhada à direita, até a próxima.
-- ==========================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spi_master is
    generic (
        -- Largura do divisor de clock, em bits.
        divider_width : positive := 16;
        -- Largura máxima da palavra, em bits.
        word_width    : positive range 1 to 32 := 32
    );
    port (
        -- Clock do módulo.
        i_clk       : in    std_logic;
        -- Reset síncrono, ativo em nível alto.
        i_rst       : in    std_logic;
        -- Nível de repouso de SCLK.
        i_cpol      : in    std_logic;
        -- Fase: em 1 o escravo muda o dado na borda leading e o mestre amostra na trailing.
        i_cpha      : in    std_logic;
        -- Em 1 o bit menos significativo vai primeiro.
        i_lsb_first : in    std_logic;
        -- Quantidade de bits da palavra, de 1 a word_width (fora da faixa vira o extremo mais próximo).
        i_word_bits : in    std_logic_vector(5 downto 0);
        -- Metade do período de SCLK menos um, em ciclos de i_clk.
        i_divider   : in    std_logic_vector(divider_width - 1 downto 0);
        -- Em 0 a palavra só escuta (o mestre solta MOSI).
        i_tx_drive  : in    std_logic;
        -- Pedido de início de uma palavra, aceito apenas com o_busy em '0'.
        i_start     : in    std_logic;
        -- Palavra a transmitir, alinhada à direita, capturada junto com o pedido de início.
        i_tx_data   : in    std_logic_vector(word_width - 1 downto 0);
        -- Indica uma palavra em andamento.
        o_busy      : out   std_logic;
        -- Pulso de um ciclo no fim da palavra.
        o_done      : out   std_logic;
        -- Palavra recebida, alinhada à direita, válida a partir de o_done.
        o_rx_data   : out   std_logic_vector(word_width - 1 downto 0);
        -- Relógio serial.
        o_sclk      : out   std_logic;
        -- Dado serial do mestre para o escravo.
        o_mosi      : out   std_logic;
        -- Habilitação do driver de MOSI, em 0 quando o mestre solta a linha.
        o_mosi_oe   : out   std_logic;
        -- Dado serial do escravo, já sincronizado com i_clk.
        i_miso      : in    std_logic
    );
end entity spi_master;

architecture rtl of spi_master is

    -- Palavra na largura máxima.
    subtype word_t is std_logic_vector(word_width - 1 downto 0);

    -- Inverte a ordem dos bits de uma palavra inteira.
    function reverse (value : word_t) return word_t is

        -- Resultado da inversão.
        variable result : word_t;

    begin

        for i in 0 to word_width - 1 loop
            result(i) := value(word_width - 1 - i);
        end loop;

        return result;

    end function reverse;

    -- Desloca a palavra à direita de modo que os n bits mais recentes fiquem nos bits baixos.
    function align (value : word_t; bits : natural) return word_t is
    begin

        return word_t(shift_right(unsigned(value), word_width - bits));

    end function align;

    -- Máscara com os n bits baixos em 1.
    function low_mask (bits : natural) return word_t is
    begin

        return align((others => '1'), bits);

    end function low_mask;

    -- Ordem de saída: o bit 0 do resultado é o primeiro a ser transmitido.
    function to_order (value : word_t; bits : natural; lsb_first : std_logic) return word_t is
    begin

        if lsb_first = '1' then
            return value and low_mask(bits);
        end if;

        return align(reverse(value), bits);

    end function to_order;

    -- Palavra alinhada à direita a partir dos bits na ordem de chegada (o primeiro a chegar no bit 0).
    function from_order (arrived : word_t; bits : natural; lsb_first : std_logic) return word_t is

        -- Bits da chegada já alinhados à direita.
        variable aligned : word_t;

    begin

        aligned := align(arrived, bits);

        if lsb_first = '1' then
            return aligned;
        end if;

        return align(reverse(aligned), bits);

    end function from_order;

    -- Limita a quantidade de bits pedida à faixa de 1 a word_width.
    function clamp_bits (value : std_logic_vector(5 downto 0)) return natural is

        -- Valor numérico do pedido.
        variable requested : natural;

    begin

        requested := to_integer(unsigned(value));

        if requested < 1 then
            return 1;
        elsif requested > word_width then
            return word_width;
        end if;

        return requested;

    end function clamp_bits;

    -- Indica uma palavra em andamento.
    signal busy      : std_logic;
    -- Pulso de fim de palavra.
    signal done      : std_logic;
    -- Nível atual de SCLK.
    signal sclk      : std_logic;
    -- Bits a transmitir, o próximo em tx_shift(0).
    signal tx_shift  : word_t;
    -- Bits recebidos na ordem de chegada, o mais recente no bit mais alto.
    signal rx_shift  : word_t;
    -- Palavra recebida da última transferência.
    signal rx_data   : word_t;
    -- Bits que ainda faltam amostrar na palavra.
    signal bits_left : natural range 0 to word_width;
    -- Quantidade de bits da palavra em andamento.
    signal word_bits : natural range 1 to word_width;
    -- Ciclos já contados na metade atual do período de SCLK.
    signal tick_cnt  : unsigned(divider_width - 1 downto 0);
    -- Divisor capturado no início da palavra.
    signal divider   : unsigned(divider_width - 1 downto 0);
    -- Nível de repouso de SCLK capturado no início da palavra.
    signal cpol      : std_logic;
    -- Fase capturada no início da palavra.
    signal cpha      : std_logic;
    -- Ordem dos bits capturada no início da palavra.
    signal lsb_first : std_logic;
    -- Em 0 o mestre solta MOSI (palavra de escuta).
    signal drive     : std_logic;

begin

    o_busy    <= busy;
    o_done    <= done;
    o_rx_data <= rx_data;
    o_sclk    <= sclk;
    o_mosi    <= tx_shift(0);
    o_mosi_oe <= drive;

    p_phy : process (i_clk) is

        -- Palavra recebida com o bit desta amostra.
        variable arrived : word_t;

    begin

        if rising_edge(i_clk) then
            done <= '0';

            if i_rst = '1' then
                busy      <= '0';
                sclk      <= i_cpol;
                tx_shift  <= (others => '1');
                rx_shift  <= (others => '0');
                rx_data   <= (others => '0');
                bits_left <= 0;
                word_bits <= 1;
                tick_cnt  <= (others => '0');
                divider   <= (others => '0');
                cpol      <= '0';
                cpha      <= '0';
                lsb_first <= '0';
                drive     <= '1';
            elsif busy = '0' then
                sclk     <= i_cpol;
                tx_shift <= (others => '1');

                if i_start = '1' then
                    busy      <= '1';
                    word_bits <= clamp_bits(i_word_bits);
                    bits_left <= clamp_bits(i_word_bits);
                    tx_shift  <= to_order(i_tx_data, clamp_bits(i_word_bits), i_lsb_first)
                                 or not low_mask(clamp_bits(i_word_bits));
                    tick_cnt  <= (others => '0');
                    divider   <= unsigned(i_divider);
                    cpol      <= i_cpol;
                    cpha      <= i_cpha;
                    lsb_first <= i_lsb_first;
                    drive     <= i_tx_drive;
                end if;
            elsif tick_cnt /= divider then
                tick_cnt <= tick_cnt + 1;
            else
                tick_cnt <= (others => '0');
                sclk     <= not sclk;

                if sclk = cpol then
                    -- Borda leading: com CPHA 1 o próximo bit sai, exceto antes do primeiro.
                    if cpha = '1' and bits_left /= word_bits then
                        tx_shift <= '1' & tx_shift(word_width - 1 downto 1);
                    end if;
                else
                    -- Borda trailing: amostra MISO e, com CPHA 0, apresenta o próximo bit.
                    arrived   := i_miso & rx_shift(word_width - 1 downto 1);
                    rx_shift  <= arrived;
                    bits_left <= bits_left - 1;

                    if cpha = '0' then
                        tx_shift <= '1' & tx_shift(word_width - 1 downto 1);
                    end if;

                    if bits_left = 1 then
                        busy     <= '0';
                        done     <= '1';
                        rx_data  <= from_order(arrived, word_bits, lsb_first);
                    end if;
                end if;
            end if;
        end if;

    end process p_phy;

end architecture rtl;
