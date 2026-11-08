"""Console com o backend "pinos" e os dois pinos invertidos.

Roda os testes de ``console_pins`` com a variável de ambiente que
inverte o nível de repouso esperado e a leitura dos quadros no pino.
"""

import importlib
import os

os.environ["CONSOLE_INVERTED"] = "1"

_base = importlib.import_module("tests.python.unittests.UART.console_pins")

# cocotb collects the tests from the namespace of this module.
globals().update(
    {
        name: value
        for name, value in vars(_base).items()
        if name.startswith("test_")
    }
)
