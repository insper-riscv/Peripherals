-- =============================================================================
-- Mouse PS/2 mapeado em memória (um canal PS/2)
--
-- Liga o decodificador de protocolo (ps2_mouse_decoder) a dois acumuladores
-- de deslocamento com saturação e a registradores de status, expondo o mouse
-- como periférico de barramento. A entidade fala bytes com o ps2_host (camada
-- física), de modo que cada instância atende um único canal e não compartilha
-- estado com outra instância.
--
-- Registradores (endereço de palavra, acessos de 32 bits):
--   0 STATUS   (leitura) bit 0 pacote novo, bit 1 estouro, bit 2 erro, bit 3
--              mouse em streaming. Os bits 0 a 2 são limpos pela leitura; o
--              bit 3 é o nível atual.
--   1 DX       (leitura) deslocamento acumulado em X, 16 bits em complemento
--              de dois com extensão de sinal; a leitura zera o acumulador.
--   2 DY       (leitura) deslocamento acumulado em Y (positivo para cima),
--              com o mesmo formato e a mesma limpeza de DX.
--   3 BUTTONS  (leitura) bit 0 esquerdo, bit 1 direito, bit 2 meio, nível do
--              último pacote.
--   4 CONTROL  (leitura e escrita) bit 0 habilita a interrupção; a escrita de
--              '1' no bit 1 reinicia o mouse (lê sempre zero).
--   5 a 7      leem zero e ignoram a escrita.
-- A interrupção o_irq vale '1' enquanto o bit de pacote novo estiver ligado e
-- a interrupção habilitada, e cai com a leitura do STATUS. O bit de estouro
-- liga quando o pacote traz estouro de eixo ou um acumulador satura.
-- Um pacote que chega no mesmo ciclo da leitura de um registrador não se
-- perde: o valor lido é o anterior e o novo fica acumulado ou sinalizado.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.ps2_mouse_consts.all;

entity ps2_mouse is
    generic (
        -- Largura do barramento de dados em bits.
        data_width            : integer  := 32;
        -- Ciclos de clock sem resposta aceitos durante a inicialização.
        init_timeout_cycles   : positive := 100_000_000;
        -- Ciclos de clock sem byte aceitos no meio de um pacote.
        packet_timeout_cycles : positive := 5_000_000
    );
    port (
        -- Clock do módulo.
        i_clk          : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst          : in    std_logic;
        -- Dado de escrita vindo do processador.
        i_data_in      : in    std_logic_vector(data_width - 1 downto 0);
        -- Endereço de palavra de 3 bits vindo do processador.
        i_address      : in    std_logic_vector(2 downto 0);
        -- Pulso de escrita do processador ('1' = escreve).
        i_write        : in    std_logic;
        -- Pulso de leitura do processador ('1' = lê e limpa o que a leitura limpa).
        i_read         : in    std_logic;
        -- Dado de leitura para o processador.
        o_data_out     : out   std_logic_vector(data_width - 1 downto 0);
        -- Requisição de interrupção, ativa em '1'.
        o_irq          : out   std_logic;
        -- Byte recebido do ps2_host.
        i_rx_data      : in    std_logic_vector(7 downto 0);
        -- Pulso de byte recebido válido do ps2_host.
        i_rx_valid     : in    std_logic;
        -- Pulso de erro de paridade ou de quadro do ps2_host.
        i_rx_error     : in    std_logic;
        -- Byte a enviar ao ps2_host.
        o_tx_data      : out   std_logic_vector(7 downto 0);
        -- Pulso de envio ao ps2_host (um ciclo, só com i_tx_ready em '1').
        o_tx_valid     : out   std_logic;
        -- O ps2_host aceita um byte novo ('1' = pronto).
        i_tx_ready     : in    std_logic
    );
end entity ps2_mouse;

architecture rtl of ps2_mouse is

    -- Seletor do multiplexador de leitura.
    signal rd_sel          : std_logic_vector(2 downto 0);
    -- Leitura do STATUS em curso.
    signal status_read     : std_logic;
    -- Leitura de DX em curso.
    signal dx_read         : std_logic;
    -- Leitura de DY em curso.
    signal dy_read         : std_logic;
    -- Escrita do CONTROL em curso.
    signal control_write   : std_logic;
    -- Pulso que reinicia o mouse, vindo da escrita de '1' no bit de reinicialização.
    signal restart         : std_logic;

    -- O mouse está em streaming.
    signal streaming       : std_logic;
    -- Pulso de pacote completo do decodificador.
    signal packet_valid    : std_logic;
    -- Botões do último pacote.
    signal buttons         : std_logic_vector(2 downto 0);
    -- Deslocamento X do pacote, 9 bits.
    signal packet_dx       : std_logic_vector(DELTA_WIDTH - 1 downto 0);
    -- Deslocamento Y do pacote, 9 bits.
    signal packet_dy       : std_logic_vector(DELTA_WIDTH - 1 downto 0);
    -- O pacote trouxe estouro de eixo.
    signal packet_overflow : std_logic;
    -- Pulso de erro de protocolo do decodificador.
    signal packet_error    : std_logic;

    -- Acumulador de X.
    signal acc_dx          : std_logic_vector(ACC_WIDTH - 1 downto 0);
    -- Acumulador de Y.
    signal acc_dy          : std_logic_vector(ACC_WIDTH - 1 downto 0);
    -- O acumulador de X saturou neste ciclo.
    signal sat_dx          : std_logic;
    -- O acumulador de Y saturou neste ciclo.
    signal sat_dy          : std_logic;

    -- Evento que liga o bit de estouro.
    signal overflow_event  : std_logic;
    -- Limpeza do bit de pacote novo (leitura do STATUS sem pacote simultâneo).
    signal new_clear       : std_logic;
    -- Limpeza do bit de estouro.
    signal overflow_clear  : std_logic;
    -- Limpeza do bit de erro.
    signal error_clear     : std_logic;
    -- Bit de pacote novo, em formato de vetor.
    signal new_q           : std_logic_vector(0 downto 0);
    -- Bit de estouro, em formato de vetor.
    signal overflow_q      : std_logic_vector(0 downto 0);
    -- Bit de erro, em formato de vetor.
    signal error_q         : std_logic_vector(0 downto 0);
    -- Habilitação da interrupção, em formato de vetor.
    signal irq_enable_q    : std_logic_vector(0 downto 0);
    -- Clear do registrador de controle (reset).
    signal control_clear   : std_logic;

    -- Palavras de leitura de cada registrador.
    signal status_word     : std_logic_vector(data_width - 1 downto 0);
    -- Leitura de DX com extensão de sinal.
    signal dx_word         : std_logic_vector(data_width - 1 downto 0);
    -- Leitura de DY com extensão de sinal.
    signal dy_word         : std_logic_vector(data_width - 1 downto 0);
    -- Leitura de BUTTONS.
    signal buttons_word    : std_logic_vector(data_width - 1 downto 0);
    -- Leitura de CONTROL.
    signal control_word    : std_logic_vector(data_width - 1 downto 0);

    -- Palavra de zeros.
    constant ZERO_WORD : std_logic_vector(data_width - 1 downto 0) := (others => '0');
    -- Operando de 1 bit com valor '1', dado dos bits de status.
    constant ONE_BIT   : std_logic_vector(0 downto 0)              := "1";

begin

    restart       <= control_write and i_data_in(CTRL_REINIT_BIT);
    overflow_event <= packet_valid and (packet_overflow or sat_dx or sat_dy);
    -- Um evento no mesmo ciclo da leitura vence a limpeza.
    new_clear      <= i_rst or (status_read and not packet_valid);
    overflow_clear <= i_rst or (status_read and not overflow_event);
    error_clear    <= i_rst or (status_read and not packet_error);
    control_clear  <= i_rst;

    status_word  <= ZERO_WORD(data_width - 1 downto 4) & streaming & error_q & overflow_q & new_q;
    dx_word      <= std_logic_vector(resize(signed(acc_dx), data_width));
    dy_word      <= std_logic_vector(resize(signed(acc_dy), data_width));
    buttons_word <= ZERO_WORD(data_width - 1 downto 3) & buttons;
    control_word <= ZERO_WORD(data_width - 1 downto 1) & irq_enable_q;

    o_irq <= irq_enable_q(0) and new_q(0);

    -------------------------------------------------------------------------------
    -- Decodificador de operações do barramento
    -------------------------------------------------------------------------------
    u_operation_decoder : entity work.ps2_mouse_operation_decoder
        port map (
            i_address       => i_address,
            i_write         => i_write,
            i_read          => i_read,
            o_rd_sel        => rd_sel,
            o_status_read   => status_read,
            o_dx_read       => dx_read,
            o_dy_read       => dy_read,
            o_control_write => control_write
        );

    -------------------------------------------------------------------------------
    -- Decodificador do protocolo do mouse
    -------------------------------------------------------------------------------
    u_decoder : entity work.ps2_mouse_decoder
        generic map (
            init_timeout_cycles   => init_timeout_cycles,
            packet_timeout_cycles => packet_timeout_cycles
        )
        port map (
            i_clk          => i_clk,
            i_rst          => i_rst,
            i_restart      => restart,
            i_rx_data      => i_rx_data,
            i_rx_valid     => i_rx_valid,
            i_rx_error     => i_rx_error,
            o_tx_data      => o_tx_data,
            o_tx_valid     => o_tx_valid,
            i_tx_ready     => i_tx_ready,
            o_streaming    => streaming,
            o_packet_valid => packet_valid,
            o_buttons      => buttons,
            o_dx           => packet_dx,
            o_dy           => packet_dy,
            o_overflow     => packet_overflow,
            o_error        => packet_error
        );

    -------------------------------------------------------------------------------
    -- Acumuladores de deslocamento, um por eixo
    -------------------------------------------------------------------------------
    u_acc_x : entity work.ps2_axis_accumulator
        generic map (
            acc_width   => ACC_WIDTH,
            delta_width => DELTA_WIDTH
        )
        port map (
            i_clk       => i_clk,
            i_rst       => i_rst,
            i_clear     => dx_read,
            i_add_valid => packet_valid,
            i_delta     => packet_dx,
            o_value     => acc_dx,
            o_saturated => sat_dx
        );

    u_acc_y : entity work.ps2_axis_accumulator
        generic map (
            acc_width   => ACC_WIDTH,
            delta_width => DELTA_WIDTH
        )
        port map (
            i_clk       => i_clk,
            i_rst       => i_rst,
            i_clear     => dy_read,
            i_add_valid => packet_valid,
            i_delta     => packet_dy,
            o_value     => acc_dy,
            o_saturated => sat_dy
        );

    -------------------------------------------------------------------------------
    -- Bits de status: ligam no evento e desligam na leitura do STATUS
    -------------------------------------------------------------------------------
    u_new_flag : entity work.clearable_register
        generic map (
            data_width => 1
        )
        port map (
            i_clk    => i_clk,
            i_clear  => new_clear,
            i_enable => packet_valid,
            i_d      => ONE_BIT,
            o_d      => new_q
        );

    u_overflow_flag : entity work.clearable_register
        generic map (
            data_width => 1
        )
        port map (
            i_clk    => i_clk,
            i_clear  => overflow_clear,
            i_enable => overflow_event,
            i_d      => ONE_BIT,
            o_d      => overflow_q
        );

    u_error_flag : entity work.clearable_register
        generic map (
            data_width => 1
        )
        port map (
            i_clk    => i_clk,
            i_clear  => error_clear,
            i_enable => packet_error,
            i_d      => ONE_BIT,
            o_d      => error_q
        );

    -------------------------------------------------------------------------------
    -- Habilitação da interrupção (bit 0 do CONTROL)
    -------------------------------------------------------------------------------
    u_irq_enable : entity work.clearable_register
        generic map (
            data_width => 1
        )
        port map (
            i_clk    => i_clk,
            i_clear  => control_clear,
            i_enable => control_write,
            i_d      => i_data_in(CTRL_IRQ_EN_BIT downto CTRL_IRQ_EN_BIT),
            o_d      => irq_enable_q
        );

    -------------------------------------------------------------------------------
    -- Seletor do dado de leitura
    -------------------------------------------------------------------------------
    u_read_mux : entity work.mux_8x1
        generic map (
            data_width => data_width
        )
        port map (
            i_d0  => status_word,
            i_d1  => dx_word,
            i_d2  => dy_word,
            i_d3  => buttons_word,
            i_d4  => control_word,
            i_d5  => ZERO_WORD,
            i_d6  => ZERO_WORD,
            i_d7  => ZERO_WORD,
            i_sel => rd_sel,
            o_d   => o_data_out
        );

end architecture rtl;
