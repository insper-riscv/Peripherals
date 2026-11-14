"""GPIO with an explicit partition (gpio_tb).

Partition 0,1,2,3/5,6: pin 4 is in no group, so it is off.
"""

from tests.python.unittests.GPIO import partition as p

globals().update(
    p.tests(
        p.Layout(
            pins=7,
            groups=((0, 1, 2, 3), (5, 6)),
            dirs="fffffff",
            lows="hhhhhhh",
        )
    )
)
