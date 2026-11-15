"""Modelo do CSI-2 sobre D-PHY em alta velocidade, para os testes.

Monta pacotes curtos e longos com ECC e CRC-16, distribui os bytes
pelas lanes e serializa cada lane em pares de bits, dois por ciclo do
clock da câmera, como o registrador DDR de entrada os entrega. Os
bits de cada byte saem do menos significativo.
"""

SYNC = 0xB8
CRC_INIT = 0xFFFF
CRC_POLY = 0x8408

# Bits de dado do cabeçalho que cada bit de paridade do ECC cobre.
ECC_COVER = (
    (0, 1, 2, 4, 5, 7, 10, 11, 13, 16, 20, 21, 22, 23),
    (0, 1, 3, 4, 6, 8, 10, 12, 14, 17, 20, 21, 22, 23),
    (0, 2, 3, 5, 6, 9, 11, 12, 15, 18, 20, 21, 22),
    (1, 2, 3, 7, 8, 9, 13, 14, 15, 19, 20, 21, 23),
    (4, 5, 6, 7, 8, 9, 16, 17, 18, 19, 20, 22, 23),
    (10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23),
)

type Pair = tuple[int, int]


def ecc(value: int) -> int:
    """Obtenha o ECC de 6 bits de um cabeçalho de 24 bits.

    Parameters
    ----------
    value : int
        Identificador de dado, contagem baixa e contagem alta.

    Returns
    -------
    int
        O ECC.
    """
    result = 0
    for index, cover in enumerate(ECC_COVER):
        parity = sum(value >> bit & 1 for bit in cover) & 1
        result |= parity << index
    return result


def crc16(data: bytes) -> int:
    """Obtenha o CRC-16 do CSI-2 (CRC-16 MCRF4XX).

    Parameters
    ----------
    data : bytes
        Carga útil do pacote.

    Returns
    -------
    int
        O CRC.
    """
    crc = CRC_INIT
    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = crc >> 1 ^ CRC_POLY if crc & 1 else crc >> 1
    return crc


def header(dt: int, word_count: int, vc: int = 0) -> bytes:
    """Monte o cabeçalho de quatro bytes de um pacote.

    Parameters
    ----------
    dt : int
        Tipo de dado.
    word_count : int
        Contagem de palavras, ou o dado de um pacote curto.
    vc : int
        Canal virtual.

    Returns
    -------
    bytes
        Identificador, contagem baixa, contagem alta e ECC.
    """
    first = vc << 6 | dt
    value = first | (word_count & 0xFFFF) << 8
    return bytes([first, word_count & 0xFF, word_count >> 8, ecc(value)])


def short_packet(dt: int, data: int = 0, vc: int = 0) -> bytes:
    """Monte um pacote curto.

    Parameters
    ----------
    dt : int
        Tipo de dado, de 0 a 15.
    data : int
        Dado de 16 bits.
    vc : int
        Canal virtual.

    Returns
    -------
    bytes
        O pacote.
    """
    return header(dt, data, vc)


def long_packet(
    dt: int, payload: bytes, vc: int = 0, bad_crc: int = 0
) -> bytes:
    """Monte um pacote longo com o CRC depois da carga útil.

    Parameters
    ----------
    dt : int
        Tipo de dado, de 16 a 63.
    payload : bytes
        Carga útil.
    vc : int
        Canal virtual.
    bad_crc : int
        Valor somado ao CRC para forjar um CRC errado.

    Returns
    -------
    bytes
        O pacote, com o byte baixo do CRC primeiro.
    """
    crc = (crc16(payload) + bad_crc) & 0xFFFF
    return (
        header(dt, len(payload), vc) + payload + bytes([crc & 0xFF, crc >> 8])
    )


def distribute(packet: bytes, lanes: int) -> list[list[int]]:
    """Reparta os bytes do pacote pelas lanes (byte n na lane n mod L).

    Parameters
    ----------
    packet : bytes
        Bytes do pacote.
    lanes : int
        Quantidade de lanes.

    Returns
    -------
    list[list[int]]
        Os bytes de cada lane.
    """
    return [list(packet[lane::lanes]) for lane in range(lanes)]


def byte_bits(value: int) -> list[int]:
    """Separe um byte em bits, do menos significativo.

    Parameters
    ----------
    value : int
        O byte.

    Returns
    -------
    list[int]
        Os oito bits.
    """
    return [value >> bit & 1 for bit in range(8)]


def lane_bits(
    data: list[int], lead_zeros: int, tail_zeros: int = 16
) -> list[int]:
    """Serialize uma rajada de uma lane: zeros, sincronismo e dados.

    Parameters
    ----------
    data : list[int]
        Bytes da lane, depois do sincronismo.
    lead_zeros : int
        Bits em zero antes do sincronismo.
    tail_zeros : int
        Bits em zero depois do último byte.

    Returns
    -------
    list[int]
        Os bits em ordem de tempo.
    """
    bits = [0] * lead_zeros + byte_bits(SYNC)
    for byte in data:
        bits += byte_bits(byte)
    return bits + [0] * tail_zeros


def to_pairs(bits: list[int]) -> list[Pair]:
    """Agrupe os bits em pares (mais antigo, mais novo) de um ciclo.

    Parameters
    ----------
    bits : list[int]
        Bits em ordem de tempo.

    Returns
    -------
    list[Pair]
        Um par por ciclo; um bit solto vira par com zero.
    """
    if len(bits) % 2:
        bits = [*bits, 0]
    return [(bits[i], bits[i + 1]) for i in range(0, len(bits), 2)]


def burst(
    packet: bytes, lanes: int, lead: int = 24, skew: tuple[int, ...] = ()
) -> list[list[Pair]]:
    """Serialize um pacote em todas as lanes, ciclo a ciclo.

    Parameters
    ----------
    packet : bytes
        Bytes do pacote.
    lanes : int
        Quantidade de lanes.
    lead : int
        Bits em zero antes do sincronismo na lane mais adiantada.
    skew : tuple[int, ...]
        Atraso em bits de cada lane, para deslocar a fase e a defasagem.

    Returns
    -------
    list[list[Pair]]
        Para cada ciclo, o par de cada lane.
    """
    delays = skew or (0,) * lanes
    streams = [
        to_pairs(lane_bits(data, lead + delays[lane]))
        for lane, data in enumerate(distribute(packet, lanes))
    ]
    size = max(len(stream) for stream in streams)
    streams = [stream + [(0, 0)] * (size - len(stream)) for stream in streams]
    return [[stream[cycle] for stream in streams] for cycle in range(size)]


def frame_packets(
    lines: list[bytes], dt: int = 0x2A, frame: int = 1
) -> list[bytes]:
    """Monte os pacotes de um quadro, do início ao fim.

    Parameters
    ----------
    lines : list[bytes]
        Carga útil de cada linha.
    dt : int
        Tipo de dado das linhas.
    frame : int
        Número do quadro do pacote de início e de fim.

    Returns
    -------
    list[bytes]
        Início de quadro, linhas e fim de quadro.
    """
    packets = [short_packet(0x00, frame)]
    packets += [long_packet(dt, line) for line in lines]
    packets.append(short_packet(0x01, frame))
    return packets
