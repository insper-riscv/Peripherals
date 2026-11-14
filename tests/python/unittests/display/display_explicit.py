"""The display with an explicit partition (8 digits).

Partition 0,1,2,3/5,6: digits 4 and 7 are in no group, so they stay
blank.
"""

from tests.python.unittests.display import partition as p

globals().update(p.tests(p.Layout(digits=8, groups=((0, 1, 2, 3), (5, 6)))))
