-- =============================================================================
-- Codificador TMDS de um canal (8 bits para 10 bits)
--
-- Converte um byte de pixel num símbolo de 10 bits que mantém poucas transições
-- e a disparidade de corrente contínua limitada, como manda o DVI 1.0. Com
-- i_de = '1' o byte passa pelas duas etapas do algoritmo:
--   1. minimização de transições: o byte vira nove bits por XOR ou por XNOR em
--      cadeia, conforme o número de bits em 1 do byte;
--   2. balanceamento: os oito bits baixos saem como estão ou invertidos, e o
--      bit 9 diz se houve inversão, de modo que a disparidade acumulada
--      (running disparity) tenda a zero.
-- Com i_de = '0' (período de apagamento) o símbolo é um dos quatro de controle,
-- escolhido por i_c1 e i_c0, e a disparidade acumulada volta a zero.
--
-- A saída é registrada em i_clk, uma latência de um ciclo. O reset síncrono
-- coloca na saída o símbolo de controle 00 e zera a disparidade.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.tmds_consts.all;

entity tmds_encoder is
    port (
        -- Clock de pixel.
        i_clk : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst : in    std_logic;
        -- Habilitação de dados: '1' codifica i_d, '0' envia um símbolo de controle.
        i_de  : in    std_logic;
        -- Bit de controle C0 do período de apagamento.
        i_c0  : in    std_logic;
        -- Bit de controle C1 do período de apagamento.
        i_c1  : in    std_logic;
        -- Byte de pixel do canal.
        i_d   : in    std_logic_vector(PIXEL_BITS - 1 downto 0);
        -- Símbolo TMDS, registrado, bit 0 transmitido primeiro.
        o_q   : out   std_logic_vector(TOKEN_BITS - 1 downto 0)
    );
end entity tmds_encoder;

architecture rtl of tmds_encoder is

    -- Disparidade acumulada: bits em 1 menos bits em 0 já enviados desde o último apagamento.
    signal disparity : integer range -31 to 31;
    -- Símbolo registrado.
    signal token     : std_logic_vector(TOKEN_BITS - 1 downto 0);

begin

    o_q <= token;

    p_encode : process (i_clk) is

        -- Nove bits da etapa de minimização de transições.
        variable q_m    : std_logic_vector(PIXEL_BITS downto 0);
        -- Diferença entre bits em 1 e em 0 dos oito bits baixos de q_m.
        variable diff   : integer range -8 to 8;
        -- Símbolo de dados em construção.
        variable q_out  : std_logic_vector(TOKEN_BITS - 1 downto 0);
        -- Disparidade seguinte em construção.
        variable cnt_nx : integer range -31 to 31;
        -- Contagem de bits em 1 do byte de entrada.
        variable n1d    : natural range 0 to PIXEL_BITS;

    begin

        if rising_edge(i_clk) then
            if i_rst = '1' then
                token     <= TOKEN_CTRL_00;
                disparity <= 0;
            elsif i_de = '0' then
                disparity <= 0;

                case std_logic_vector'(i_c1 & i_c0) is

                    when "00" =>

                        token <= TOKEN_CTRL_00;

                    when "01" =>

                        token <= TOKEN_CTRL_01;

                    when "10" =>

                        token <= TOKEN_CTRL_10;

                    when others =>

                        token <= TOKEN_CTRL_11;

                end case;
            else
                n1d    := count_ones(i_d);
                q_m(0) := i_d(0);

                -- Etapa 1: XNOR em cadeia com mais bits em 1 que em 0 (ou empate com bit 0 em 0), XOR nos demais.
                if n1d > PIXEL_BITS / 2 or (n1d = PIXEL_BITS / 2 and i_d(0) = '0') then
                    for i in 1 to PIXEL_BITS - 1 loop
                        q_m(i) := q_m(i - 1) xnor i_d(i);
                    end loop;

                    q_m(PIXEL_BITS) := '0';
                else
                    for i in 1 to PIXEL_BITS - 1 loop
                        q_m(i) := q_m(i - 1) xor i_d(i);
                    end loop;

                    q_m(PIXEL_BITS) := '1';
                end if;

                diff := 2 * count_ones(q_m(PIXEL_BITS - 1 downto 0)) - PIXEL_BITS;

                -- Etapa 2: balanceamento pela disparidade acumulada.
                if disparity = 0 or diff = 0 then
                    q_out(9) := not q_m(PIXEL_BITS);
                    q_out(8) := q_m(PIXEL_BITS);

                    if q_m(PIXEL_BITS) = '1' then
                        q_out(7 downto 0) := q_m(7 downto 0);
                        cnt_nx            := disparity + diff;
                    else
                        q_out(7 downto 0) := not q_m(7 downto 0);
                        cnt_nx            := disparity - diff;
                    end if;
                elsif (disparity > 0 and diff > 0) or (disparity < 0 and diff < 0) then
                    q_out(9)          := '1';
                    q_out(8)          := q_m(PIXEL_BITS);
                    q_out(7 downto 0) := not q_m(7 downto 0);
                    cnt_nx            := disparity - diff;

                    if q_m(PIXEL_BITS) = '1' then
                        cnt_nx := cnt_nx + 2;
                    end if;
                else
                    q_out(9)          := '0';
                    q_out(8)          := q_m(PIXEL_BITS);
                    q_out(7 downto 0) := q_m(7 downto 0);
                    cnt_nx            := disparity + diff;

                    if q_m(PIXEL_BITS) = '0' then
                        cnt_nx := cnt_nx - 2;
                    end if;
                end if;

                token     <= q_out;
                disparity <= cnt_nx;
            end if;
        end if;

    end process p_encode;

end architecture rtl;
