-- ==========================================================================
-- Console do SoC com o backend escolhido por generic
-- ==========================================================================
-- Uma só interface de console para o software e para o interconector: o
-- barramento de periférico (endereço, dado, escrita, leitura, dado lido) e a
-- interrupção de nível. O generic backend escolhe qual bloco existente
-- atende o barramento, sem lógica própria além da escolha da instância e da
-- polaridade dos pinos:
--
--   "jtag"   (padrão) jtag_uart, cuja outra ponta é o hospedeiro no Virtual
--            JTAG; usa as portas i_tck a i_state_uir e o_tdo, e deixa os
--            pinos sem uso (o_tx em repouso, i_rx ignorado).
--   "pinos"  uart serial 8N1, cuja outra ponta são os pinos i_rx e o_tx da
--            placa; as portas do Virtual JTAG ficam sem uso (o_tdo em zero).
--
-- Os dois blocos têm a mesma forma de palavra no barramento: palavra 0 envia
-- um byte, palavra 1 recebe um byte nos bits 7:0 e palavra 3 habilita as
-- três causas de interrupção nos bits 2:0. A palavra 2 (STATUS) e o bit 8 de
-- RXDATA são do backend e estão em docs/pt-br/UART. O o_irq de cada backend
-- mantém a semântica de nível do bloco escolhido.
--
-- A instância do sld_virtual_jtag fica fora desta entidade, no topo
-- estrutural, porque é primitiva de fornecedor: este arquivo não tem nome de
-- placa nem de família.
-- ==========================================================================

library ieee;
use ieee.std_logic_1164.all;

entity console is
    generic (
        -- Backend do console: "jtag" ou "pinos".
        backend       : string   := "jtag";
        -- Constante de frequência do gerador de baud (backend "pinos").
        baud_freq     : natural  := 16#240#;
        -- Constante de limite do gerador de baud (backend "pinos").
        baud_limit    : natural  := 16#3AC9#;
        -- Bytes na fila de recepção (backend "pinos").
        rx_fifo_depth : positive := 16;
        -- Bytes na fila de transmissão (backend "pinos").
        tx_fifo_depth : positive := 16;
        -- Log2 da profundidade de cada fila (backend "jtag").
        log2_depth    : natural  := 6;
        -- Inverte a polaridade do pino de transmissão (backend "pinos").
        tx_invert     : boolean  := false;
        -- Inverte a polaridade do pino de recepção (backend "pinos").
        rx_invert     : boolean  := false
    );
    port (
        -- Clock do módulo.
        i_clk : in    std_logic;
        -- Reset, ativo em '1'.
        i_rst : in    std_logic;

        -- Endereço de palavra do acesso (o backend "pinos" usa os dois bits baixos).
        i_addr  : in    std_logic_vector(7 downto 0);
        -- Dado de escrita.
        i_wdata : in    std_logic_vector(31 downto 0);
        -- Escrita ('1').
        i_we    : in    std_logic;
        -- Leitura ('1').
        i_re    : in    std_logic;
        -- Dado lido.
        o_rdata : out   std_logic_vector(31 downto 0);
        -- Requisição de interrupção de nível do console.
        o_irq   : out   std_logic;

        -- Linha serial de recepção (backend "pinos").
        i_rx : in    std_logic := '1';
        -- Linha serial de transmissão (backend "pinos"); em repouso no outro.
        o_tx : out   std_logic;

        -- Clock da cadeia JTAG (backend "jtag").
        i_tck       : in    std_logic                    := '0';
        -- Dado serial vindo do hospedeiro (backend "jtag").
        i_tdi       : in    std_logic                    := '0';
        -- Dado serial para o hospedeiro (backend "jtag").
        o_tdo       : out   std_logic;
        -- Registrador de instrução do Virtual JTAG (backend "jtag").
        i_ir_in     : in    std_logic_vector(1 downto 0) := "00";
        -- Estado Capture-DR da cadeia virtual (backend "jtag").
        i_state_cdr : in    std_logic                    := '0';
        -- Estado Shift-DR da cadeia virtual (backend "jtag").
        i_state_sdr : in    std_logic                    := '0';
        -- Estado Update-DR da cadeia virtual (backend "jtag").
        i_state_udr : in    std_logic                    := '0';
        -- Estado Update-IR da cadeia virtual (backend "jtag").
        i_state_uir : in    std_logic                    := '0'
    );
end entity console;

architecture rtl of console is

begin

    assert backend = "jtag" or backend = "pinos"
        report "console: backend must be ""jtag"" or ""pinos"""
        severity failure;

    g_jtag : if backend = "jtag" generate
    begin

        u_jtag_uart : entity work.jtag_uart
            generic map (
                log2_depth => log2_depth
            )
            port map (
                i_clk       => i_clk,
                i_rst       => i_rst,
                i_addr      => i_addr,
                i_wdata     => i_wdata,
                i_we        => i_we,
                i_re        => i_re,
                o_rdata     => o_rdata,
                o_irq       => o_irq,
                i_tck       => i_tck,
                i_tdi       => i_tdi,
                o_tdo       => o_tdo,
                i_ir_in     => i_ir_in,
                i_state_cdr => i_state_cdr,
                i_state_sdr => i_state_sdr,
                i_state_udr => i_state_udr,
                i_state_uir => i_state_uir
            );

        -- Linha serial em repouso (nível alto antes da polaridade).
        o_tx <= '0' when tx_invert else '1';
    end generate g_jtag;

    g_pins : if backend = "pinos" generate
        -- Linha de transmissão do bloco serial antes da polaridade.
        signal uart_tx : std_logic;
        -- Linha de recepção do bloco serial depois da polaridade.
        signal uart_rx : std_logic;
    begin

        u_uart : entity work.uart
            generic map (
                baud_freq     => baud_freq,
                baud_limit    => baud_limit,
                rx_fifo_depth => rx_fifo_depth,
                tx_fifo_depth => tx_fifo_depth
            )
            port map (
                i_clk      => i_clk,
                i_rst      => i_rst,
                i_data_in  => i_wdata,
                i_address  => i_addr(1 downto 0),
                i_write    => i_we,
                i_read     => i_re,
                o_data_out => o_rdata,
                o_irq      => o_irq,
                i_uart_rx  => uart_rx,
                o_uart_tx  => uart_tx
            );

        o_tx    <= not uart_tx when tx_invert else uart_tx;
        uart_rx <= not i_rx when rx_invert else i_rx;
        o_tdo   <= '0';
    end generate g_pins;

end architecture rtl;
