-- =============================================================================
-- Decodificador de operações de um temporizador e PWM mapeado em memória
--
-- Decodifica leituras e escritas em habilitações de escrita one-hot, um seletor
-- da entrada do contador e um seletor do multiplexador de leitura.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity timer_operation_decoder is
  port (
    -- Endereço de palavra de 3 bits vindo do processador.
    i_address : in  std_logic_vector(2 downto 0);
    -- Pulso de escrita ('1' = escreve).
    i_write   : in  std_logic;
    -- Pulso de leitura ('1' = lê).
    i_read    : in  std_logic;

    -- Habilitações de escrita dos registradores, one-hot.
    o_wr_en   : out std_logic_vector(6 downto 0);

    -- Seletor da entrada do contador: o barramento só quando se carrega.
    o_cnt_sel : out std_logic;

    -- Seletor do multiplexador de leitura.
    o_rd_sel  : out std_logic_vector(2 downto 0)
  );
end entity timer_operation_decoder;

architecture rtl of timer_operation_decoder is

  -- ===========================================================================
  -- WRITE-ENABLE VECTOR BIT MAP  (wr_en)
  -- ===========================================================================
  --   Bit : Purpose
  --   ----+------------------------------------------------------------
  --    0  | WR_CONFIG      – Config register (start / mode / pwm_en / irq_mask)
  --    1  | WR_LOAD_TIMER  – Load current counter value
  --    2  | WR_RESET       – Reset the timer
  --    3  | WR_LOAD_TOP    – Load TOP register
  --    4  | WR_LOAD_DUTY   – Load DUTY-CYCLE register
  --    5  | WR_OVF_CLR     – Read-to-clear overflow status (pulse on read)
  --    6  | WR_PRESCALER   – Load prescaler value 
  -- ===========================================================================
  -- Posição da escrita do registrador de configuração.
  constant WR_CONFIG_I     : integer := 0;
  -- Posição da escrita que carrega o contador.
  constant WR_LOAD_TIMER_I : integer := 1;
  -- Posição da escrita que zera o contador.
  constant WR_RESET_I      : integer := 2;
  -- Posição da escrita do valor de topo.
  constant WR_LOAD_TOP_I   : integer := 3;
  -- Posição da escrita do ciclo de trabalho.
  constant WR_LOAD_DUTY_I  : integer := 4;
  -- Posição da limpeza do status de overflow.
  constant WR_OVF_CLR_I    : integer := 5;
  -- Posição da escrita do prescaler.
  constant WR_PRESCALER    : integer := 6;

  -- ===========================================================================
  -- Configuration Register
  -- ===========================================================================
  -- Endereço do registrador de configuração.
  constant ADDR_CONFIG      : std_logic_vector(2 downto 0) := "000";
  -- ===========================================================================
  -- Registrador do contador
  -- ===========================================================================
  -- Endereço que carrega o contador.
  constant ADDR_TIMER_LOAD  : std_logic_vector(2 downto 0) := "001";
  -- Endereço que zera o contador.
  constant ADDR_TIMER_RESET : std_logic_vector(2 downto 0) := "010";
  -- ===========================================================================
  -- TOP Register
  -- ===========================================================================
  -- Endereço do valor de topo.
  constant ADDR_TOP         : std_logic_vector(2 downto 0) := "011";
  -- ===========================================================================
  -- DUTY-CYCLE Register
  -- ===========================================================================
  -- Endereço do ciclo de trabalho.
  constant ADDR_DUTY_CYCLE  : std_logic_vector(2 downto 0) := "100";
  -- ===========================================================================
  -- Overflow Status Flag
  --   Read-to-clear overflow status (pulse aligned with the READ)
  -- ===========================================================================
  -- Endereço do status de overflow.
  constant ADDR_OVF_STATUS  : std_logic_vector(2 downto 0) := "101";
  -- ===========================================================================
  -- PWM Output
  -- ===========================================================================
  -- Endereço da leitura do PWM.
  constant ADDR_PWM         : std_logic_vector(2 downto 0) := "110";
  -- ===========================================================================
  -- Registrador do prescaler
  -- ===========================================================================
  -- Endereço do prescaler.
  constant ADDR_PRESCALER   : std_logic_vector(2 downto 0) := "111";

begin

  -- -----------------------------------------------------------------------------
  -- Decodificação de escrita: pulsos de habilitação de um ciclo
  -- -----------------------------------------------------------------------------
  o_wr_en(WR_CONFIG_I)     <= i_write when i_address = ADDR_CONFIG      else '0';
  o_wr_en(WR_LOAD_TIMER_I) <= i_write when i_address = ADDR_TIMER_LOAD  else '0';
  o_wr_en(WR_RESET_I)      <= i_write when i_address = ADDR_TIMER_RESET else '0';
  o_wr_en(WR_LOAD_TOP_I)   <= i_write when i_address = ADDR_TOP         else '0';
  o_wr_en(WR_LOAD_DUTY_I)  <= i_write when i_address = ADDR_DUTY_CYCLE  else '0';
  o_wr_en(WR_PRESCALER)    <= i_write when i_address = ADDR_PRESCALER   else '0';

  -- Limpeza do overflow na leitura (pulso alinhado com a leitura)
  o_wr_en(WR_OVF_CLR_I)    <= i_read  when i_address = ADDR_OVF_STATUS  else '0';

  -- -----------------------------------------------------------------------------
  -- Seletor da entrada do contador (cnt_sel)
  -- 0 = usa contador + 1
  -- 1 = carrega o valor externo (WR_LOAD_TIMER)
  -- -----------------------------------------------------------------------------
  o_cnt_sel <= '1' when (i_address = ADDR_TIMER_LOAD and i_write = '1') else '0';

  -- -----------------------------------------------------------------------------
  -- Leitura: seletor do multiplexador (rd_sel)
  -- -----------------------------------------------------------------------------
  with i_address select
    o_rd_sel <= "000" when ADDR_TIMER_LOAD,     -- 000 = contador atual
              "000" when ADDR_TIMER_RESET,    -- 000 = contador atual
              "001" when ADDR_TOP,            -- 001 = registrador de topo
              "010" when ADDR_DUTY_CYCLE,     -- 010 = ciclo de trabalho
              "011" when ADDR_CONFIG,         -- 011 = configuração
              "100" when ADDR_PWM,            -- 100 = saída PWM
              "101" when ADDR_OVF_STATUS,     -- 101 = status de overflow (limpa na leitura)
              "110" when ADDR_PRESCALER,      -- 110 = prescaler
              "111" when others;              -- 111 = reservado

end architecture;
