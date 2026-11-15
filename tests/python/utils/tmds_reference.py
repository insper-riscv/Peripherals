"""Modelo de referência da codificação TMDS do DVI 1.0.

O codificador do modelo segue a especificação em passos separados
(minimização de transições e balanceamento), e o decodificador faz o
caminho inverso, de modo que o teste confere o símbolo do hardware e
também que ele devolve o byte original.
"""

from dataclasses import dataclass

BYTE_BITS = 8
TOKEN_BITS = 10
CONTROL_TOKENS = {
    0b00: 0b1101010100,
    0b01: 0b0010101011,
    0b10: 0b0101010100,
    0b11: 0b1010101011,
}
CLOCK_TOKEN = 0b1111100000
BYTE_MASK = 0xFF


def ones(value: int) -> int:
    """Conte os bits em 1 de um inteiro.

    Parameters
    ----------
    value : int
        Valor não negativo.

    Returns
    -------
    int
        Quantidade de bits em 1.
    """
    return value.bit_count()


def minimize(byte: int) -> int:
    """Faça a etapa de minimização de transições.

    Parameters
    ----------
    byte : int
        Byte de pixel.

    Returns
    -------
    int
        Os nove bits da etapa, com o bit 8 marcando XOR.
    """
    use_xnor = ones(byte) > BYTE_BITS // 2 or (
        ones(byte) == BYTE_BITS // 2 and not byte & 1
    )
    q_m = byte & 1
    for i in range(1, BYTE_BITS):
        previous = (q_m >> (i - 1)) & 1
        bit = (byte >> i) & 1
        value = 1 - (previous ^ bit) if use_xnor else previous ^ bit
        q_m |= value << i
    return q_m | (0 if use_xnor else 1 << BYTE_BITS)


def decode(token: int) -> int | None:
    """Decodifique um símbolo de dados.

    Parameters
    ----------
    token : int
        Símbolo de 10 bits.

    Returns
    -------
    int | None
        O byte de pixel, ou None quando o símbolo é de controle.
    """
    if token in CONTROL_TOKENS.values():
        return None
    low = token & BYTE_MASK
    q_m = low ^ BYTE_MASK if (token >> 9) & 1 else low
    use_xor = (token >> 8) & 1
    byte = q_m & 1
    for i in range(1, BYTE_BITS):
        changed = ((q_m >> i) ^ (q_m >> (i - 1))) & 1
        byte |= (changed if use_xor else 1 - changed) << i
    return byte


@dataclass
class EncoderModel:
    """Codificador de um canal com a disparidade acumulada.

    Attributes
    ----------
    disparity : int
        Bits em 1 menos bits em 0 enviados desde o último apagamento.
    """

    disparity: int = 0

    def control(self, c1: int, c0: int) -> int:
        """Envie um símbolo de controle e zere a disparidade.

        Parameters
        ----------
        c1 : int
            Bit de controle C1.
        c0 : int
            Bit de controle C0.

        Returns
        -------
        int
            O símbolo de controle.
        """
        self.disparity = 0
        return CONTROL_TOKENS[(c1 << 1) | c0]

    def data(self, byte: int) -> int:
        """Codifique um byte de pixel.

        Parameters
        ----------
        byte : int
            Byte de pixel.

        Returns
        -------
        int
            O símbolo de 10 bits.
        """
        q_m = minimize(byte)
        low = q_m & BYTE_MASK
        diff = 2 * ones(low) - BYTE_BITS
        xor_flag = (q_m >> BYTE_BITS) & 1
        same_sign = (self.disparity > 0 and diff > 0) or (
            self.disparity < 0 and diff < 0
        )
        if self.disparity == 0 or diff == 0:
            invert = not xor_flag
            self.disparity += -diff if invert else diff
        elif same_sign:
            invert = True
            self.disparity += 2 * xor_flag - diff
        else:
            invert = False
            self.disparity += diff - 2 * (1 - xor_flag)
        body = low ^ BYTE_MASK if invert else low
        return (int(invert) << 9) | (xor_flag << 8) | body


def symbols(bits: list[int], offset: int) -> list[int]:
    """Agrupe os bits de um canal em símbolos de 10 bits.

    Parameters
    ----------
    bits : list[int]
        Bits na ordem de transmissão.
    offset : int
        Posição do primeiro bit do primeiro símbolo.

    Returns
    -------
    list[int]
        Os símbolos, com o primeiro bit transmitido no bit 0.
    """
    count = (len(bits) - offset) // TOKEN_BITS
    return [
        sum(bits[offset + k * TOKEN_BITS + i] << i for i in range(TOKEN_BITS))
        for k in range(count)
    ]


def find_run(stream: list[int], run: list[int]) -> int | None:
    """Ache a posição de uma subsequência contígua.

    Parameters
    ----------
    stream : list[int]
        Sequência recebida.
    run : list[int]
        Sequência procurada.

    Returns
    -------
    int | None
        Posição da primeira ocorrência, ou None se não aparece.
    """
    for start in range(len(stream) - len(run) + 1):
        stop = start + len(run)
        if stream[start:stop] == run:
            return start
    return None
