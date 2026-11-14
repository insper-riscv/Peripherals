"""The display with the digits of each group in reverse order.

Partition 3,2,1,0/5,4.
"""

from tests.python.unittests.display import partition as p

globals().update(p.tests(p.Layout(digits=6, groups=((3, 2, 1, 0), (5, 4)))))
