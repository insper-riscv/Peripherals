"""GPIO block with fixed directions and polarity (gpio_tb).

It also has an output pin that is off, held at its inactive level.
"""

from tests.python.unittests.GPIO import partition as p

globals().update(
    p.tests(
        p.Layout(
            pins=8,
            groups=((0, 1, 2, 3), (4, 5), (7,)),
            dirs="oooofioi",
            lows="hlhhlhlh",
        )
    )
)
