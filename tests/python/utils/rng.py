"""Seeded generator for the randomised tests."""

import random


def seeded(seed: int) -> random.Random:
    """Return a reproducible generator for stimulus, not for secrets.

    Parameters
    ----------
    seed : int
        Seed that makes the stimulus identical on every run.

    Returns
    -------
    random.Random
        The generator.
    """
    return random.Random(seed)  # noqa: S311 - deterministic test stimulus
