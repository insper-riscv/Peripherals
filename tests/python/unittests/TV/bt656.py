"""Gerador de fluxo BT.656 de NTSC e modelo do quadro esperado.

O fluxo tem 525 linhas de 1716 bytes (858 amostras), o primeiro
campo tem 262 linhas e o segundo, 263. Cada campo tem 20 linhas de
apagamento vertical, 240 de vídeo ativo de 720 pixels e o resto de
apagamento. A linha n do campo F do vídeo ativo é a linha 2n + F do
quadro.
"""

ACTIVE_PIXELS = 720
ACTIVE_LINES = 480
FIELD_LINES = ACTIVE_LINES // 2
LEAD_BLANK = 20
FIELD_TOTAL = (262, 263)
ACTIVE_BYTES = 2 * ACTIVE_PIXELS
BLANK_BYTES = 268
PREFIX = (0xFF, 0x00, 0x00)
BLANK_FILL = (0x80, 0x10)


def timing_word(field: int, vblank: int, eav: int) -> int:
    """Monte a palavra XY de uma referência de temporização.

    Parameters
    ----------
    field : int
        Bit F do campo.
    vblank : int
        Bit V do apagamento vertical.
    eav : int
        Bit H, 1 para o fim e 0 para o início do vídeo ativo.

    Returns
    -------
    int
        A palavra XY com os quatro bits de proteção.
    """
    p3 = vblank ^ eav
    p2 = field ^ eav
    p1 = field ^ vblank
    p0 = field ^ vblank ^ eav
    return (
        0x80
        | field << 6
        | vblank << 5
        | eav << 4
        | p3 << 3
        | p2 << 2
        | p1 << 1
        | p0
    )


def content(x: int, y: int) -> tuple[int, int, int]:
    """Devolva Y, Cb e Cr do pixel (x, y) do quadro de teste.

    A crominância é a do par de colunas, como no formato 4:2:2.

    Parameters
    ----------
    x : int
        Coluna do pixel.
    y : int
        Linha do pixel no quadro.

    Returns
    -------
    tuple[int, int, int]
        Luminância, crominância azul e crominância vermelha.
    """
    pair = x // 2
    luma = 16 + (3 * x + 5 * y) % 220
    cb = 16 + (7 * pair + 3 * y) % 225
    cr = 16 + (5 * pair + 11 * y) % 225
    return luma, cb, cr


def active_bytes(y: int) -> bytes:
    """Devolva os 1440 bytes Cb Y Cr Y da linha y do quadro.

    Parameters
    ----------
    y : int
        Linha do quadro.

    Returns
    -------
    bytes
        Os bytes de vídeo ativo da linha.
    """
    out = bytearray()
    for x in range(0, ACTIVE_PIXELS, 2):
        luma0, cb, cr = content(x, y)
        luma1 = content(x + 1, y)[0]
        out += bytes((cb, luma0, cr, luma1))
    return bytes(out)


def blank_bytes(count: int) -> bytes:
    """Devolva bytes de apagamento horizontal (Cb e Y de preto).

    Parameters
    ----------
    count : int
        Número de bytes.

    Returns
    -------
    bytes
        Os bytes alternados 0x80 e 0x10.
    """
    return bytes(BLANK_FILL[i % 2] for i in range(count))


def line_bytes(field: int, vblank: int, y: int, flip: int = 0) -> bytes:
    """Monte uma linha do fluxo: SAV, vídeo, EAV e apagamento.

    Parameters
    ----------
    field : int
        Campo da linha.
    vblank : int
        1 se a linha está no apagamento vertical.
    y : int
        Linha do quadro do vídeo, ignorada com apagamento vertical.
    flip : int
        Máscara de bits trocados na palavra XY do SAV (erro injetado).

    Returns
    -------
    bytes
        Os 1716 bytes da linha.
    """
    sav = timing_word(field, vblank, 0) ^ flip
    eav = timing_word(field, vblank, 1)
    video = blank_bytes(ACTIVE_BYTES) if vblank else active_bytes(y)
    return (
        bytes((*PREFIX, sav))
        + video
        + bytes((*PREFIX, eav))
        + blank_bytes(BLANK_BYTES)
    )


def frame_bytes(bad_line: int | None = None) -> bytes:
    """Monte um quadro NTSC inteiro de 525 linhas.

    Parameters
    ----------
    bad_line : int | None
        Número, de 0 a 524, da linha cujo SAV leva um bit de proteção
        trocado, ou None para um fluxo sem erro.

    Returns
    -------
    bytes
        Os 900900 bytes do quadro.
    """
    out = bytearray()
    number = 0
    for field in (0, 1):
        for line in range(FIELD_TOTAL[field]):
            active = LEAD_BLANK <= line < LEAD_BLANK + FIELD_LINES
            n = line - LEAD_BLANK
            flip = 1 if number == bad_line else 0
            out += line_bytes(field, int(not active), 2 * n + field, flip)
            number += 1
    return bytes(out)


def to_rgb565(luma: int, cb: int, cr: int) -> int:
    """Converta YCbCr em RGB565 com a mesma aritmética do hardware.

    Parameters
    ----------
    luma : int
        Luminância.
    cb : int
        Crominância azul.
    cr : int
        Crominância vermelha.

    Returns
    -------
    int
        O pixel de 16 bits.
    """
    base = 298 * max(luma - 16, 0) + 128
    u = cb - 128
    v = cr - 128
    red = min(max((base + 409 * v) >> 8, 0), 255)
    green = min(max((base - 100 * u - 208 * v) >> 8, 0), 255)
    blue = min(max((base + 516 * u) >> 8, 0), 255)
    return (red >> 3) << 11 | (green >> 2) << 5 | blue >> 3


def source_row(src_y: int, field_sel: int) -> int | None:
    """Devolva a linha do quadro que a captura lê, se ela existir.

    Parameters
    ----------
    src_y : int
        Linha da origem já decimada, contada no campo ou no quadro.
    field_sel : int
        0 para os dois campos, 1 ou 2 para só um campo.

    Returns
    -------
    int | None
        Linha do quadro, ou None se a captura não chega até ela.
    """
    if field_sel == 0:
        return src_y if src_y < ACTIVE_LINES else None
    return 2 * src_y + field_sel - 1 if src_y < FIELD_LINES else None


def expected_frame(
    divisors: tuple[int, int],
    luma_format: bool,
    field_sel: int,
    size: tuple[int, int],
) -> dict[int, int]:
    """Devolva os pixels que a captura grava, por índice.

    Parameters
    ----------
    divisors : tuple[int, int]
        Fatores de decimação em x e em y.
    luma_format : bool
        Verdadeiro para luminância de 8 bits, falso para RGB565.
    field_sel : int
        0 para os dois campos, 1 ou 2 para só um campo.
    size : tuple[int, int]
        Largura e altura da memória do quadro em pixels.

    Returns
    -------
    dict[int, int]
        Valor do pixel de cada índice gravado.
    """
    div_x, div_y = divisors
    width, height = size
    out: dict[int, int] = {}
    for row in range(height):
        frame_y = source_row(row * div_y, field_sel)
        if frame_y is None:
            continue
        for col in range(min(width, -(-ACTIVE_PIXELS // div_x))):
            pixel = content(col * div_x, frame_y)
            out[row * width + col] = (
                pixel[0] if luma_format else to_rgb565(*pixel)
            )
    return out
