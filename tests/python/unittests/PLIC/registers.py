"""Word addresses of the PLIC registers, shared by its tests."""

PENDING_BASE = 0x1000 // 4
ENABLE_BASE = 0x2000 // 4
THRESHOLD = 0x200000 // 4
CLAIM = 0x200004 // 4
MASK32 = 0xFFFFFFFF


def priority(source: int) -> int:
    """Return the word address of the priority of a source.

    Parameters
    ----------
    source : int
        Source id.

    Returns
    -------
    int
        The word address.
    """
    return source


def pending_word(source: int) -> int:
    """Return the word address of the pending word that holds a source.

    Parameters
    ----------
    source : int
        Source id.

    Returns
    -------
    int
        The word address.
    """
    return PENDING_BASE + source // 32


def enable_word(source: int) -> int:
    """Return the word address of the enable word that holds a source.

    Parameters
    ----------
    source : int
        Source id.

    Returns
    -------
    int
        The word address.
    """
    return ENABLE_BASE + source // 32
