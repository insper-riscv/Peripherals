-- =============================================================================
-- Constantes do MAC Ethernet
--
-- Endereços de palavra dos registradores, posições dos bits, constantes do
-- quadro Ethernet (preâmbulo, SFD, FCS, preenchimento e intervalo entre
-- quadros) e a função que avança o CRC-32 de um nibble. O CRC é o do IEEE 802.3
-- (polinômio refletido 0xEDB88320, valor inicial 0xFFFFFFFF), e um quadro
-- íntegro, FCS incluso, deixa o registrador em CRC_RESIDUE.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

package eth_consts is

    -- Largura em bits do endereço de palavra do barramento.
    constant ETH_ADDR_WIDTH : natural := 6;

    -- Registrador de controle.
    constant ADDR_CTRL         : std_logic_vector(ETH_ADDR_WIDTH - 1 downto 0) := "000000";
    -- Registrador de status (somente leitura).
    constant ADDR_STATUS       : std_logic_vector(ETH_ADDR_WIDTH - 1 downto 0) := "000001";
    -- Registrador de interrupções pendentes (escrever 1 limpa).
    constant ADDR_IRQ_STATUS   : std_logic_vector(ETH_ADDR_WIDTH - 1 downto 0) := "000010";
    -- Registrador de habilitação das interrupções.
    constant ADDR_IRQ_ENABLE   : std_logic_vector(ETH_ADDR_WIDTH - 1 downto 0) := "000011";
    -- Quatro primeiros octetos do endereço MAC.
    constant ADDR_MAC_LO       : std_logic_vector(ETH_ADDR_WIDTH - 1 downto 0) := "000100";
    -- Dois últimos octetos do endereço MAC.
    constant ADDR_MAC_HI       : std_logic_vector(ETH_ADDR_WIDTH - 1 downto 0) := "000101";
    -- Comprimento em bytes do quadro a enviar.
    constant ADDR_TX_LEN       : std_logic_vector(ETH_ADDR_WIDTH - 1 downto 0) := "000110";
    -- Comando de envio.
    constant ADDR_TX_CMD       : std_logic_vector(ETH_ADDR_WIDTH - 1 downto 0) := "000111";
    -- Porta de dados do buffer de envio, com autoincremento.
    constant ADDR_TX_DATA      : std_logic_vector(ETH_ADDR_WIDTH - 1 downto 0) := "001000";
    -- Comprimento em bytes do quadro recebido, zero sem quadro.
    constant ADDR_RX_LEN       : std_logic_vector(ETH_ADDR_WIDTH - 1 downto 0) := "001001";
    -- Porta de dados do buffer de recepção, com autoincremento.
    constant ADDR_RX_DATA      : std_logic_vector(ETH_ADDR_WIDTH - 1 downto 0) := "001010";
    -- Comando de recepção.
    constant ADDR_RX_CMD       : std_logic_vector(ETH_ADDR_WIDTH - 1 downto 0) := "001011";
    -- Comando do mestre MDIO.
    constant ADDR_MDIO_CMD     : std_logic_vector(ETH_ADDR_WIDTH - 1 downto 0) := "001100";
    -- Dado do mestre MDIO.
    constant ADDR_MDIO_DATA    : std_logic_vector(ETH_ADDR_WIDTH - 1 downto 0) := "001101";
    -- Contador de quadros enviados.
    constant ADDR_CNT_TX       : std_logic_vector(ETH_ADDR_WIDTH - 1 downto 0) := "010000";
    -- Contador de quadros recebidos e entregues.
    constant ADDR_CNT_RX       : std_logic_vector(ETH_ADDR_WIDTH - 1 downto 0) := "010001";
    -- Contador de quadros com erro de CRC.
    constant ADDR_CNT_CRC      : std_logic_vector(ETH_ADDR_WIDTH - 1 downto 0) := "010010";
    -- Contador de quadros com erro de PHY, de alinhamento ou curtos.
    constant ADDR_CNT_PHY      : std_logic_vector(ETH_ADDR_WIDTH - 1 downto 0) := "010011";
    -- Contador de quadros descartados por falta de espaço.
    constant ADDR_CNT_DROP     : std_logic_vector(ETH_ADDR_WIDTH - 1 downto 0) := "010100";
    -- Contador de quadros recusados pelo filtro de endereço.
    constant ADDR_CNT_FILTER   : std_logic_vector(ETH_ADDR_WIDTH - 1 downto 0) := "010101";

    -- Bit de CTRL que habilita o MAC.
    constant CTRL_ENABLE        : natural := 0;
    -- Bit de CTRL que aceita todo endereço de destino.
    constant CTRL_PROMISCUOUS   : natural := 1;
    -- Bit de CTRL que aceita o endereço de difusão.
    constant CTRL_BROADCAST     : natural := 2;
    -- Bit de CTRL que aceita endereços de grupo.
    constant CTRL_MULTICAST     : natural := 3;
    -- Bit de CTRL que entrega também quadros com erro.
    constant CTRL_ACCEPT_ERRORS : natural := 4;
    -- Bit de CTRL que reinicia o MAC (autolimpante).
    constant CTRL_SOFT_RESET    : natural := 5;
    -- Bit de CTRL que mantém o PHY em reset.
    constant CTRL_PHY_RESET     : natural := 6;

    -- Bit de STATUS: envio em andamento.
    constant STATUS_TX_BUSY    : natural := 0;
    -- Bit de STATUS: há quadro recebido no buffer.
    constant STATUS_RX_READY   : natural := 1;
    -- Bit de STATUS: transação MDIO em andamento.
    constant STATUS_MDIO_BUSY  : natural := 2;
    -- Bit de STATUS: nível da interrupção do PHY.
    constant STATUS_PHY_INT    : natural := 3;
    -- Bit de STATUS: o PHY não respondeu à última leitura MDIO.
    constant STATUS_MDIO_NOACK : natural := 4;

    -- Bit de IRQ: quadro recebido.
    constant IRQ_RX_FRAME  : natural := 0;
    -- Bit de IRQ: quadro enviado.
    constant IRQ_TX_DONE   : natural := 1;
    -- Bit de IRQ: erro de recepção ou de envio.
    constant IRQ_ERROR     : natural := 2;
    -- Bit de IRQ: transação MDIO concluída.
    constant IRQ_MDIO_DONE : natural := 3;
    -- Bit de IRQ: interrupção do PHY (nível).
    constant IRQ_PHY       : natural := 4;

    -- Valor inicial do CRC-32.
    constant CRC_INIT    : std_logic_vector(31 downto 0) := x"FFFFFFFF";
    -- Polinômio refletido do CRC-32 do Ethernet.
    constant CRC_POLY    : std_logic_vector(31 downto 0) := x"EDB88320";
    -- Valor do CRC depois de um quadro íntegro com FCS.
    constant CRC_RESIDUE : std_logic_vector(31 downto 0) := x"DEBB20E3";

    -- Nibble do preâmbulo.
    constant NIBBLE_PREAMBLE : std_logic_vector(3 downto 0) := "0101";
    -- Nibble alto do SFD (o baixo é igual ao do preâmbulo).
    constant NIBBLE_SFD_HIGH : std_logic_vector(3 downto 0) := "1101";
    -- Nibbles do preâmbulo mais o nibble baixo do SFD.
    constant PREAMBLE_NIBBLES : natural := 15;
    -- Tamanho mínimo do quadro sem FCS; abaixo disso o MAC preenche com zeros.
    constant MIN_PAYLOAD_BYTES : natural := 60;
    -- Tamanho mínimo do quadro recebido com FCS.
    constant MIN_RX_BYTES      : natural := 64;
    -- Bytes do FCS.
    constant FCS_BYTES         : natural := 4;
    -- Nibbles do FCS.
    constant FCS_NIBBLES       : natural := 8;
    -- Intervalo entre quadros em tempos de nibble (96 bits).
    constant GAP_NIBBLES       : natural := 24;
    -- Octetos do endereço de destino.
    constant MAC_BYTES         : natural := 6;

    -- Flag do quadro recebido: CRC incorreto.
    constant RXF_CRC     : natural := 0;
    -- Flag do quadro recebido: RX_ER do PHY durante o quadro.
    constant RXF_PHY     : natural := 1;
    -- Flag do quadro recebido: número ímpar de nibbles.
    constant RXF_ALIGN   : natural := 2;
    -- Flag do quadro recebido: menos de 64 bytes.
    constant RXF_RUNT    : natural := 3;
    -- Flag do quadro recebido: bytes perdidos na FIFO.
    constant RXF_OVERFLOW : natural := 4;
    -- Flag do quadro recebido: quadros ignorados antes deste.
    constant RXF_MISSED  : natural := 5;

    -- Avança o CRC-32 com um nibble, bit menos significativo primeiro.
    function crc32_nibble (
        crc    : std_logic_vector(31 downto 0);
        nibble : std_logic_vector(3 downto 0)
    ) return std_logic_vector;

end package eth_consts;

package body eth_consts is

    function crc32_nibble (
        crc    : std_logic_vector(31 downto 0);
        nibble : std_logic_vector(3 downto 0)
    ) return std_logic_vector is
        -- Estado do CRC durante os quatro passos de um bit.
        variable state : std_logic_vector(31 downto 0) := crc;
        -- Bit que decide a aplicação do polinômio.
        variable feedback : std_logic;
    begin
        for i in 0 to 3 loop
            feedback := state(0) xor nibble(i);
            state    := '0' & state(31 downto 1);
            if feedback = '1' then
                state := state xor CRC_POLY;
            end if;
        end loop;
        return state;
    end function crc32_nibble;

end package body eth_consts;
