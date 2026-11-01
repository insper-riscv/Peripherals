"""Check helper for the cocotb tests."""


def check(condition: bool, message: str = "") -> None:
    """Fail the running test if a condition does not hold.

    Parameters
    ----------
    condition : bool
        The condition that must hold.
    message : str
        Text of the failure.

    Raises
    ------
    AssertionError
        If the condition is false.
    """
    if not condition:
        raise AssertionError(message)
