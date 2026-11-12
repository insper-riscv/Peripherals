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


def check_equal(got: int, want: int) -> None:
    """Fail the running test if two values differ.

    Parameters
    ----------
    got : int
        The value the design produced.
    want : int
        The value the test expects.

    Raises
    ------
    AssertionError
        If the values differ.
    """
    if got != want:
        raise AssertionError(f"got {got:#x}, want {want:#x}")
