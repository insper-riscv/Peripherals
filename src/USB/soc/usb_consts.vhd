-- =============================================================================
-- Constantes da ponte paralela de 16 bits para o chip USB
--
-- Endereços de palavra dos registradores, posições dos bits e larguras dos
-- campos de temporização da ponte entre o barramento do SoC e o chip USB da
-- placa (controlador host e controlador de dispositivo, quatro portas de
-- acesso selecionadas por dois bits de endereço do chip).
-- =============================================================================

package usb_consts is

    -- Largura em bits do endereço de palavra local do periférico.
    constant USB_ADDR_BITS : natural := 4;
    -- Largura em bits do barramento de dados do chip.
    constant CHIP_DATA_BITS : natural := 16;
    -- Largura em bits do endereço do chip (seleciona uma das quatro portas de acesso).
    constant CHIP_ADDR_BITS : natural := 2;
    -- Largura em bits de cada campo de temporização, em ciclos de clock.
    constant TIMING_FIELD_BITS : natural := 8;

    -- Endereço de palavra da porta de dado do controlador host (endereço do chip 0).
    constant USB_ADDR_HC_DATA : natural := 0;
    -- Endereço de palavra da porta de comando do controlador host (endereço do chip 1).
    constant USB_ADDR_HC_CMD  : natural := 1;
    -- Endereço de palavra da porta de dado do controlador de dispositivo (endereço do chip 2).
    constant USB_ADDR_DC_DATA : natural := 2;
    -- Endereço de palavra da porta de comando do controlador de dispositivo (endereço do chip 3).
    constant USB_ADDR_DC_CMD  : natural := 3;
    -- Endereço de palavra do último dado lido do chip.
    constant USB_ADDR_RDATA   : natural := 4;
    -- Endereço de palavra do registrador de controle.
    constant USB_ADDR_CTRL    : natural := 5;
    -- Endereço de palavra do registrador de estado.
    constant USB_ADDR_STATUS  : natural := 6;
    -- Endereço de palavra da máscara de interrupção.
    constant USB_ADDR_IRQ_MASK : natural := 7;
    -- Endereço de palavra da temporização dos acessos.
    constant USB_ADDR_TIMING  : natural := 8;

    -- Bit de CTRL que mantém o chip em reset.
    constant USB_CTRL_CHIP_RESET : natural := 0;
    -- Bit de CTRL que ativa o reconhecimento de DMA do controlador de dispositivo.
    constant USB_CTRL_DACK       : natural := 1;

    -- Bit de STATUS com o nível da interrupção 0 do chip (já na polaridade ativa em '1').
    constant USB_STATUS_INT0  : natural := 0;
    -- Bit de STATUS com o nível da interrupção 1 do chip (já na polaridade ativa em '1').
    constant USB_STATUS_INT1  : natural := 1;
    -- Bit de STATUS com o pedido de DMA do controlador de dispositivo.
    constant USB_STATUS_DREQ  : natural := 2;
    -- Bit de STATUS que indica acesso ao chip em andamento.
    constant USB_STATUS_BUSY  : natural := 3;
    -- Bit de STATUS pegajoso: acesso pedido com a ponte ocupada e descartado (escrever 1 limpa).
    constant USB_STATUS_ERROR : natural := 4;

end package usb_consts;
