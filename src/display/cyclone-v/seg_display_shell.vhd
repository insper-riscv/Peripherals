-- =============================================================================
-- Registrador do display com a sua instância do Virtual JTAG
--
-- Só para a placa: usa o sld_virtual_jtag da Intel e por isso não é analisado
-- na simulação, onde o testbench faz o papel da instância e dirige seg_display
-- direto. O hospedeiro vê a instância de índice 2, ao lado da porta de debug da
-- SDRAM (0) e da UART (1), com registrador de instrução de 2 bits; a instrução 1
-- seleciona o registrador de 25 bits de seg_display e a instrução 2, o de 2 bits da
-- bandeira de falha.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity seg_display_shell is
	port (
		-- Clock do módulo.
		i_clk   : in  std_logic;
		-- Reset, ativo em '1'.
		i_rst   : in  std_logic;
		-- Endereço do acesso.
		i_address : in  std_logic_vector(7 downto 0);
		-- Dado de escrita.
		i_data_in : in  std_logic_vector(31 downto 0);
		-- Pulso de escrita ('1' = escreve).
		i_write   : in  std_logic;
		-- Dado lido.
		o_rdata : out std_logic_vector(31 downto 0);
		-- Segmentos dos seis displays, HEX0 nos bits 6:0 e HEX5 nos bits 41:36 (nível baixo).
		o_hex   : out std_logic_vector(41 downto 0);
		-- Valor de 24 bits guardado no registrador do display.
		o_value : out std_logic_vector(23 downto 0);
		-- Bandeira de falha gravada pelo hospedeiro ('1' = houve falha).
		o_fail  : out std_logic
	);
end entity seg_display_shell;

architecture rtl of seg_display_shell is

	-- Clock da cadeia JTAG.
	signal tck : std_logic;
	-- Dado serial vindo do hospedeiro.
	signal tdi : std_logic;
	-- Dado serial para o hospedeiro.
	signal tdo : std_logic;
	-- Registrador de instrução do Virtual JTAG.
	signal ir_in         : std_logic_vector(1 downto 0);
	-- Estado Capture-DR da cadeia virtual.
	signal st_cdr : std_logic;
	-- Estado Shift-DR da cadeia virtual.
	signal st_sdr : std_logic;
	-- Estado Update-DR da cadeia virtual.
	signal st_udr : std_logic;
	-- Estado Update-IR da cadeia virtual.
	signal st_uir : std_logic;

begin

	u_vjtag : entity work.virtual_jtag
		generic map (
			instance_index => 2,
			auto_instance_index => "NO",
			ir_width => 2
		)
		port map (
			o_tck => tck, o_tdi => tdi, i_tdo => tdo, o_ir_in => ir_in,
			o_state_cdr => st_cdr, o_state_sdr => st_sdr, o_state_udr => st_udr, o_state_uir => st_uir
		);

	u_display : entity work.seg_display
		port map (
			i_clk => i_clk, i_rst => i_rst, i_address => i_address, i_data_in => i_data_in,
			i_write => i_write, o_rdata => o_rdata,
			i_tck => tck, i_tdi => tdi, o_tdo => tdo, i_ir_in => ir_in,
			i_state_cdr => st_cdr, i_state_sdr => st_sdr, i_state_udr => st_udr, i_state_uir => st_uir,
			o_value => o_value, o_fail => o_fail, o_hex => o_hex
		);

end architecture rtl;
