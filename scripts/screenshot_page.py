#!/usr/bin/env python3
"""Start (if needed) the dev fixtures + polaris, connect, navigate to a
sidebar page, and screenshot it - the AT-SPI-driven live verification
technique documented in DEVELOPMENT.md, packaged into a reusable script
instead of ad-hoc one-off snippets re-derived every session.

Usage:
    scripts/screenshot_page.py <page> <output.png> [--click BUTTON ...]

    <page> is a sidebar entry's exact label - "Status"/"Shell"/"Logs"/
    "Events"/"Settings" for the built-ins, or a connected module's
    registered widget label ("Camera"/"Telescope"/"Roof"/"Auto Focus"/
    "Acquisition"/"Auto Guiding"/"Mode"/"Weather").

    --click BUTTON (repeatable) presses an additional *visible* button
    on the page after navigating there, before the screenshot - e.g.
    `--click Expose` on the Camera page. Only ever presses a button
    that's actually AT-SPI SHOWING - every module's page delegate
    exists in the accessibility tree simultaneously (see
    DEVELOPMENT.md's "round 2" write-up), so an unfiltered name lookup
    can silently fire an action on the wrong, invisible module.

Requirements (all already true on this dev machine, not auto-installed
here): `gi.repository.Atspi` (Debian/Ubuntu package
gir1.2-atspi-2.0), `spectacle` (KDE screenshot tool), a pyobs-core venv
(see PYOBS_CORE_VENV below), a running ejabberd reachable at localhost
with the fixture accounts already registered (see DEVELOPMENT.md's
"Live-verification test fixtures" section), and passwordless (or
already-cached) `sudo ejabberdctl` - only invoked to clear stale zombie
XMPP sessions, see ensure_single_xmpp_session()'s own docstring.

Environment overrides:
    POLARIS_BIN          - path to the built polaris binary
                            (default: build/Release/polaris under the repo root)
    PYOBS_CORE_VENV       - path to a pyobs-core venv
                            (default: ~/code/pyobs/pyobs-core/.venv)
    SCREENSHOT_LOG_DIR    - where fixture/polaris stdout+stderr logs go
                            (default: /tmp/polaris-screenshot-logs)

Idempotent: only starts fixtures/polaris that aren't already running,
and only kicks XMPP sessions when more than one is actually found. Not
CI-portable - this is a local dev convenience script tied to this
machine's ejabberd/fixture/spectacle setup, not a test.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
import time
from pathlib import Path

import gi

gi.require_version("Atspi", "2.0")
from gi.repository import Atspi  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parent.parent
FIXTURES_DIR = REPO_ROOT / "fixtures"
POLARIS_BIN = Path(os.environ.get("POLARIS_BIN", REPO_ROOT / "build" / "Release" / "polaris"))
PYOBS_CORE_VENV = Path(os.environ.get("PYOBS_CORE_VENV", Path.home() / "code" / "pyobs" / "pyobs-core" / ".venv"))
PYOBS_BIN = PYOBS_CORE_VENV / "bin" / "pyobs"
LOG_DIR = Path(os.environ.get("SCREENSHOT_LOG_DIR", "/tmp/polaris-screenshot-logs"))


def log(message: str) -> None:
    print(message, file=sys.stderr)


def is_process_running(literal_substring: str) -> bool:
    # `pgrep -f` matches its pattern as an extended regex, not a literal
    # substring - this repo's own directory is named "pyobs-gui++",
    # whose "++" is a regex metacharacter sequence that pgrep silently
    # fails to match against (no error, just a false "not running"). Hit
    # live: two duplicate polaris instances got launched before this was
    # caught, see DEVELOPMENT.md. re.escape() every caller unconditionally
    # so a literal path is always what actually gets matched.
    pattern = re.escape(literal_substring)
    return subprocess.run(["pgrep", "-f", pattern], capture_output=True).returncode == 0


def start_fixtures() -> list[str]:
    """Starts every fixtures/*.yaml (except the shared _comm.yaml) that
    isn't already running, from the pyobs-core venv. Returns the names
    of the ones actually started."""
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    started = []
    for yaml_file in sorted(FIXTURES_DIR.glob("*.yaml")):
        if yaml_file.name == "_comm.yaml":
            continue
        # Matches this project's own `ps aux | grep "[p]yobs fixtures"`
        # convention (see DEVELOPMENT.md) - pgrep -f searches the full
        # command line, so this substring is enough without needing the
        # bracket self-match trick pgrep doesn't need anyway.
        if is_process_running(f"pyobs fixtures/{yaml_file.name}"):
            continue
        log_path = LOG_DIR / f"{yaml_file.stem}.log"
        with open(log_path, "w") as log_file:
            subprocess.Popen(
                [str(PYOBS_BIN), f"fixtures/{yaml_file.name}"],
                cwd=REPO_ROOT,
                stdout=log_file,
                stderr=subprocess.STDOUT,
                start_new_session=True,
            )
        started.append(yaml_file.stem)
    return started


def start_polaris() -> bool:
    """Starts polaris with the accessibility bridge forced on
    (QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1) if it isn't already running.
    Without this env var Qt only registers on the AT-SPI bus lazily,
    once a real screen reader asks - a script polling for the app never
    would. Returns whether it actually started a new instance."""
    if is_process_running(str(POLARIS_BIN)):
        return False
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["QT_LINUX_ACCESSIBILITY_ALWAYS_ON"] = "1"
    env["QT_ACCESSIBILITY"] = "1"
    with open(LOG_DIR / "polaris.log", "w") as log_file:
        subprocess.Popen(
            [str(POLARIS_BIN)],
            cwd=REPO_ROOT,
            stdout=log_file,
            stderr=subprocess.STDOUT,
            env=env,
            start_new_session=True,
        )
    return True


def find_polaris_app(timeout: float = 15.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        desktop = Atspi.get_desktop(0)
        for i in range(desktop.get_child_count()):
            app = desktop.get_child_at_index(i)
            if app is not None and app.get_name() == "Polaris":
                return app
        time.sleep(0.5)
    return None


def _walk(node, predicate, results: list, depth: int = 0, max_depth: int = 25) -> None:
    try:
        if predicate(node):
            results.append(node)
    except Exception:
        return
    if depth >= max_depth:
        return
    for i in range(node.get_child_count()):
        try:
            child = node.get_child_at_index(i)
        except Exception:
            continue
        if child is not None:
            _walk(child, predicate, results, depth + 1, max_depth)


def find_buttons(app, name: str, showing_only: bool = False) -> list:
    """Finds every "button"-role node named `name` in the app's
    accessibility tree. Every module's page delegate exists in the tree
    simultaneously regardless of which page is actually showing (see
    MainWindow.qml's StackLayout - all children are eagerly
    instantiated), so a bare name search can return several matches for
    a control that only really exists on one currently-visible page -
    pass showing_only=True (and take the first result) to avoid pressing
    the wrong, invisible one."""
    results: list = []

    def predicate(node) -> bool:
        if node.get_role_name() != "button" or node.get_name() != name:
            return False
        if not showing_only:
            return True
        try:
            return bool(node.get_state_set().contains(Atspi.StateType.SHOWING))
        except Exception:
            return False

    _walk(app, predicate, results)
    return results


def press(node) -> None:
    node.get_action_iface().do_action(0)


def ensure_single_xmpp_session(no_kick: bool) -> bool:
    """Repeated pkills of polaris without a graceful disconnectFromServer()
    leave stale zombie admin@localhost XMPP sessions server-side (see
    DEVELOPMENT.md's Phase 3 gotcha, and the "round 2" write-up where
    this was hit in practice) - confusing enough to leave the module
    list empty even though discovery itself succeeds. Kicks all
    admin@localhost sessions via `sudo ejabberdctl kick_user` if more
    than one is found; returns whether it did."""
    if no_kick:
        return False
    result = subprocess.run(
        ["sudo", "ejabberdctl", "connected_users"], capture_output=True, text=True
    )
    admin_sessions = [line for line in result.stdout.splitlines() if line.startswith("admin@localhost/")]
    if len(admin_sessions) <= 1:
        return False
    subprocess.run(["sudo", "ejabberdctl", "kick_user", "admin", "localhost"], capture_output=True)
    return True


def connect(app, timeout: float = 15.0) -> None:
    connect_buttons = find_buttons(app, "Connect", showing_only=True)
    if not connect_buttons:
        return  # already connected - no visible login window
    press(connect_buttons[0])
    deadline = time.time() + timeout
    while time.time() < deadline:
        if find_buttons(app, "Sign out", showing_only=True):
            return
        time.sleep(0.5)
    raise RuntimeError("timed out waiting for connection after pressing Connect")


def navigate_to(app, page: str, timeout: float = 10.0) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        buttons = find_buttons(app, page, showing_only=True)
        if buttons:
            press(buttons[0])
            return
        time.sleep(0.5)
    raise RuntimeError(
        f"sidebar entry {page!r} not found or not visible - is a module implementing it actually connected?"
    )


def click_visible(app, name: str) -> None:
    buttons = find_buttons(app, name, showing_only=True)
    if not buttons:
        raise RuntimeError(f"button {name!r} not found or not visible on the current page")
    press(buttons[0])


def screenshot(output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["spectacle", "-b", "-n", "-a", "-o", str(output_path)], check=True)


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("page", help="Sidebar entry to navigate to, e.g. Status, Camera, Telescope")
    parser.add_argument("output", type=Path, help="Path to write the screenshot PNG to")
    parser.add_argument(
        "--click",
        action="append",
        default=[],
        metavar="BUTTON",
        help="After navigating, press this visible button before screenshotting (repeatable, in order)",
    )
    parser.add_argument(
        "--settle",
        type=float,
        default=1.5,
        help="Seconds to wait after the final action before screenshotting (default: 1.5)",
    )
    parser.add_argument(
        "--no-kick",
        action="store_true",
        help="Don't check for/kick stale zombie XMPP sessions (skips the sudo ejabberdctl call)",
    )
    args = parser.parse_args()

    try:
        started_fixtures = start_fixtures()
        if started_fixtures:
            log(f"started fixtures: {', '.join(started_fixtures)}")
            time.sleep(3)  # let them register presence before polaris connects

        if start_polaris():
            log("started polaris")

        app = find_polaris_app()
        if app is None:
            raise RuntimeError(
                "polaris never registered on the AT-SPI bus - "
                "is QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1 taking effect?"
            )

        if ensure_single_xmpp_session(args.no_kick):
            log("kicked stale zombie XMPP session(s), restarting polaris cleanly")
            subprocess.run(["pkill", "-9", "-f", re.escape(str(POLARIS_BIN))])
            time.sleep(1)
            start_polaris()
            app = find_polaris_app()
            if app is None:
                raise RuntimeError("polaris didn't come back up after the session-kick restart")

        connect(app)
        navigate_to(app, args.page)
        for button_name in args.click:
            time.sleep(0.5)
            click_visible(app, button_name)

        time.sleep(args.settle)
        screenshot(args.output)
        log(f"screenshot saved to {args.output}")
    except RuntimeError as error:
        log(f"error: {error}")
        sys.exit(1)


if __name__ == "__main__":
    main()
