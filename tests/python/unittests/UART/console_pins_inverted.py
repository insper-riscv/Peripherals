"""Console com o backend "pinos" e os dois pinos invertidos.

Roda os testes de ``console_pins`` com a variável de ambiente que inverte o
nível de repouso esperado e a leitura dos quadros no pino.
"""

import os

os.environ["CONSOLE_INVERTED"] = "1"

from tests.python.unittests.UART.console_pins import *  # noqa: E402, F401, F403
