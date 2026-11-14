-- =============================================================================
-- Registradores próprios do HDMI (lado do processador)
--
-- Domínio do clock do sistema. Complementa os registradores do periférico de
-- vídeo (controle, estado do quadro, geometria, formato, paleta e framebuffer)
-- com as palavras 8 a 14 do espaço de registradores, no mesmo endereçamento
-- (a janela do framebuffer é a metade alta do espaço de endereços e as palavras
-- de 15 a 255 leem zero):
--   8  modo (L): bits 7:0 número do modo CEA-861 do generic mode_id, bit 8
--      sincronismo horizontal positivo, bit 9 sincronismo vertical positivo;
--   9  estado (L): bit 0 pino de interrupção do transmissor ativo, bit 1
--      sequenciador ocupado, bit 2 sequenciador concluído, bit 3 alguma
--      escrita sem confirmação, bit 4 sequenciador presente;
--   10 habilitação das interrupções (L/E): bit 0 fim de quadro, bit 1
--      ativação do pino de interrupção do transmissor;
--   11 interrupções pendentes (L/E1C): mesmos bits; escrever 1 limpa o bit,
--      e um evento no mesmo ciclo da limpeza vence a limpeza;
--   12 controle do sequenciador (E): escrever 1 no bit 0 reinicia a tabela de
--      inicialização se o sequenciador estiver parado; a leitura vale zero;
--   13 contador do sequenciador (L): bits 7:0 entradas concluídas, 15:8
--      escritas sem confirmação, 23:16 entradas da tabela;
--   14 clock de pixel do modo em kHz (L).
--
-- O evento de fim de quadro é a borda de subida de i_vblank (a primeira linha
-- depois da última visível) e o de interrupção do transmissor é a borda de
-- ativação do pino. A leitura é combinacional no endereço, sem efeito
-- colateral. O reset síncrono zera os registradores de escrita e as pendências.
-- A saída o_irq é o OU das pendências habilitadas, em nível.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.utils_pkg.all;
use work.video_consts.all;
use work.hdmi_consts.all;

entity hdmi_regs is
    generic (
        -- Largura do endereço de palavra da janela do periférico.
        addr_width      : positive := 16;
        -- Número do modo CEA-861 (VIC) da instância, ou zero para um modo próprio.
        mode_id         : natural  := 0;
        -- Clock de pixel do modo em kHz.
        pixel_clock_khz : natural  := 74250;
        -- Polaridade do sincronismo horizontal: verdadeiro = nível alto durante o pulso.
        h_sync_positive : boolean  := true;
        -- Polaridade do sincronismo vertical: verdadeiro = nível alto durante o pulso.
        v_sync_positive : boolean  := true;
        -- Entradas da tabela de inicialização do transmissor.
        init_entries    : natural  := 0;
        -- O sequenciador de inicialização existe nesta instância.
        init_enable     : boolean  := true
    );
    port (
        -- Clock do sistema.
        i_clk        : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst        : in    std_logic;

        -- Dado de escrita vindo do processador.
        i_data_in    : in    std_logic_vector(31 downto 0);
        -- Endereço de palavra dentro do periférico.
        i_address    : in    std_logic_vector(addr_width - 1 downto 0);
        -- Pulso de escrita do processador ('1' = escreve).
        i_write      : in    std_logic;
        -- Dado de leitura (zero fora das palavras 8 a 14).
        o_data_out   : out   std_logic_vector(31 downto 0);

        -- Apagamento vertical em nível alto, já sincronizado em i_clk.
        i_vblank     : in    std_logic;
        -- Pino de interrupção do transmissor ativo, já sincronizado em i_clk.
        i_int_active : in    std_logic;
        -- Sequenciador ocupado.
        i_seq_busy   : in    std_logic;
        -- Sequenciador concluído.
        i_seq_done   : in    std_logic;
        -- Alguma escrita da sequência sem confirmação.
        i_seq_nack   : in    std_logic;
        -- Entradas concluídas pelo sequenciador.
        i_seq_sent   : in    std_logic_vector(7 downto 0);
        -- Escritas sem confirmação contadas pelo sequenciador.
        i_seq_nacks  : in    std_logic_vector(7 downto 0);

        -- Pulso de um ciclo que reinicia o sequenciador.
        o_seq_start  : out   std_logic;
        -- Interrupção em nível: alguma pendência habilitada.
        o_irq        : out   std_logic
    );
end entity hdmi_regs;

architecture rtl of hdmi_regs is

    -- Número de bits das duas interrupções.
    constant IRQ_BITS : positive := 2;

    -- Habilitação das interrupções.
    signal irq_en      : std_logic_vector(IRQ_BITS - 1 downto 0) := (others => '0');
    -- Interrupções pendentes.
    signal irq_pend    : std_logic_vector(IRQ_BITS - 1 downto 0) := (others => '0');
    -- Valor anterior de i_vblank, para a borda de subida.
    signal vblank_prev : std_logic                               := '0';
    -- Valor anterior de i_int_active, para a borda de ativação.
    signal int_prev    : std_logic                               := '0';
    -- Pulso de reinício do sequenciador.
    signal seq_start_q : std_logic                               := '0';
    -- Eventos do ciclo: fim de quadro e ativação do pino.
    signal events      : std_logic_vector(IRQ_BITS - 1 downto 0);
    -- Bits de pendência que a escrita atual limpa.
    signal clear_mask  : std_logic_vector(IRQ_BITS - 1 downto 0);

    -- Palavra dentro do espaço de registradores.
    signal space_idx : natural range 0 to 2 ** REG_SPACE_BITS - 1;
    -- O endereço está no espaço de registradores (fora da janela do framebuffer e abaixo da paleta).
    signal hit       : std_logic;

begin

    assert addr_width > REG_SPACE_BITS
        report "hdmi_regs: addr_width deve conter o espaço de registradores"
        severity failure;

    hit       <= '1' when i_address(addr_width - 1) = '0'
                          and unsigned(i_address(addr_width - 2 downto REG_SPACE_BITS)) = 0 else '0';
    space_idx <= to_integer(unsigned(i_address(REG_SPACE_BITS - 1 downto 0)));

    events(IRQ_FRAME_BIT) <= i_vblank and not vblank_prev;
    events(IRQ_INT_BIT)   <= i_int_active and not int_prev;

    o_seq_start <= seq_start_q;
    o_irq       <= to_sl((irq_pend and irq_en) /= (IRQ_BITS - 1 downto 0 => '0'));

    -- Leitura combinacional dos registradores do HDMI.
    p_read : process (hit, space_idx, i_int_active, i_seq_busy, i_seq_done, i_seq_nack, irq_en, irq_pend,
                      i_seq_sent, i_seq_nacks) is
    begin

        o_data_out <= (others => '0');

        if hit = '1' then
            case space_idx is
                when ADDR_HDMI_MODE =>
                    o_data_out(7 downto 0) <= std_logic_vector(to_unsigned(mode_id mod 256, 8));
                    o_data_out(8)          <= to_sl(h_sync_positive);
                    o_data_out(9)          <= to_sl(v_sync_positive);
                when ADDR_HDMI_STATUS =>
                    o_data_out(STATUS_INT_BIT)  <= i_int_active;
                    o_data_out(STATUS_BUSY_BIT) <= i_seq_busy;
                    o_data_out(STATUS_DONE_BIT) <= i_seq_done;
                    o_data_out(STATUS_NACK_BIT) <= i_seq_nack;
                    o_data_out(STATUS_INIT_BIT) <= to_sl(init_enable);
                when ADDR_HDMI_IRQ_EN =>
                    o_data_out(IRQ_BITS - 1 downto 0) <= irq_en;
                when ADDR_HDMI_IRQ_PEND =>
                    o_data_out(IRQ_BITS - 1 downto 0) <= irq_pend;
                when ADDR_HDMI_SEQ_COUNT =>
                    o_data_out(7 downto 0)   <= i_seq_sent;
                    o_data_out(15 downto 8)  <= i_seq_nacks;
                    o_data_out(23 downto 16) <= std_logic_vector(to_unsigned(init_entries, 8));
                when ADDR_HDMI_PIXEL_KHZ =>
                    o_data_out <= std_logic_vector(to_unsigned(pixel_clock_khz, 32));
                when others =>
                    null;
            end case;
        end if;

    end process p_read;

    -- Bits de pendência que a escrita atual limpa.
    clear_mask <= i_data_in(IRQ_BITS - 1 downto 0)
                  when (i_write = '1' and hit = '1' and space_idx = ADDR_HDMI_IRQ_PEND)
                  else (others => '0');

    p_write : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            vblank_prev <= i_vblank;
            int_prev    <= i_int_active;
            seq_start_q <= '0';

            if i_write = '1' and hit = '1' then
                case space_idx is
                    when ADDR_HDMI_IRQ_EN =>
                        irq_en <= i_data_in(IRQ_BITS - 1 downto 0);
                    when ADDR_HDMI_SEQ_CTRL =>
                        seq_start_q <= to_sl(init_enable) and i_data_in(0);
                    when others =>
                        null;
                end case;
            end if;

            -- Um evento no mesmo ciclo da limpeza vence a limpeza.
            irq_pend <= (irq_pend and not clear_mask) or events;

            if i_rst = '1' then
                irq_en      <= (others => '0');
                irq_pend    <= (others => '0');
                vblank_prev <= '0';
                int_prev    <= '0';
                seq_start_q <= '0';
            end if;
        end if;

    end process p_write;

end architecture rtl;
