-- =============================================================================
-- Constantes do PLIC
--
-- Endereços de palavra (deslocamento em palavras dentro do periférico) dos
-- registradores do PLIC de um hart e um contexto (modo máquina), no leiaute da
-- especificação RISC-V PLIC 1.0.0, e a função que dimensiona o campo do
-- identificador de fonte.
-- =============================================================================

package plic_consts is

  -- Menor largura em bits do endereço de palavra que cobre o mapa (janela de 0x200008 bytes).
  constant PLIC_MIN_ADDR_WIDTH : natural := 20;
  -- Maior número de fontes que a especificação admite.
  constant PLIC_MAX_SOURCES    : natural := 1023;
  -- Endereço de palavra da primeira palavra de pendência (deslocamento 0x1000 em bytes).
  constant ADDR_PENDING_BASE   : natural := 16#400#;
  -- Endereço de palavra da primeira palavra de habilitação do contexto 0 (deslocamento 0x2000 em bytes).
  constant ADDR_ENABLE_BASE    : natural := 16#800#;
  -- Endereço de palavra do limiar do contexto 0 (deslocamento 0x200000 em bytes).
  constant ADDR_THRESHOLD      : natural := 16#80000#;
  -- Endereço de palavra do claim/complete do contexto 0 (deslocamento 0x200004 em bytes).
  constant ADDR_CLAIM_COMPLETE : natural := 16#80001#;

  -- Número de bits que representa os identificadores de 0 a sources.
  function id_bits(sources : positive) return positive;

end package plic_consts;

package body plic_consts is

  function id_bits(sources : positive) return positive is
    -- Número de bits já contado.
    variable width : positive := 1;
  begin
    while 2 ** width <= sources loop
      width := width + 1;
    end loop;
    return width;
  end function id_bits;

end package body plic_consts;
