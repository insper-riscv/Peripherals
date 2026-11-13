-- =============================================================================
-- Sequenciador de inicialização do transmissor HDMI
--
-- Domínio do clock do sistema. Percorre a tabela de pares registrador-valor
-- recebida por generic (init_table, quatro dígitos hexadecimais por entrada,
-- registrador primeiro) e pede ao escritor I2C uma escrita por entrada, na
-- ordem da tabela, esperando o fim de cada uma antes de pedir a seguinte. A
-- confirmação do chip é contada e não interrompe a sequência: o_nacks conta as
-- escritas sem confirmação (saturado em 255) e o_nack_seen guarda se houve
-- alguma, até o próximo início.
--
-- A sequência começa sozinha depois do reset se auto_start for verdadeiro, e
-- sempre que i_start pulsar com o sequenciador parado. Um pulso de i_start com
-- a sequência em andamento é ignorado. Com a tabela vazia, o início só marca o
-- fim (o_done), sem nenhuma escrita.
--
-- Estados: parado, pedindo a escrita da entrada atual, esperando o fim dela.
-- o_done vale '1' depois que a última entrada terminou e volta a '0' no
-- próximo início; o_sent conta as entradas já concluídas (saturado em 255).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.utils_pkg.all;
use work.hdmi_consts.all;

entity hdmi_init_seq is
    generic (
        -- Tabela de inicialização: quatro dígitos hexadecimais por entrada, registrador e depois valor.
        init_table : string  := "";
        -- A sequência começa sozinha logo depois do reset.
        auto_start : boolean := true
    );
    port (
        -- Clock do sistema.
        i_clk       : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst       : in    std_logic;

        -- Pulso de um ciclo que (re)inicia a sequência quando ela está parada.
        i_start     : in    std_logic;

        -- Pulso de um ciclo que pede ao escritor I2C a escrita da entrada atual.
        o_wr_start  : out   std_logic;
        -- Registrador da entrada atual.
        o_wr_reg    : out   std_logic_vector(7 downto 0);
        -- Valor da entrada atual.
        o_wr_value  : out   std_logic_vector(7 downto 0);
        -- Pulso de fim da escrita pedida, vindo do escritor I2C.
        i_wr_done   : in    std_logic;
        -- A escrita que terminou não foi confirmada pelo chip, válido no pulso de i_wr_done.
        i_wr_nack   : in    std_logic;

        -- A sequência está em andamento.
        o_busy      : out   std_logic;
        -- A sequência terminou e não foi reiniciada.
        o_done      : out   std_logic;
        -- Alguma escrita da sequência não foi confirmada.
        o_nack_seen : out   std_logic;
        -- Entradas concluídas desde o início, saturado em 255.
        o_sent      : out   std_logic_vector(7 downto 0);
        -- Escritas sem confirmação desde o início, saturado em 255.
        o_nacks     : out   std_logic_vector(7 downto 0)
    );
end entity hdmi_init_seq;

architecture rtl of hdmi_init_seq is

    -- Número de entradas da tabela.
    constant COUNT    : natural  := init_count(init_table);
    -- Posições da memória de entradas (no mínimo uma, para a tabela vazia).
    constant ROM_SIZE : positive := pick(COUNT > 0, COUNT, 1);
    -- Maior valor dos contadores saturados.
    constant SAT      : natural  := 255;

    -- Memória de entradas, registrador nos bits 15:8 e valor nos bits 7:0.
    type rom_t is array(0 to ROM_SIZE - 1) of std_logic_vector(15 downto 0);

    -- Monta a memória de entradas a partir da tabela, em tempo de elaboração.
    function build_rom return rom_t is

        -- Memória em montagem.
        variable rom : rom_t := (others => (others => '0'));

    begin

        for i in 0 to COUNT - 1 loop

            rom(i) := init_word(init_table, i);

        end loop;

        return rom;

    end function build_rom;

    -- Entradas da tabela.
    constant ROM : rom_t := build_rom;

    -- Estados da sequência.
    type state_t is (S_IDLE, S_ISSUE, S_WAIT);

    -- Estado atual; com auto_start e tabela não vazia a sequência já nasce pedindo a primeira entrada.
    signal state     : state_t                      := S_IDLE;
    -- Índice da entrada atual.
    signal index     : natural range 0 to ROM_SIZE - 1 := 0;
    -- A sequência terminou.
    signal done_q    : std_logic                    := '0';
    -- Alguma escrita não foi confirmada.
    signal nack_q    : std_logic                    := '0';
    -- Entradas concluídas.
    signal sent_q    : natural range 0 to SAT       := 0;
    -- Escritas sem confirmação.
    signal nacks_q   : natural range 0 to SAT       := 0;
    -- Pedido de escrita ao escritor I2C.
    signal wr_start  : std_logic                    := '0';

begin

    assert is_valid_table(init_table)
        report "hdmi_init_seq: init_table deve ter quatro dígitos hexadecimais por entrada, no máximo 255 entradas"
        severity failure;

    o_wr_start  <= wr_start;
    o_wr_reg    <= ROM(index)(15 downto 8);
    o_wr_value  <= ROM(index)(7 downto 0);
    o_busy      <= to_sl(state /= S_IDLE);
    o_done      <= done_q;
    o_nack_seen <= nack_q;
    o_sent      <= std_logic_vector(to_unsigned(sent_q, 8));
    o_nacks     <= std_logic_vector(to_unsigned(nacks_q, 8));

    p_fsm : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            wr_start <= '0';

            if i_rst = '1' then
                index   <= 0;
                sent_q  <= 0;
                nacks_q <= 0;
                nack_q  <= '0';
                done_q  <= to_sl(auto_start and COUNT = 0);
                if auto_start and COUNT > 0 then
                    state <= S_ISSUE;
                else
                    state <= S_IDLE;
                end if;
            else
                case state is
                    when S_IDLE =>
                        if i_start = '1' then
                            index   <= 0;
                            sent_q  <= 0;
                            nacks_q <= 0;
                            nack_q  <= '0';
                            done_q  <= to_sl(COUNT = 0);
                            if COUNT > 0 then
                                state <= S_ISSUE;
                            end if;
                        end if;
                    when S_ISSUE =>
                        wr_start <= '1';
                        state    <= S_WAIT;
                    when S_WAIT =>
                        if i_wr_done = '1' then
                            sent_q <= pick(sent_q = SAT, SAT, sent_q + 1);
                            if i_wr_nack = '1' then
                                nack_q  <= '1';
                                nacks_q <= pick(nacks_q = SAT, SAT, nacks_q + 1);
                            end if;
                            if index = COUNT - 1 then
                                state  <= S_IDLE;
                                done_q <= '1';
                            else
                                index <= index + 1;
                                state <= S_ISSUE;
                            end if;
                        end if;
                end case;
            end if;
        end if;

    end process p_fsm;

end architecture rtl;
