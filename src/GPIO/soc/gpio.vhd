-- =============================================================================
-- Bloco de E/S de uso geral com partição adaptativa
--
-- Reúne pin_count pinos em group_count grupos. Cada grupo é um gpio_group com o
-- seu arquivo de registradores de 64 bytes, em passos de 64 bytes a partir da
-- base do bloco, e o bloco ocupa uma única janela do interconector, de
-- group_count * 64 bytes arredondado para potência de dois. O bit k dos
-- registradores de um grupo é o k-ésimo pino da lista do grupo, na ordem escrita.
-- Um pino fora de todos os grupos fica desligado: se é só saída, é mantido no
-- nível inativo da placa; senão, fica em alta impedância e não é lido.
--
-- As listas vêm em generics vetoriais, sem tipo da VHDL-2008, para o Quartus
-- Prime Lite aceitar o bloco. Uma lista de números tem um campo de 8 bits por
-- elemento (o elemento k nos bits 8k+7 a 8k), e uma lista de direções tem 2 bits
-- por pino. O formato completo está em docs/pt-br/GPIO/gpio.md.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.config_pkg.all;
use work.gpio_pkg.all;

entity gpio is
    generic (
        -- Pinos do bloco, numerados de 0 a pin_count - 1 (de 1 a 255).
        pin_count      : positive range 1 to 255                                    := 32;
        -- Grupos do bloco (de 1 a 255, cada um com 1 a 32 pinos).
        group_count    : positive range 1 to 255                                    := 1;
        -- Total de índices de pino listados em group_members, a soma de group_sizes.
        member_count   : positive range 1 to 255                                    := 32;
        -- Pinos de cada grupo, um campo de 8 bits por grupo: o grupo g nos bits 8g+7 a 8g.
        group_sizes    : std_logic_vector(8 * group_count - 1 downto 0)             := x"20";
        -- Índices de pino de todos os grupos, em sequência e na ordem escrita, um campo de 8 bits por membro.
        group_members  : std_logic_vector(8 * member_count - 1 downto 0)            :=
            x"1f1e1d1c1b1a191817161514131211100f0e0d0c0b0a09080706050403020100";
        -- Direção fixa de cada pino, 2 bits por pino (0 livre, 1 só entrada, 2 só saída): o pino p nos bits 2p+1 a 2p.
        pin_dirs       : std_logic_vector(2 * pin_count - 1 downto 0)               := (others => '0');
        -- Polaridade de cada pino: '1' é ativo em nível baixo e '0' é ativo em nível alto; o pino p no bit p.
        pin_active_low : std_logic_vector(pin_count - 1 downto 0)                   := (others => '0')
    );
    port (
        -- Clock do módulo.
        i_clk : in    std_logic;

        -- Reset, ativo em '1'.
        i_rst : in    std_logic;

        -- Dado de escrita vindo do processador.
        i_data_in : in    word_t;

        -- Endereço de palavra dentro da janela: o grupo nos bits altos e a palavra do grupo nos 4 bits baixos.
        i_address : in    std_logic_vector(block_addr_width(group_count) - 1 downto 0);

        -- Pulso de escrita do processador ('1' = escreve).
        i_write : in    std_logic;

        -- Pulso de leitura do processador ('1' = lê).
        i_read : in    std_logic;

        -- Dado de leitura para o processador.
        o_data_out : out   word_t;

        -- Requisição de interrupção, ativa em '1' enquanto algum grupo tem pendência.
        o_irq : out   std_logic;

        -- Pinos de E/S físicos (bidirecionais).
        io_gpio_pins : inout std_logic_vector(pin_count - 1 downto 0)
    );
end entity gpio;

architecture rtl of gpio is

    -- Matriz das palavras de leitura, uma por grupo.
    type rdata_array_t is array (0 to group_count - 1) of word_t;

    -- Palavras de leitura de cada grupo, zero quando o grupo não é o endereçado.
    signal group_rdata : rdata_array_t;
    -- Interrupção de cada grupo.
    signal group_irq   : std_logic_vector(group_count - 1 downto 0);
    -- Índice do grupo endereçado.
    signal group_sel   : natural range 0 to 2 ** group_index_bits(group_count) - 1;

begin

    -- O índice do grupo são os bits do endereço acima dos 4 da palavra; com um grupo só, é zero.
    gen_sel_one : if group_count = 1 generate
        group_sel <= 0;
    end generate gen_sel_one;

    gen_sel_many : if group_count > 1 generate
        group_sel <= to_integer(unsigned(i_address(i_address'high downto GROUP_WORD_BITS)));
    end generate gen_sel_many;

    -----------------------------------------------------------------------------
    -- Grupos
    -----------------------------------------------------------------------------
    gen_groups : for g in 0 to group_count - 1 generate

        -- Pinos do grupo.
        constant SIZE  : positive := field_value(group_sizes, g);
        -- Posição do primeiro membro do grupo na lista de membros.
        constant FIRST : natural  := field_sum(group_sizes, g);

        -- O grupo é o endereçado.
        signal hit    : std_logic;
        -- Valor de cada pino do grupo.
        signal pins_i : std_logic_vector(SIZE - 1 downto 0);
        -- Valor que o grupo dirige a cada pino.
        signal pins_d : std_logic_vector(SIZE - 1 downto 0);
        -- Habilitação do tristate de cada pino do grupo.
        signal pins_e : std_logic_vector(SIZE - 1 downto 0);
        -- Palavra de leitura do grupo.
        signal rdata  : word_t;

    begin

        hit <= '1' when group_sel = g else '0';

        u_group : entity work.gpio_group
            generic map (
                width      => SIZE,
                dir_modes  => member_dirs(pin_dirs, group_members, FIRST, SIZE),
                active_low => member_lows(pin_active_low, group_members, FIRST, SIZE)
            )
            port map (
                i_clk      => i_clk,
                i_rst      => i_rst,
                i_data_in  => i_data_in,
                i_address  => i_address(GROUP_WORD_BITS - 1 downto 0),
                i_write    => i_write and hit,
                i_read     => i_read and hit,
                o_data_out => rdata,
                o_irq      => group_irq(g),
                i_pins     => pins_i,
                o_pins_drv => pins_d,
                o_pins_en  => pins_e
            );

        group_rdata(g) <= rdata when hit = '1' else (others => '0');

        gen_pins : for k in 0 to SIZE - 1 generate
            -- Índice do pino do k-ésimo membro do grupo.
            constant PIN : natural := field_value(group_members, FIRST + k);
        begin

            pins_i(k)          <= io_gpio_pins(PIN);
            io_gpio_pins(PIN) <= pins_d(k) when pins_e(k) = '1' else 'Z';

        end generate gen_pins;

    end generate gen_groups;

    -----------------------------------------------------------------------------
    -- Leitura: a palavra do grupo endereçado; um endereço de grupo inexistente lê zero.
    -----------------------------------------------------------------------------
    p_read : process (group_rdata) is

        -- Acumulador do OU das palavras.
        variable acc : word_t;

    begin

        acc := (others => '0');

        for g in 0 to group_count - 1 loop

            acc := acc or group_rdata(g);

        end loop;

        o_data_out <= acc;

    end process p_read;

    p_irq : process (group_irq) is

        -- Acumulador do OU das interrupções.
        variable acc : std_logic;

    begin

        acc := '0';

        for g in 0 to group_count - 1 loop

            acc := acc or group_irq(g);

        end loop;

        o_irq <= acc;

    end process p_irq;

    -----------------------------------------------------------------------------
    -- Pinos desligados: só saída é mantida no nível inativo, o resto fica solto
    -----------------------------------------------------------------------------
    gen_off : for p in 0 to pin_count - 1 generate
    begin

        gen_off_pin : if not is_member(group_members, member_count, p) generate

            gen_hold : if to_mode(pin_dirs(2 * p + 1 downto 2 * p)) = DIR_OUTPUT generate
                io_gpio_pins(p) <= pin_active_low(p);
            end generate gen_hold;

            gen_float : if to_mode(pin_dirs(2 * p + 1 downto 2 * p)) /= DIR_OUTPUT generate
                io_gpio_pins(p) <= 'Z';
            end generate gen_float;

        end generate gen_off_pin;

    end generate gen_off;

end architecture rtl;
