"""GPIO with consecutive pairs (gpio_tb, partition 0,1/2,3/4,5)."""

from tests.python.unittests.GPIO import partition as p

globals().update(
    p.tests(
        p.Layout(
            pins=6,
            groups=((0, 1), (2, 3), (4, 5)),
            dirs="ffffff",
            lows="hhhhhh",
        )
    )
)
