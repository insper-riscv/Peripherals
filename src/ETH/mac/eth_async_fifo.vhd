-- =============================================================================
-- FIFO assíncrona de dois clocks com ponteiros em código Gray
--
-- Fila de 2**addr_bits palavras entre o domínio de escrita (i_wclk) e o de
-- leitura (i_rclk). Cada ponteiro tem addr_bits + 1 bits, o bit extra
-- distingue cheia de vazia, e atravessa o domínio oposto em código Gray por um
-- sincronizador, de modo que só um bit muda por vez. A memória é uma
-- eth_dpram com leitura registrada; o endereço de leitura é o do ponteiro
-- seguinte quando há retirada, e a palavra do topo aparece em o_rdata sempre
-- que o_empty está em '0' (primeira palavra à frente, sem esperar i_rd_en).
--
-- Uma escrita com a fila cheia e uma leitura com a fila vazia são ignoradas. As
-- flags são conservadoras: o_full e o_empty podem durar alguns ciclos além do
-- estado real, nunca o contrário. o_full_next antecipa em um
-- ciclo o o_full que a escrita deste ciclo causa. Cada lado tem seu reset síncrono, e os dois
-- devem ser ativados juntos e por tempo suficiente para o sincronizador do
-- outro domínio enxergar os ponteiros zerados.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity eth_async_fifo is
    generic (
        -- Largura da palavra em bits.
        data_width  : positive := 9;
        -- Largura do endereço da memória (profundidade 2**addr_bits, no mínimo 2).
        addr_bits   : positive := 4;
        -- Estágios dos sincronizadores dos ponteiros.
        sync_stages : positive := 2
    );
    port (
        -- Clock de escrita.
        i_wclk  : in    std_logic;
        -- Reset síncrono do lado de escrita.
        i_wrst  : in    std_logic;
        -- Pedido de escrita, ignorado com a fila cheia.
        i_wr_en : in    std_logic;
        -- Palavra a escrever.
        i_wdata : in    std_logic_vector(data_width - 1 downto 0);
        -- Fila cheia, visto do lado de escrita.
        o_full  : out   std_logic;
        -- Fila cheia depois da escrita deste ciclo, para quem escreve a cada ciclo.
        o_full_next : out std_logic;
        -- Clock de leitura.
        i_rclk  : in    std_logic;
        -- Reset síncrono do lado de leitura.
        i_rrst  : in    std_logic;
        -- Retira a palavra do topo, ignorado com a fila vazia.
        i_rd_en : in    std_logic;
        -- Palavra do topo, válida quando o_empty vale '0'.
        o_rdata : out   std_logic_vector(data_width - 1 downto 0);
        -- Fila vazia, visto do lado de leitura.
        o_empty : out   std_logic
    );
end entity eth_async_fifo;

architecture rtl of eth_async_fifo is

    -- Código Gray de um contador binário.
    function to_gray (
        value : unsigned
    ) return std_logic_vector is
    begin
        return std_logic_vector(value xor shift_right(value, 1));
    end function to_gray;

    -- Ponteiro binário de escrita.
    signal wbin       : unsigned(addr_bits downto 0) := (others => '0');
    -- Ponteiro binário de escrita depois da escrita deste ciclo.
    signal wbin_next  : unsigned(addr_bits downto 0);
    -- Ponteiro de escrita em Gray.
    signal wgray      : std_logic_vector(addr_bits downto 0) := (others => '0');
    -- Ponteiro de leitura em Gray, sincronizado no domínio de escrita.
    signal rgray_sync : std_logic_vector(addr_bits downto 0);
    -- A fila está cheia.
    signal full       : std_logic;
    -- A escrita deste ciclo é aceita.
    signal wr_ok      : std_logic;

    -- Ponteiro binário de leitura.
    signal rbin       : unsigned(addr_bits downto 0) := (others => '0');
    -- Ponteiro binário de leitura depois da retirada deste ciclo.
    signal rbin_next  : unsigned(addr_bits downto 0);
    -- Ponteiro de leitura em Gray.
    signal rgray      : std_logic_vector(addr_bits downto 0) := (others => '0');
    -- Ponteiro de escrita em Gray, sincronizado no domínio de leitura.
    signal wgray_sync : std_logic_vector(addr_bits downto 0);
    -- A fila está vazia.
    signal empty      : std_logic;
    -- A retirada deste ciclo é aceita.
    signal rd_ok      : std_logic;

begin

    assert addr_bits >= 2
        report "eth_async_fifo: addr_bits deve ser no mínimo 2"
        severity failure;

    -----------------------------------------------------------------------------
    -- Lado de escrita
    -----------------------------------------------------------------------------

    u_sync_rptr : entity work.synchronizer
        generic map (
            stages     => sync_stages,
            data_width => addr_bits + 1
        )
        port map (
            i_clk => i_wclk,
            i_rst => i_wrst,
            i_d   => rgray,
            o_d   => rgray_sync
        );

    -- A fila está cheia quando o ponteiro de escrita deu uma volta à frente do de leitura.
    full <= '1' when wgray = (not rgray_sync(addr_bits) & not rgray_sync(addr_bits - 1)
                              & rgray_sync(addr_bits - 2 downto 0)) else '0';

    wr_ok      <= i_wr_en and not full;
    wbin_next  <= wbin + 1 when wr_ok = '1' else wbin;

    p_wptr : process (i_wclk) is
    begin

        if rising_edge(i_wclk) then
            if i_wrst = '1' then
                wbin  <= (others => '0');
                wgray <= (others => '0');
            else
                wbin  <= wbin_next;
                wgray <= to_gray(wbin_next);
            end if;
        end if;

    end process p_wptr;

    o_full <= full;

    -- Cheia depois de aceitar a escrita deste ciclo: o ponteiro seguinte é o da volta à frente do de leitura.
    o_full_next <= '1' when to_gray(wbin + 1) = (not rgray_sync(addr_bits) & not rgray_sync(addr_bits - 1)
                                                  & rgray_sync(addr_bits - 2 downto 0)) else '0';

    -----------------------------------------------------------------------------
    -- Lado de leitura
    -----------------------------------------------------------------------------

    u_sync_wptr : entity work.synchronizer
        generic map (
            stages     => sync_stages,
            data_width => addr_bits + 1
        )
        port map (
            i_clk => i_rclk,
            i_rst => i_rrst,
            i_d   => wgray,
            o_d   => wgray_sync
        );

    empty <= '1' when rgray = wgray_sync else '0';

    rd_ok     <= i_rd_en and not empty;
    rbin_next <= rbin + 1 when rd_ok = '1' else rbin;

    p_rptr : process (i_rclk) is
    begin

        if rising_edge(i_rclk) then
            if i_rrst = '1' then
                rbin  <= (others => '0');
                rgray <= (others => '0');
            else
                rbin  <= rbin_next;
                rgray <= to_gray(rbin_next);
            end if;
        end if;

    end process p_rptr;

    o_empty <= empty;

    -----------------------------------------------------------------------------
    -- Memória
    -----------------------------------------------------------------------------

    u_mem : entity work.eth_dpram
        generic map (
            data_width => data_width,
            addr_width => addr_bits
        )
        port map (
            i_wclk  => i_wclk,
            i_we    => wr_ok,
            i_waddr => std_logic_vector(wbin(addr_bits - 1 downto 0)),
            i_wdata => i_wdata,
            i_rclk  => i_rclk,
            i_raddr => std_logic_vector(rbin_next(addr_bits - 1 downto 0)),
            o_rdata => o_rdata
        );

end architecture rtl;
