-- ==========================================================================
-- Miter do console: a entidade console contra o bloco que ela escolhe
-- ==========================================================================
-- Só para a prova formal (não faz parte do SoC). Instancia o console e, ao
-- lado, o bloco de referência do mesmo backend ligado direto às mesmas
-- entradas, com a polaridade dos pinos escrita à parte como inversão
-- explícita. A prova exige que as saídas dos dois sejam iguais em todo
-- ciclo, ou seja, que o console não acrescenta lógica além da escolha da
-- instância e da polaridade.
-- ==========================================================================

library ieee;
use ieee.std_logic_1164.all;

entity console_equiv is
    generic (
        -- Backend do console: "jtag" ou "pinos".
        backend       : string   := "pinos";
        -- Constante de frequência do gerador de baud.
        baud_freq     : natural  := 0;
        -- Constante de limite do gerador de baud.
        baud_limit    : natural  := 0;
        -- Bytes na fila de recepção.
        rx_fifo_depth : positive := 3;
        -- Bytes na fila de transmissão.
        tx_fifo_depth : positive := 3;
        -- Log2 da profundidade de cada fila do backend jtag.
        log2_depth    : natural  := 2;
        -- Inverte a polaridade do pino de transmissão.
        tx_invert     : boolean  := false;
        -- Inverte a polaridade do pino de recepção.
        rx_invert     : boolean  := false
    );
    port (
        -- Clock do módulo (também o clock da cadeia JTAG).
        i_clk       : in    std_logic;
        -- Reset, ativo em '1'.
        i_rst       : in    std_logic;
        -- Endereço de palavra do acesso.
        i_addr      : in    std_logic_vector(7 downto 0);
        -- Dado de escrita.
        i_wdata     : in    std_logic_vector(31 downto 0);
        -- Escrita ('1').
        i_we        : in    std_logic;
        -- Leitura ('1').
        i_re        : in    std_logic;
        -- Linha serial de recepção.
        i_rx        : in    std_logic;
        -- Dado lido do console.
        o_rdata_dut : out   std_logic_vector(31 downto 0);
        -- Dado lido da referência.
        o_rdata_ref : out   std_logic_vector(31 downto 0);
        -- Interrupção do console.
        o_irq_dut   : out   std_logic;
        -- Interrupção da referência.
        o_irq_ref   : out   std_logic;
        -- Linha de transmissão do console.
        o_tx_dut    : out   std_logic;
        -- Linha de transmissão da referência.
        o_tx_ref    : out   std_logic;
        -- Saída da cadeia JTAG do console.
        o_tdo_dut   : out   std_logic;
        -- Saída da cadeia JTAG da referência.
        o_tdo_ref   : out   std_logic
    );
end entity console_equiv;

architecture rtl of console_equiv is

    -- Linha de transmissão do bloco serial de referência.
    signal ref_tx : std_logic;
    -- Linha de recepção do bloco serial de referência.
    signal ref_rx : std_logic;

begin

    u_dut : entity work.console
        generic map (
            backend       => backend,
            baud_freq     => baud_freq,
            baud_limit    => baud_limit,
            rx_fifo_depth => rx_fifo_depth,
            tx_fifo_depth => tx_fifo_depth,
            log2_depth    => log2_depth,
            tx_invert     => tx_invert,
            rx_invert     => rx_invert
        )
        port map (
            i_clk       => i_clk,
            i_rst       => i_rst,
            i_addr      => i_addr,
            i_wdata     => i_wdata,
            i_we        => i_we,
            i_re        => i_re,
            o_rdata     => o_rdata_dut,
            o_irq       => o_irq_dut,
            i_rx        => i_rx,
            o_tx        => o_tx_dut,
            o_rts       => open,
            i_tck       => i_clk,
            i_tdi       => '0',
            o_tdo       => o_tdo_dut,
            i_ir_in     => "00",
            i_state_cdr => '0',
            i_state_sdr => '0',
            i_state_udr => '0',
            i_state_uir => '0'
        );

    gen_pins : if backend = "pinos" generate
    begin
        ref_rx <= not i_rx when rx_invert else i_rx;

        u_ref : entity work.uart
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
                o_data_out => o_rdata_ref,
                o_irq      => o_irq_ref,
                i_uart_rx  => ref_rx,
                o_uart_tx  => ref_tx,
                o_uart_rts => open
            );

        o_tx_ref  <= not ref_tx when tx_invert else ref_tx;
        o_tdo_ref <= '0';
    end generate gen_pins;

    gen_jtag : if backend = "jtag" generate
    begin

        u_ref : entity work.jtag_uart
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
                o_rdata     => o_rdata_ref,
                o_irq       => o_irq_ref,
                i_tck       => i_clk,
                i_tdi       => '0',
                o_tdo       => o_tdo_ref,
                i_ir_in     => "00",
                i_state_cdr => '0',
                i_state_sdr => '0',
                i_state_udr => '0',
                i_state_uir => '0'
            );

        o_tx_ref <= '0' when tx_invert else '1';
    end generate gen_jtag;

end architecture rtl;
