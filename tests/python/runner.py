"""Run the cocotb tests of the peripherals listed in tests.json."""

import argparse
import json
import os
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, cast

# cocotb 2.0 split the Python test-runner API out of the main cocotb
# package into cocotb-tools, imported as cocotb_tools.runner.
from cocotb_tools.check_results import get_results
from cocotb_tools.runner import get_runner

NO_REASON = "no reason given"

Parameters = dict[str, bool | int | str]


@dataclass(frozen=True)
class Config:
    """One entry of tests.json.

    Attributes
    ----------
    toplevel : str
        Name of the top-level entity.
    sources : list[str]
        VHDL sources, relative to the repository root.
    test_module : str
        Dotted name of the cocotb test module.
    parameters : Parameters
        Generics of the top-level.
    build_args : list[str]
        Extra arguments of the build step.
    test_args : list[str]
        Extra arguments of the test step.
    skip : bool
        Leave the test out of the sweep of all tests.
    skip_reason : str
        Why the test is skipped.
    """

    toplevel: str
    sources: list[str]
    test_module: str
    parameters: Parameters = field(default_factory=Parameters)
    build_args: list[str] = field(default_factory=list[str])
    test_args: list[str] = field(default_factory=list[str])
    skip: bool = False
    skip_reason: str = NO_REASON


def _resolve_path_parameter(value: str, repo_root: Path) -> str:
    """Return the absolute path a parameter names, or the value itself.

    Parameters
    ----------
    value : str
        Parameter value that may be a path.
    repo_root : Path
        Root of the repository, tried when the path is not relative to
        the current directory.

    Returns
    -------
    str
        The resolved path if it exists, otherwise the original value.
    """
    for candidate in (Path(value), repo_root / value):
        if candidate.exists():
            return str(candidate.resolve())
    return value


def _to_vhdl_parameter(value: bool | int | str, repo_root: Path) -> str:
    """Convert one generic value to the text the simulator expects.

    Parameters
    ----------
    value : bool | int | str
        Value of the generic.
    repo_root : Path
        Root of the repository, used to resolve path values.

    Returns
    -------
    str
        The value as text.
    """
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    return _resolve_path_parameter(value, repo_root)


def _build_dir(tests_root: Path, test_module: str, toplevel: str) -> Path:
    """Return the simulation build directory of a test.

    Parameters
    ----------
    tests_root : Path
        The tests directory of the repository.
    test_module : str
        Dotted name of the cocotb test module.
    toplevel : str
        Name of the top-level entity.

    Returns
    -------
    Path
        The directory, already created.
    """
    if ".entities." in test_module:
        group, name = "entities", toplevel
    elif ".instructions." in test_module:
        group, name = "instructions", test_module.rsplit(".", maxsplit=1)[-1]
    else:
        group, name = "misc", toplevel
    build_dir = tests_root / "python/sim_build" / group / name
    build_dir.mkdir(parents=True, exist_ok=True)
    return build_dir


def run_cocotb_test(config: Config) -> None:
    """Build one top-level with the simulator and run its cocotb tests.

    Parameters
    ----------
    config : Config
        The entry of tests.json to run.

    Raises
    ------
    RuntimeError
        If any cocotb test fails.
    """
    tests_root = Path(__file__).resolve().parents[1]
    repo_root = Path(__file__).resolve().parents[2]
    sys.path.append(str(repo_root))

    runner = get_runner(os.getenv("SIM", "ghdl"))
    build_dir = _build_dir(tests_root, config.test_module, config.toplevel)
    vhdl_params = {
        key: _to_vhdl_parameter(value, repo_root)
        for key, value in config.parameters.items()
    }

    runner.build(
        vhdl_sources=[repo_root / source for source in config.sources],
        hdl_toplevel=config.toplevel,
        always=True,
        build_dir=build_dir,
        parameters=vhdl_params,
        build_args=config.build_args,
    )

    wave_file = build_dir / "waves.ghw"
    results_xml = runner.test(
        hdl_toplevel=config.toplevel,
        hdl_toplevel_lang="vhdl",
        test_module=config.test_module,
        build_dir=build_dir,
        plusargs=[f"--wave={wave_file}"],
        test_args=config.test_args,
    )
    print(f"Waves: {wave_file} (generated)")

    # runner.test() returns normally when a cocotb test fails; the
    # failures are only in results.xml.
    total, failed = get_results(results_xml)
    if failed:
        message = f"{failed} of {total} cocotb tests failed"
        raise RuntimeError(message)


def _load_configs(json_path: Path) -> dict[str, Config]:
    """Read tests.json, exiting with a message if it cannot be used.

    Parameters
    ----------
    json_path : Path
        Path of tests.json.

    Returns
    -------
    dict[str, Config]
        The test configurations by name.
    """
    try:
        with json_path.open(encoding="utf-8") as file:
            raw = cast("dict[str, dict[str, Any]]", json.load(file))
        return {name: Config(**entry) for name, entry in raw.items()}
    except FileNotFoundError:
        print(f"Error: configuration file '{json_path}' not found.")
    except json.JSONDecodeError:
        print(f"Error: the JSON file '{json_path}' is malformed.")
    sys.exit(1)


def _run_all(configs: dict[str, Config]) -> None:
    """Run every test that is not marked as skip.

    The skip and skip_reason keys are a config-level opt-out for a test
    that is known to be broken for an unrelated reason. They only apply
    to this sweep; running a test by name still attempts it.

    Parameters
    ----------
    configs : dict[str, Config]
        The test configurations by name.
    """
    print("Running ALL tests defined in tests.json...")
    failures: list[str] = []
    for name, config in configs.items():
        if config.skip:
            reason = config.skip_reason
            print(f"\n{'=' * 20} SKIPPING TEST: {name.upper()} {'=' * 20}")
            print(f"[SKIP] {reason}")
            continue
        print(f"\n{'=' * 20} STARTING TEST: {name.upper()} {'=' * 20}")
        try:
            run_cocotb_test(config)
        except (RuntimeError, OSError, subprocess.SubprocessError) as error:
            failures.append(name)
            print(f"[FAIL] test '{name}' failed: {error}")
        else:
            print(f"{'-' * 20} TEST {name.upper()} FINISHED {'-' * 20}")
    print("\nAll tests were executed.")
    if failures:
        print(f"[FAIL] {len(failures)} test(s) failed: {', '.join(failures)}")
        sys.exit(1)


def _run_one(name: str, config: Config) -> None:
    """Run a single test by name, even if it is marked as skip.

    Parameters
    ----------
    name : str
        Name of the test in tests.json.
    config : Config
        The entry of tests.json.
    """
    print(f"Running specific test: {name}")
    if config.skip:
        reason = config.skip_reason
        print(
            f"[WARN] '{name}' is marked as skip ({reason}) "
            "-- running anyway, as it was explicitly requested."
        )
    run_cocotb_test(config)
    print(f"\nTest {name} finished.")


def main() -> None:
    """Parse the command line and run the requested tests."""
    tests_root = Path(__file__).resolve().parents[1]
    configs = _load_configs(tests_root / "python/tests.json")
    options = [*configs, "all"]

    parser = argparse.ArgumentParser(
        description="Cocotb test runner for the RV32I project"
    )
    parser.add_argument(
        "test_name",
        nargs="?",
        default="all",
        help=f"Name of the test to run. Options: {options}",
    )
    test_name = cast("str", parser.parse_args().test_name)

    if test_name == "all":
        _run_all(configs)
    elif test_name in configs:
        _run_one(test_name, configs[test_name])
    else:
        print(f"Error: test '{test_name}' not found in tests.json.")
        print(f"Available options: {options}")
        sys.exit(1)


if __name__ == "__main__":
    main()
