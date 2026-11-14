"""GPIO with the pins listed in reverse order (gpio_tb).

Partition 5,4,3,2,1,0: one group whose bit k is the pin 5 - k.
"""

from tests.python.unittests.GPIO import partition as p

globals().update(
    p.tests(
        p.Layout(
            pins=6, groups=((5, 4, 3, 2, 1, 0),), dirs="ffffff", lows="hhhhhh"
        )
    )
)
