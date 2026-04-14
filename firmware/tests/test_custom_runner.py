"""
Microvisor Test Runner

Renders screenplay-style output with trace narration.
Test registration is manual — edit tests/test_unit/main.cpp directly.
"""

import re

import click
from platformio.test.runners.unity import UnityTestRunner

ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")


class CustomTestRunner(UnityTestRunner):
    def on_testing_line_output(self, line):
        if self.options.verbose:
            click.echo(line, nl=False)
            return

        line = ANSI_RE.sub("", line or "").strip()
        if not line:
            return

        test_case = self.parse_test_case(line)
        if test_case:
            self.test_suite.add_case(test_case)
            status = click.style(
                "[%s]" % test_case.status.name,
                fg=test_case.status.to_ansi_color(),
            )
            click.echo("%s %s" % (status, test_case.name.replace("_", " ")))
        elif ":INFO:" in line:
            msg = line.split(":INFO:", 1)[-1].strip()
            click.echo(
                "  %s %s"
                % (
                    click.style("·", fg="cyan"),
                    click.style(msg, fg="cyan", dim=True),
                )
            )

        if all(s in line for s in ("Tests", "Failures", "Ignored")):
            self.test_suite.on_finish()
