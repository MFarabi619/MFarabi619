"""Microvisor Test Runner — Ward-inspired BDD renderer for PlatformIO + Unity."""

from __future__ import annotations

import re
from collections import Counter
from typing import Final, NamedTuple

import click
from platformio.test.runners.unity import UnityTestRunner

ANSI_RE: Final = re.compile(r"\x1b\[[0-9;]*m")
MODULE_PREFIX: Final = "[MODULE]"
INDENT: Final = "  "
BAR_WIDTH: Final = 40
HEADER_WIDTH: Final = 60


class BddStyle(NamedTuple):
    color: str
    depth: int


BDD_STYLES: Final[dict[str, BddStyle]] = {
    "[GIVEN]": BddStyle("cyan", 1),
    "[WHEN]":  BddStyle("blue", 2),
    "[THEN]":  BddStyle("magenta", 3),
    "[AND]":   BddStyle("magenta", 3),
}

VERDICT_COLORS: Final[dict[str, str]] = {
    "PASSED":  "bright_green",
    "SKIPPED": "bright_yellow",
    "FAILED":  "bright_red",
}


def _styled_bar(count: int, total: int, color: str) -> str:
    width = round(BAR_WIDTH * count / total) if total else 0
    return click.style(" " * width, bg=color) if width else ""


def _summary_row(label: str, count: int, total: int, color: str) -> str:
    num = click.style(f"{count:3d}", fg=color, bold=True)
    bar = _styled_bar(count, total, color)
    pct = 100.0 * count / total if total else 0.0
    return f"  {num}  {label:<8s} {bar:<40s} {pct:5.1f}%"


class CustomTestRunner(UnityTestRunner):

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._current_module: str | None = None
        self._scenario_depth: int = 0

    # ── PlatformIO hook ──────────────────────────────────────────────────

    def on_testing_line_output(self, line: str) -> None:
        line = ANSI_RE.sub("", line or "").strip()
        if not line:
            return

        if test_case := self.parse_test_case(line):
            self._render_verdict(test_case)
            self._scenario_depth = 0
        elif ":INFO:" in line:
            self._render_info(line.split(":INFO:", 1)[-1].strip())
        elif self.options.verbose:
            click.echo(click.style(line, fg="white", dim=True))

        if all(s in line for s in ("Tests", "Failures", "Ignored")):
            self._render_summary()
            self.test_suite.on_finish()

    # ── Rendering ────────────────────────────────────────────────────────

    def _render_info(self, msg: str) -> None:
        if msg.startswith(MODULE_PREFIX):
            self._render_module_header(msg[len(MODULE_PREFIX):].strip())
            return

        if match := self._match_bdd_prefix(msg):
            prefix, style = match
            effective = min(style.depth, self._scenario_depth + 1)
            self._scenario_depth = max(self._scenario_depth, effective)
            tag = click.style(prefix, fg="black", bg=style.color, bold=True)
            text = click.style(msg[len(prefix):], fg=style.color)
            click.echo(f"{INDENT * effective}{tag}{text}")
        else:
            depth = max(self._scenario_depth, 1)
            click.echo(INDENT * depth + click.style(msg, fg="white"))

    def _render_module_header(self, name: str) -> None:
        self._current_module = name
        pad = max(0, HEADER_WIDTH - len(name) - 2) // 2
        click.echo()
        click.echo(click.style(f"{'═' * pad} {name} {'═' * pad}", fg="white", bold=True))

    def _render_verdict(self, test_case) -> None:
        self.test_suite.add_case(test_case)
        name = test_case.name.replace("_", " ").removeprefix("test ")
        status = test_case.status.name
        bg = VERDICT_COLORS.get(status, "white")
        tag = click.style(f"[{status}]", fg="black", bg=bg, bold=True)
        styled_name = click.style(name, fg=bg.removeprefix("bright_"))

        dur = getattr(test_case, "duration", 0) or 0
        duration = click.style(f"  {int(dur * 1000)} ms", fg="white", dim=True) if dur > 0 else ""

        click.echo(f"{tag} {styled_name}{duration}")

    def _render_summary(self) -> None:
        cases = self.test_suite.cases
        total = len(cases)
        if not total:
            return

        counts = Counter(c.status.name for c in cases)
        divider = click.style("═" * HEADER_WIDTH, fg="white", bold=True)

        click.echo()
        click.echo(divider)
        click.echo(click.style("  Results", fg="white", bold=True))
        click.echo(divider)
        click.echo(f"  {total:3d}  total")
        for label, color in VERDICT_COLORS.items():
            click.echo(_summary_row(label.lower(), counts.get(label, 0), total, color))
        click.echo(divider)

    # ── Helpers ──────────────────────────────────────────────────────────

    @staticmethod
    def _match_bdd_prefix(msg: str) -> tuple[str, BddStyle] | None:
        return next(
            ((prefix, style) for prefix, style in BDD_STYLES.items() if msg.startswith(prefix)),
            None,
        )
