"""The display with decimal points: 8 digits, groups, active low.

Partition 0,1,2,3/5,6; digits 4 and 7 are in no group.
"""

from tests.python.unittests.display import dp_checks as d

LAYOUT = d.DpLayout(digits=8, groups=((0, 1, 2, 3), (5, 6)), active_low=True)

globals().update(d.tests(LAYOUT))
