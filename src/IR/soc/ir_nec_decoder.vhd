-- =============================================================================
-- Decodificador do protocolo NEC de infravermelho
--
-- Consome os eventos do medidor de pulsos (largura de cada pulso e de cada
-- espaço) e reconhece o quadro NEC: pulso de 9 ms e espaço de 4,5 ms, 32 bits
-- (pulso de 562,5 us e espaço de 562,5 us para zero ou 1687,5 us para um, bit
-- menos significativo primeiro) e um pulso final de 562,5 us. O código de
-- repetição é o pulso de 9 ms, o espaço de 2,25 ms e o pulso final. Os quatro
-- bytes são endereço, endereço invertido (ou byte alto do endereço, no NEC
-- estendido), comando e comando invertido. O comando invertido precisa ser o
-- complemento do comando; o endereço invertido, quando não é o complemento do
-- endereço, só é aceito como byte alto com i_ext_en em '1'.
--
-- Cada largura é comparada com a faixa de n unidades de 562,5 us mais ou menos
-- tolerance_percent por cento. Um erro só é sinalizado depois de um pulso
-- inicial válido: ruído fora de um quadro é ignorado. Depois de um erro o
-- decodificador volta ao repouso, mas um pulso que casa com o inicial já
-- começa o quadro seguinte. Uma repetição sem quadro anterior é um erro.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.ir_consts.all;

entity ir_nec_decoder is
    generic (
        -- Frequência do clock em Hz (abaixo de 238 MHz).
        clk_freq_hz       : positive := 50000000;
        -- Tolerância das larguras, em por cento (de 0 a 30).
        tolerance_percent : natural  := 25
    );
    port (
        -- Clock do módulo.
        i_clk         : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst         : in    std_logic;
        -- Pulso de um ciclo com a medida de um nível que acabou.
        i_event       : in    std_logic;
        -- Tipo do nível medido: '1' pulso, '0' espaço.
        i_event_mark  : in    std_logic;
        -- Largura medida em ciclos.
        i_width       : in    std_logic_vector(31 downto 0);
        -- Pulso de um ciclo quando um nível passou do tempo máximo.
        i_timeout     : in    std_logic;
        -- Aceita o NEC estendido de 16 bits de endereço.
        i_ext_en      : in    std_logic;
        -- Pulso de um ciclo com um quadro (ou repetição) válido nas saídas.
        o_frame_valid : out   std_logic;
        -- Endereço do quadro (os 8 bits baixos só, no NEC de 8 bits).
        o_address     : out   std_logic_vector(15 downto 0);
        -- Comando do quadro.
        o_command     : out   std_logic_vector(7 downto 0);
        -- '1' quando o quadro é uma repetição do anterior.
        o_repeat      : out   std_logic;
        -- '1' quando o quadro usou o endereço estendido de 16 bits.
        o_extended    : out   std_logic;
        -- Pulso de um ciclo quando um quadro malformado é descartado.
        o_error       : out   std_logic
    );
end entity ir_nec_decoder;

architecture rtl of ir_nec_decoder is

    -- Estados do reconhecimento do quadro.
    type state_t is (S_IDLE, S_LEAD_SPACE, S_BIT_MARK, S_BIT_SPACE, S_STOP_MARK, S_REP_MARK);

    -- Unidade do NEC em ciclos.
    constant UNIT : natural := nec_unit_cycles(clk_freq_hz);

    -- Limite inferior da faixa de n unidades.
    function lo (n : positive) return unsigned is
    begin

        return to_unsigned(n * UNIT * (100 - tolerance_percent) / 100, 32);

    end function lo;

    -- Limite superior da faixa de n unidades.
    function hi (n : positive) return unsigned is
    begin

        return to_unsigned(n * UNIT * (100 + tolerance_percent) / 100, 32);

    end function hi;

    -- Diz se a largura está na faixa de n unidades.
    function in_range (w : unsigned(31 downto 0); n : positive) return boolean is
    begin

        return w >= lo(n) and w <= hi(n);

    end function in_range;

    -- Estado atual.
    signal state      : state_t := S_IDLE;
    -- Bits já recebidos do quadro.
    signal bit_cnt    : natural range 0 to 31 := 0;
    -- Registrador de deslocamento dos 32 bits, o primeiro bit na posição 0 ao fim.
    signal shift      : std_logic_vector(31 downto 0) := (others => '0');
    -- Há um quadro anterior para repetir.
    signal last_valid : std_logic := '0';
    -- Endereço do último quadro.
    signal last_addr  : std_logic_vector(15 downto 0) := (others => '0');
    -- Comando do último quadro.
    signal last_cmd   : std_logic_vector(7 downto 0) := (others => '0');
    -- Estendido do último quadro.
    signal last_ext   : std_logic := '0';

begin

    assert tolerance_percent <= 30
        report "ir_nec_decoder: tolerance_percent deve ser no máximo 30"
        severity failure;

    -- Máquina de estados do quadro NEC.
    p_fsm : process (i_clk) is
        -- Palavra de 32 bits do quadro recebido.
        variable w   : unsigned(31 downto 0);
        -- Indica que o quadro recebido é inválido.
        variable bad : boolean;
        -- Bit decodificado do pulso atual.
        variable b   : std_logic;
        -- Primeiro byte de endereço do quadro.
        variable a0  : std_logic_vector(7 downto 0);
        -- Segundo byte de endereço do quadro.
        variable a1  : std_logic_vector(7 downto 0);
        -- Byte de comando do quadro.
        variable c   : std_logic_vector(7 downto 0);
        -- Byte de comando invertido do quadro.
        variable ic  : std_logic_vector(7 downto 0);
    begin

        if rising_edge(i_clk) then
            o_frame_valid <= '0';
            o_error       <= '0';

            if i_rst = '1' then
                state      <= S_IDLE;
                bit_cnt    <= 0;
                shift      <= (others => '0');
                last_valid <= '0';
                last_addr  <= (others => '0');
                last_cmd   <= (others => '0');
                last_ext   <= '0';
                o_address  <= (others => '0');
                o_command  <= (others => '0');
                o_repeat   <= '0';
                o_extended <= '0';
            else
                w   := unsigned(i_width);
                bad := false;

                if i_timeout = '1' then
                    bad := state /= S_IDLE;
                elsif i_event = '1' then
                    case state is
                        when S_IDLE =>
                            if i_event_mark = '1' and in_range(w, 16) then
                                state <= S_LEAD_SPACE;
                            end if;

                        when S_LEAD_SPACE =>
                            if in_range(w, 8) then
                                state   <= S_BIT_MARK;
                                bit_cnt <= 0;
                            elsif in_range(w, 4) and last_valid = '1' then
                                state <= S_REP_MARK;
                            else
                                bad := true;
                            end if;

                        when S_BIT_MARK =>
                            if in_range(w, 1) then
                                state <= S_BIT_SPACE;
                            else
                                bad := true;
                            end if;

                        when S_BIT_SPACE =>
                            b := '0';

                            if in_range(w, 1) then
                                b := '0';
                            elsif in_range(w, 3) then
                                b := '1';
                            else
                                bad := true;
                            end if;

                            if not bad then
                                shift <= b & shift(31 downto 1);

                                if bit_cnt = 31 then
                                    state <= S_STOP_MARK;
                                else
                                    bit_cnt <= bit_cnt + 1;
                                    state   <= S_BIT_MARK;
                                end if;
                            end if;

                        when S_STOP_MARK =>
                            a0 := shift(7 downto 0);
                            a1 := shift(15 downto 8);
                            c  := shift(23 downto 16);
                            ic := shift(31 downto 24);

                            if not in_range(w, 1) or (c xor ic) /= x"FF" then
                                bad := true;
                            elsif a1 = not a0 then
                                o_address     <= x"00" & a0;
                                o_extended    <= '0';
                                last_addr     <= x"00" & a0;
                                last_ext      <= '0';
                            elsif i_ext_en = '1' then
                                o_address     <= a1 & a0;
                                o_extended    <= '1';
                                last_addr     <= a1 & a0;
                                last_ext      <= '1';
                            else
                                bad := true;
                            end if;

                            if not bad then
                                o_command     <= c;
                                o_repeat      <= '0';
                                o_frame_valid <= '1';
                                last_cmd      <= c;
                                last_valid    <= '1';
                                state         <= S_IDLE;
                            end if;

                        when S_REP_MARK =>
                            if in_range(w, 1) then
                                o_address     <= last_addr;
                                o_command     <= last_cmd;
                                o_extended    <= last_ext;
                                o_repeat      <= '1';
                                o_frame_valid <= '1';
                                state         <= S_IDLE;
                            else
                                bad := true;
                            end if;
                    end case;
                end if;

                if bad then
                    o_error <= '1';

                    if i_event = '1' and i_event_mark = '1' and in_range(w, 16) then
                        state <= S_LEAD_SPACE;
                    else
                        state <= S_IDLE;
                    end if;
                end if;
            end if;
        end if;

    end process p_fsm;

end architecture rtl;
