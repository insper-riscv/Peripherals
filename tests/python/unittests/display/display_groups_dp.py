"""The generic group checks, with decimal points (8 digits).

Partition 0,1,2,3/5,6 with has_dp: o_hex has 8 bits per digit and the
point of each digit stays off while no point is written.
"""

from tests.python.unittests.display import partition as p

globals().update(
    p.tests(p.Layout(digits=8, groups=((0, 1, 2, 3), (5, 6)), has_dp=True))
)
