-- =============================================================================
-- Registradores e FIFO do receptor de infravermelho
--
-- Interface de barramento do receptor: controle, status com bits pegajosos que
-- se limpam escrevendo 1, o registrador de dados que lê a cabeça da FIFO de
-- quadros (a leitura remove o quadro) e as duas larguras brutas da última
-- medida. Os quadros do decodificador entram na FIFO; o quadro que chega com a
-- FIFO cheia é perdido e acende o bit de estouro. A interrupção é de nível e
-- reúne quadro disponível, erro ou estouro, e medida bruta nova, cada um com a
-- sua máscara. A leitura é combinacional no endereço e amostrada antes da
-- borda que a efetiva.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.config_pkg.all;
use work.ir_consts.all;

entity ir_regs is
    generic (
        -- Profundidade da FIFO de quadros (no máximo 255).
        fifo_depth : positive := 8;
        -- Com falso, as larguras brutas não são guardadas e leem zero.
        raw_enable : boolean  := true
    );
    port (
        -- Clock do módulo.
        i_clk         : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst         : in    std_logic;
        -- Dado de escrita vindo do processador.
        i_data_in     : in    word_t;
        -- Endereço de palavra vindo do processador.
        i_address     : in    std_logic_vector(2 downto 0);
        -- Pulso de escrita ('1' = escreve).
        i_write       : in    std_logic;
        -- Pulso de leitura ('1' = lê).
        i_read        : in    std_logic;
        -- Dado de leitura para o processador.
        o_data_out    : out   word_t;
        -- Requisição de interrupção, ativa em '1'.
        o_irq         : out   std_logic;
        -- Receptor habilitado.
        o_enable      : out   std_logic;
        -- Aceita o NEC estendido.
        o_ext_en      : out   std_logic;
        -- Quadro válido do decodificador.
        i_frame_valid : in    std_logic;
        -- Endereço do quadro.
        i_address_f   : in    std_logic_vector(15 downto 0);
        -- Comando do quadro.
        i_command_f   : in    std_logic_vector(7 downto 0);
        -- Quadro é repetição.
        i_repeat_f    : in    std_logic;
        -- Quadro usa endereço estendido.
        i_extended_f  : in    std_logic;
        -- Quadro malformado descartado.
        i_error_f     : in    std_logic;
        -- Medida de nível nova do medidor.
        i_event       : in    std_logic;
        -- Tipo da medida: '1' pulso, '0' espaço.
        i_event_mark  : in    std_logic;
        -- Largura da medida em ciclos.
        i_width       : in    std_logic_vector(31 downto 0);
        -- Nível filtrado da linha.
        i_line_active : in    std_logic
    );
end entity ir_regs;

architecture rtl of ir_regs is

    -- Bit de habilitação.
    signal en_r        : std_logic := '0';
    -- Máscara de interrupção de quadro.
    signal frame_ie_r  : std_logic := '0';
    -- Máscara de interrupção de erro e estouro.
    signal err_ie_r    : std_logic := '0';
    -- Aceita o NEC estendido.
    signal ext_en_r    : std_logic := '1';
    -- Máscara de interrupção de medida bruta.
    signal raw_ie_r    : std_logic := '0';
    -- Erro de quadro pegajoso.
    signal frame_err_r : std_logic := '0';
    -- Estouro pegajoso.
    signal overflow_r  : std_logic := '0';
    -- Medida bruta nova pegajosa.
    signal raw_new_r   : std_logic := '0';
    -- Largura do último pulso.
    signal raw_mark_r  : std_logic_vector(31 downto 0) := (others => '0');
    -- Largura do último espaço.
    signal raw_space_r : std_logic_vector(31 downto 0) := (others => '0');

    -- Escrita no registrador de controle.
    signal wr_ctrl   : std_logic;
    -- Escrita no registrador de status.
    signal wr_status : std_logic;
    -- Esvaziamento da FIFO pedido.
    signal flush     : std_logic;
    -- Leitura do registrador de dados.
    signal rd_data   : std_logic;
    -- Quadro empacotado de entrada da FIFO.
    signal frame_in  : std_logic_vector(FRAME_WIDTH - 1 downto 0);
    -- Quadro da cabeça da FIFO.
    signal frame_out : std_logic_vector(FRAME_WIDTH - 1 downto 0);
    -- FIFO cheia.
    signal full      : std_logic;
    -- FIFO vazia.
    signal empty     : std_logic;
    -- Nível da FIFO.
    signal level     : natural range 0 to fifo_depth;
    -- Quadro perdido por FIFO cheia.
    signal refused   : std_logic;

begin

    wr_ctrl   <= '1' when i_write = '1' and i_address = ADDR_CTRL else '0';
    wr_status <= '1' when i_write = '1' and i_address = ADDR_STATUS else '0';
    flush     <= wr_ctrl and i_data_in(CTRL_FLUSH);
    rd_data   <= '1' when i_read = '1' and i_address = ADDR_DATA else '0';

    frame_in <= i_extended_f & i_repeat_f & i_command_f & i_address_f;

    o_enable <= en_r;
    o_ext_en <= ext_en_r;

    u_fifo : entity work.ir_fifo
        generic map (
            data_width => FRAME_WIDTH,
            depth      => fifo_depth
        )
        port map (
            i_clk       => i_clk,
            i_rst       => i_rst,
            i_flush     => flush,
            i_push      => i_frame_valid,
            i_push_data => frame_in,
            i_pop       => rd_data,
            o_pop_data  => frame_out,
            o_full      => full,
            o_empty     => empty,
            o_level     => level,
            o_refused   => refused
        );

    o_irq <= (frame_ie_r and not empty) or (err_ie_r and (frame_err_r or overflow_r)) or (raw_ie_r and raw_new_r);

    -- Leitura combinacional de cada registrador.
    p_read : process (i_address, en_r, frame_ie_r, err_ie_r, ext_en_r, raw_ie_r, empty, full, frame_err_r,
                      overflow_r, i_line_active, raw_new_r, level, frame_out, raw_mark_r, raw_space_r) is
        -- Palavra de leitura montada para o endereço atual.
        variable v : word_t;
    begin

        v := (others => '0');

        case i_address is
            when ADDR_CTRL =>
                v(CTRL_EN)       := en_r;
                v(CTRL_FRAME_IE) := frame_ie_r;
                v(CTRL_ERR_IE)   := err_ie_r;
                v(CTRL_EXT_EN)   := ext_en_r;
                v(CTRL_RAW_IE)   := raw_ie_r;
            when ADDR_STATUS =>
                v(STAT_NOT_EMPTY) := not empty;
                v(STAT_FULL)      := full;
                v(STAT_FRAME_ERR) := frame_err_r;
                v(STAT_OVERFLOW)  := overflow_r;
                v(STAT_LINE)      := i_line_active;
                v(STAT_RAW_NEW)   := raw_new_r;
                v(STAT_LEVEL_LSB + 7 downto STAT_LEVEL_LSB) := std_logic_vector(to_unsigned(level, 8));
            when ADDR_DATA =>
                v(FRAME_WIDTH - 1 downto 0) := frame_out;
            when ADDR_RAW_MARK =>
                v(31 downto 0) := raw_mark_r;
            when ADDR_RAW_SPACE =>
                v(31 downto 0) := raw_space_r;
            when others =>
                null;
        end case;

        o_data_out <= v;

    end process p_read;

    -- Registradores de controle, bits pegajosos e larguras brutas.
    p_regs : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            if i_rst = '1' then
                en_r        <= '0';
                frame_ie_r  <= '0';
                err_ie_r    <= '0';
                ext_en_r    <= '1';
                raw_ie_r    <= '0';
                frame_err_r <= '0';
                overflow_r  <= '0';
                raw_new_r   <= '0';
                raw_mark_r  <= (others => '0');
                raw_space_r <= (others => '0');
            else
                if wr_ctrl = '1' then
                    en_r       <= i_data_in(CTRL_EN);
                    frame_ie_r <= i_data_in(CTRL_FRAME_IE);
                    err_ie_r   <= i_data_in(CTRL_ERR_IE);
                    ext_en_r   <= i_data_in(CTRL_EXT_EN);
                    raw_ie_r   <= i_data_in(CTRL_RAW_IE);
                end if;

                if wr_status = '1' then
                    if i_data_in(STAT_FRAME_ERR) = '1' then
                        frame_err_r <= '0';
                    end if;

                    if i_data_in(STAT_OVERFLOW) = '1' then
                        overflow_r <= '0';
                    end if;

                    if i_data_in(STAT_RAW_NEW) = '1' then
                        raw_new_r <= '0';
                    end if;
                end if;

                if i_error_f = '1' then
                    frame_err_r <= '1';
                end if;

                if refused = '1' then
                    overflow_r <= '1';
                end if;

                if raw_enable and i_event = '1' then
                    raw_new_r <= '1';

                    if i_event_mark = '1' then
                        raw_mark_r <= i_width;
                    else
                        raw_space_r <= i_width;
                    end if;
                end if;
            end if;
        end if;

    end process p_regs;

end architecture rtl;
