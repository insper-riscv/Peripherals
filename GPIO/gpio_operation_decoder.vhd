-- =============================================================================
-- Decodificador de operações de um periférico GPIO mapeado em memória
--
-- Decodifica leituras e escritas em habilitações de escrita dos registradores, o
-- seletor da operação de saída e o seletor do multiplexador de leitura.
--
-- Mapa de bits do vetor de habilitações de escrita (wr_en):
--
--   bit 0  direção
--   bit 1  registrador de saída (carrega a palavra inteira)
--   bit 2  registrador de saída (liga, limpa ou inverte bits)
--   bit 3  máscara global de interrupção
--   bit 4  máscara de interrupção por borda de subida
--   bit 5  máscara de interrupção por borda de descida
--   bit 6  limpeza do status de interrupção na leitura do registrador de IRQ
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity gpio_operation_decoder is
  port (
    -- Endereço de palavra do acesso.
    i_address : in  std_logic_vector(3 downto 0);
    -- Pulso de escrita ('1' = escreve).
    i_write   : in  std_logic;
    -- Pulso de leitura ('1' = lê).
    i_read    : in  std_logic;

    -- Habilitações de escrita dos registradores (mapa de bits no cabeçalho).
    o_wr_en   : out std_logic_vector(6 downto 0);

    -- Operação do registrador de saída: 00 carrega, 01 liga, 10 limpa, 11 inverte.
    o_wr_op   : out std_logic_vector(1 downto 0);

    -- Seletor do multiplexador de leitura.
    o_rd_sel  : out std_logic_vector(2 downto 0)
  );
end entity gpio_operation_decoder;

architecture rtl of gpio_operation_decoder is

  -- ===========================================================================
  -- WRITE‑ENABLE VECTOR BIT MAP  (wr_en)
  -- ===========================================================================
  --   Bit : Purpose
  --   ----+------------------------------------------------------------
  --    0  | WR_DIR        – Direction register
  --    1  | WR_LOAD_OUT   – OUTPUT register (LOAD whole word)
  --    2  | WR_BIT_OUT    – OUTPUT register (SET / CLEAR / TOGGLE bits)
  --    3  | WR_IRQ_MASK   – Global interrupt‑enable mask
  --    4  | WR_RISE_MASK  – Rising‑edge interrupt mask
  --    5  | WR_FALL_MASK  – Falling‑edge interrupt mask
  --    6  | IRQ_STATUS_CLR    – Reset interrupt status on IRQ Register read
  -- ===========================================================================
  -- Posição, no vetor de habilitações, da escrita da direção.
  constant WR_DIR_I       : integer := 0;
  -- Posição da escrita que carrega a palavra de saída.
  constant WR_LOAD_OUT_I  : integer := 1;
  -- Posição da escrita que liga, limpa ou inverte bits de saída.
  constant WR_BIT_OUT_I   : integer := 2;
  -- Posição da escrita da máscara global de interrupção.
  constant WR_IRQ_MASK_I  : integer := 3;
  -- Posição da escrita da máscara de borda de subida.
  constant WR_RISE_MASK_I : integer := 4;
  -- Posição da escrita da máscara de borda de descida.
  constant WR_FALL_MASK_I : integer := 5;
  -- Posição da limpeza do status de interrupção na leitura do registrador de IRQ.
  constant IRQ_CLR_I   : integer := 6;

  -- ===========================================================================
  -- Direction Register
  -- ===========================================================================
  -- Endereço do registrador de direção.
  constant ADDR_DIR       : std_logic_vector(3 downto 0) := "0000";
  -- ===========================================================================
  -- Output Register
  -- ===========================================================================
  -- Endereço que carrega o registrador de saída.
  constant ADDR_OUT_LOAD  : std_logic_vector(3 downto 0) := "0001";
  -- Endereço que liga bits do registrador de saída.
  constant ADDR_OUT_SET   : std_logic_vector(3 downto 0) := "0010";
  -- Endereço que limpa bits do registrador de saída.
  constant ADDR_OUT_CLR   : std_logic_vector(3 downto 0) := "0011";
  -- Endereço que inverte bits do registrador de saída.
  constant ADDR_OUT_TGL   : std_logic_vector(3 downto 0) := "0100";
  -- ===========================================================================
  -- IRQ MASK Register
  -- ===========================================================================
  -- Endereço da máscara global de interrupção.
  constant ADDR_IRQ_MASK  : std_logic_vector(3 downto 0) := "0101";
  -- ===========================================================================
  -- IRQ Rising Edge Register
  -- ===========================================================================
  -- Endereço da máscara de borda de subida.
  constant ADDR_RISE_MASK : std_logic_vector(3 downto 0) := "0110";
  -- ===========================================================================
  -- IRQ Falling Edge Register
  -- ===========================================================================
  -- Endereço da máscara de borda de descida.
  constant ADDR_FALL_MASK : std_logic_vector(3 downto 0) := "0111";
  -- ===========================================================================
  -- IRQ Status Register
  -- ===========================================================================
  -- Endereço do status de interrupção.
  constant ADDR_IRQ_STAT  : std_logic_vector(3 downto 0) := "1000";
  -- ===========================================================================
  -- Read Synchronized Pins 
  -- ===========================================================================
  -- Endereço da leitura dos pinos sincronizados.
  constant ADDR_PINS      : std_logic_vector(3 downto 0) := "1001";

begin

  -- -----------------------------------------------------------------------------
  -- Decodificação de escrita:
  -- -----------------------------------------------------------------------------
  o_wr_en(WR_DIR_I)       <= i_write when i_address = ADDR_DIR       else '0';

  o_wr_en(WR_LOAD_OUT_I)  <= i_write when i_address = ADDR_OUT_LOAD  else '0';

  o_wr_en(WR_BIT_OUT_I)   <= i_write when i_address = ADDR_OUT_SET or
                                      i_address = ADDR_OUT_CLR or
                                      i_address = ADDR_OUT_TGL  else '0';

  o_wr_en(WR_IRQ_MASK_I)  <= i_write when i_address = ADDR_IRQ_MASK  else '0';
  o_wr_en(WR_RISE_MASK_I) <= i_write when i_address = ADDR_RISE_MASK else '0';
  o_wr_en(WR_FALL_MASK_I) <= i_write when i_address = ADDR_FALL_MASK else '0';
  o_wr_en(IRQ_CLR_I)   <= i_read when i_address = ADDR_IRQ_STAT   else '0';

  -- -----------------------------------------------------------------------------
  -- Operação de saída do GPIO: seletor do multiplexador (wr_op)
  -- -----------------------------------------------------------------------------
  with i_address select
    o_wr_op <= "00" when ADDR_OUT_LOAD,  -- carrega
             "01" when ADDR_OUT_SET,   -- liga
             "10" when ADDR_OUT_CLR,   -- limpa
             "11" when ADDR_OUT_TGL,   -- inverte
             "00" when others;            -- padrão (carrega)

  -- -----------------------------------------------------------------------------
  -- Operação de leitura do GPIO: seletor do multiplexador (rd_sel)
  -- -----------------------------------------------------------------------------
  with i_address select
    o_rd_sel <= "000" when ADDR_DIR,
              "001" when ADDR_OUT_LOAD,
              "001" when ADDR_OUT_SET,
              "001" when ADDR_OUT_CLR,
              "001" when ADDR_OUT_TGL,
              "010" when ADDR_PINS,
              "011" when ADDR_IRQ_STAT,
              "100" when ADDR_IRQ_MASK,
              "101" when ADDR_RISE_MASK,
              "110" when ADDR_FALL_MASK,
              "111" when others;

end architecture rtl;
