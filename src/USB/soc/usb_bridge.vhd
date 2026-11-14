-- =============================================================================
-- Ponte paralela de 16 bits entre o barramento do SoC e o chip USB da placa
--
-- Topo estrutural. Liga os registradores (usb_regs) ao mestre do barramento do
-- chip (usb_bus_master) e sincroniza as entradas assíncronas (dado, interrupções
-- e pedido de DMA). O chip implementa o USB; esta ponte só faz os acessos de
-- leitura e escrita nas quatro portas (dado e comando do controlador host e do
-- controlador de dispositivo, no caso do ISP1362; as quatro portas da interface
-- HPI, no caso do CY7C67200). O pino de dados é o trio entrada, saída e
-- habilitação, para a camada de tristate do topo da plataforma.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.config_pkg.all;
use work.usb_consts.all;

entity usb_bridge is
    generic (
        -- Ciclos de preparação no reset (0 a 255; zero vale um ciclo).
        setup_cycles    : natural range 0 to 255 := 2;
        -- Ciclos do pulso de leitura ou escrita no reset (0 a 255; zero vale um ciclo).
        pulse_cycles    : natural range 0 to 255 := 6;
        -- Ciclos de recuperação no reset (0 a 255; zero vale um ciclo).
        recovery_cycles : natural range 0 to 255 := 4;
        -- As interrupções do chip são ativas em nível alto quando verdadeiro.
        int_active_high : boolean := true
    );
    port (
        -- Clock do módulo.
        i_clk      : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst      : in    std_logic;
        -- Dado de escrita vindo do processador.
        i_data_in  : in    word_t;
        -- Endereço de palavra acessado pelo processador.
        i_address  : in    std_logic_vector(USB_ADDR_BITS - 1 downto 0);
        -- Pulso de escrita do processador.
        i_write    : in    std_logic;
        -- Pulso de leitura do processador.
        i_read     : in    std_logic;
        -- Dado de leitura para o processador.
        o_data_out : out   word_t;
        -- Requisição de interrupção, ativa em '1'.
        o_irq      : out   std_logic;

        -- Seleção do chip (OTG_CS_N), ativa em '0'.
        o_otg_cs_n    : out   std_logic;
        -- Leitura (OTG_RD_N), ativa em '0'.
        o_otg_rd_n    : out   std_logic;
        -- Escrita (OTG_WR_N), ativa em '0'.
        o_otg_wr_n    : out   std_logic;
        -- Reset do chip (OTG_RST_N), ativo em '0'.
        o_otg_rst_n   : out   std_logic;
        -- Endereço do chip (OTG_ADDR).
        o_otg_addr    : out   std_logic_vector(CHIP_ADDR_BITS - 1 downto 0);
        -- Dado que o SoC apresenta ao pino OTG_DATA.
        o_otg_data    : out   std_logic_vector(CHIP_DATA_BITS - 1 downto 0);
        -- Habilita a saída de OTG_DATA.
        o_otg_data_oe : out   std_logic;
        -- Valor do pino OTG_DATA.
        i_otg_data    : in    std_logic_vector(CHIP_DATA_BITS - 1 downto 0);
        -- Interrupções do chip (OTG_INT); uma placa com um só pino liga o bit 0 e deixa o 1 em inativo.
        i_otg_int     : in    std_logic_vector(1 downto 0);
        -- Pedido de DMA do controlador de dispositivo (OTG_DC_DREQ).
        i_otg_dreq    : in    std_logic;
        -- Reconhecimento de DMA do controlador de dispositivo (OTG_DC_DACK).
        o_otg_dack    : out   std_logic
    );
end entity usb_bridge;

architecture rtl of usb_bridge is

    -- Pedido de acesso ao mestre.
    signal start      : std_logic;
    -- Tipo do acesso.
    signal is_read    : std_logic;
    -- Porta do acesso.
    signal chip_port  : std_logic_vector(CHIP_ADDR_BITS - 1 downto 0);
    -- Dado a escrever.
    signal wdata      : std_logic_vector(CHIP_DATA_BITS - 1 downto 0);
    -- Campo de preparação.
    signal setup      : std_logic_vector(TIMING_FIELD_BITS - 1 downto 0);
    -- Campo do pulso.
    signal pulse      : std_logic_vector(TIMING_FIELD_BITS - 1 downto 0);
    -- Campo de recuperação.
    signal recovery   : std_logic_vector(TIMING_FIELD_BITS - 1 downto 0);
    -- Mestre ocupado.
    signal busy       : std_logic;
    -- Último dado lido.
    signal rdata      : std_logic_vector(CHIP_DATA_BITS - 1 downto 0);
    -- Dado do chip sincronizado.
    signal data_sync  : std_logic_vector(CHIP_DATA_BITS - 1 downto 0);
    -- Interrupções e DMA do chip, antes da sincronização.
    signal async_in   : std_logic_vector(2 downto 0);
    -- Interrupções e DMA do chip, sincronizados.
    signal sync_in    : std_logic_vector(2 downto 0);
    -- Reset do chip pedido pelo registrador de controle.
    signal chip_reset : std_logic;

begin

    async_in <= i_otg_dreq & i_otg_int;

    o_otg_rst_n <= not chip_reset;

    u_sync_data : entity work.synchronizer
        generic map (
            stages     => 2,
            data_width => CHIP_DATA_BITS
        )
        port map (
            i_clk => i_clk,
            i_rst => i_rst,
            i_d   => i_otg_data,
            o_d   => data_sync
        );

    u_sync_ctrl : entity work.synchronizer
        generic map (
            stages     => 2,
            data_width => 3
        )
        port map (
            i_clk => i_clk,
            i_rst => i_rst,
            i_d   => async_in,
            o_d   => sync_in
        );

    u_regs : entity work.usb_regs
        generic map (
            setup_cycles    => setup_cycles,
            pulse_cycles    => pulse_cycles,
            recovery_cycles => recovery_cycles,
            int_active_high => int_active_high
        )
        port map (
            i_clk        => i_clk,
            i_rst        => i_rst,
            i_data_in    => i_data_in,
            i_address    => i_address,
            i_write      => i_write,
            i_read       => i_read,
            o_data_out   => o_data_out,
            o_irq        => o_irq,
            o_start      => start,
            o_is_read    => is_read,
            o_port       => chip_port,
            o_wdata      => wdata,
            o_setup      => setup,
            o_pulse      => pulse,
            o_recovery   => recovery,
            i_busy       => busy,
            i_rdata      => rdata,
            i_int        => sync_in(1 downto 0),
            i_dreq       => sync_in(2),
            o_chip_reset => chip_reset,
            o_dack       => o_otg_dack
        );

    u_master : entity work.usb_bus_master
        port map (
            i_clk          => i_clk,
            i_rst          => i_rst,
            i_start        => start,
            i_is_read      => is_read,
            i_port         => chip_port,
            i_wdata        => wdata,
            i_setup        => setup,
            i_pulse        => pulse,
            i_recovery     => recovery,
            o_busy         => busy,
            o_rdata        => rdata,
            i_chip_data    => data_sync,
            o_cs_n         => o_otg_cs_n,
            o_rd_n         => o_otg_rd_n,
            o_wr_n         => o_otg_wr_n,
            o_chip_addr    => o_otg_addr,
            o_chip_data    => o_otg_data,
            o_chip_data_oe => o_otg_data_oe
        );

end architecture rtl;
