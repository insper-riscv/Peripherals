"""GPIO with one group per pin (gpio_tb, partition 0/1/2/3)."""

from tests.python.unittests.GPIO import partition as p

globals().update(
    p.tests(
        p.Layout(
            pins=4, groups=((0,), (1,), (2,), (3,)), dirs="ffff", lows="hhhh"
        )
    )
)
