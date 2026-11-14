-- =============================================================================
-- Mestre do barramento paralelo do chip USB
--
-- Executa um acesso por vez ao chip: ciclo de preparação (chip selecionado,
-- endereço e dado estáveis), pulso de leitura ou de escrita, um ciclo de
-- retenção com o chip ainda selecionado e ciclo de recuperação com tudo
-- inativo. Cada etapa dura o número de ciclos do campo correspondente (zero
-- vale um ciclo). Todas as saídas vêm de registradores, sem glitch. O dado
-- lido é amostrado no último ciclo do pulso de leitura, vindo de uma entrada já
-- sincronizada (atraso de dois ciclos em relação ao pino).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.usb_consts.all;

entity usb_bus_master is
    port (
        -- Clock do módulo.
        i_clk : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst : in    std_logic;

        -- Pedido de acesso, aceito só com o mestre livre.
        i_start    : in    std_logic;
        -- Tipo do acesso: '1' leitura, '0' escrita.
        i_is_read  : in    std_logic;
        -- Endereço do chip (porta de acesso) do acesso.
        i_port     : in    std_logic_vector(CHIP_ADDR_BITS - 1 downto 0);
        -- Dado a escrever no chip.
        i_wdata    : in    std_logic_vector(CHIP_DATA_BITS - 1 downto 0);
        -- Ciclos de preparação antes do pulso.
        i_setup    : in    std_logic_vector(TIMING_FIELD_BITS - 1 downto 0);
        -- Ciclos de duração do pulso de leitura ou de escrita.
        i_pulse    : in    std_logic_vector(TIMING_FIELD_BITS - 1 downto 0);
        -- Ciclos de recuperação depois do acesso.
        i_recovery : in    std_logic_vector(TIMING_FIELD_BITS - 1 downto 0);
        -- Acesso em andamento.
        o_busy     : out   std_logic;
        -- Último dado lido do chip.
        o_rdata    : out   std_logic_vector(CHIP_DATA_BITS - 1 downto 0);

        -- Dado do chip, já sincronizado com i_clk.
        i_chip_data    : in    std_logic_vector(CHIP_DATA_BITS - 1 downto 0);
        -- Seleção do chip, ativa em '0'.
        o_cs_n         : out   std_logic;
        -- Estrobo de leitura, ativo em '0'.
        o_rd_n         : out   std_logic;
        -- Estrobo de escrita, ativo em '0'.
        o_wr_n         : out   std_logic;
        -- Endereço do chip.
        o_chip_addr    : out   std_logic_vector(CHIP_ADDR_BITS - 1 downto 0);
        -- Dado que o barramento apresenta ao chip.
        o_chip_data    : out   std_logic_vector(CHIP_DATA_BITS - 1 downto 0);
        -- Habilita a saída do dado (barramento do chip em escrita).
        o_chip_data_oe : out   std_logic
    );
end entity usb_bus_master;

architecture rtl of usb_bus_master is

    -- Etapas de um acesso ao chip.
    type state_t is (S_IDLE, S_SETUP, S_PULSE, S_HOLD, S_RECOVERY);

    -- Etapa atual.
    signal state     : state_t := S_IDLE;
    -- Ciclos que faltam na etapa atual, contando o atual.
    signal remaining : unsigned(TIMING_FIELD_BITS - 1 downto 0) := (others => '0');
    -- O acesso em curso é uma leitura.
    signal is_read   : std_logic;
    -- A etapa atual termina neste ciclo.
    signal last      : std_logic;

    -- Registrador da seleção do chip.
    signal cs_n    : std_logic;
    -- Registrador do estrobo de leitura.
    signal rd_n    : std_logic;
    -- Registrador do estrobo de escrita.
    signal wr_n    : std_logic;
    -- Registrador do endereço do chip.
    signal addr    : std_logic_vector(CHIP_ADDR_BITS - 1 downto 0);
    -- Registrador do dado apresentado ao chip.
    signal wdata   : std_logic_vector(CHIP_DATA_BITS - 1 downto 0);
    -- Registrador da habilitação da saída do dado.
    signal data_oe : std_logic;
    -- Último dado lido.
    signal rdata   : std_logic_vector(CHIP_DATA_BITS - 1 downto 0);

begin

    last <= '1' when remaining <= 1 else '0';

    o_busy         <= '0' when state = S_IDLE else '1';
    o_rdata        <= rdata;
    o_cs_n         <= cs_n;
    o_rd_n         <= rd_n;
    o_wr_n         <= wr_n;
    o_chip_addr    <= addr;
    o_chip_data    <= wdata;
    o_chip_data_oe <= data_oe;

    process (i_clk) is
    begin
        if rising_edge(i_clk) then
            if i_rst = '1' then
                state     <= S_IDLE;
                remaining <= (others => '0');
                is_read   <= '0';
                cs_n      <= '1';
                rd_n      <= '1';
                wr_n      <= '1';
                addr      <= (others => '0');
                wdata     <= (others => '0');
                data_oe   <= '0';
                rdata     <= (others => '0');
            else
                case state is
                    when S_IDLE =>
                        if i_start = '1' then
                            state     <= S_SETUP;
                            remaining <= unsigned(i_setup);
                            is_read   <= i_is_read;
                            cs_n      <= '0';
                            addr      <= i_port;
                            wdata     <= i_wdata;
                            data_oe   <= not i_is_read;
                        end if;

                    when S_SETUP =>
                        if last = '1' then
                            state     <= S_PULSE;
                            remaining <= unsigned(i_pulse);
                            rd_n      <= not is_read;
                            wr_n      <= is_read;
                        else
                            remaining <= remaining - 1;
                        end if;

                    when S_PULSE =>
                        if last = '1' then
                            state <= S_HOLD;
                            rd_n  <= '1';
                            wr_n  <= '1';
                            if is_read = '1' then
                                rdata <= i_chip_data;
                            end if;
                        else
                            remaining <= remaining - 1;
                        end if;

                    when S_HOLD =>
                        state     <= S_RECOVERY;
                        remaining <= unsigned(i_recovery);
                        cs_n      <= '1';
                        data_oe   <= '0';

                    when S_RECOVERY =>
                        if last = '1' then
                            state <= S_IDLE;
                        else
                            remaining <= remaining - 1;
                        end if;
                end case;
            end if;
        end if;
    end process;

end architecture rtl;
