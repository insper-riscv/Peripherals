"""The display with decimal points, active high: 3 digits, one group."""

from tests.python.unittests.display import dp_checks as d

globals().update(
    d.tests(d.DpLayout(digits=3, groups=((0, 1, 2),), active_low=False))
)
