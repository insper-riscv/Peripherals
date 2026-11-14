"""The display with one digit in a group (partition 1).

The other five digits are in no group and stay blank.
"""

from tests.python.unittests.display import partition as p

globals().update(p.tests(p.Layout(digits=6, groups=((1,),))))
