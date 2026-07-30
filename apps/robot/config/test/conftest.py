# Copyright 2026 Mumtahin Farabi
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.


from rich.box import ROUNDED
from rich.console import Console
from rich.panel import Panel
from rich.table import Table
from rich.text import Text

PASS_COLOR = '#b8bb26'
FAIL_COLOR = '#fb4934'
SKIP_COLOR = '#fabd2f'


def pytest_terminal_summary(terminalreporter, exitstatus, config):
    suites = {}
    for outcome in ('passed', 'failed', 'skipped'):
        for report in terminalreporter.stats.get(outcome, []):
            if outcome != 'skipped' and report.when != 'call':
                continue
            suite = report.nodeid.split('::')[0].split('/')[-1]
            entry = suites.setdefault(
                suite, {'passed': 0, 'failed': 0, 'skipped': 0, 'duration': 0.0})
            entry[outcome] += 1
            entry['duration'] += getattr(report, 'duration', 0.0)
    if not suites:
        return

    console = Console()
    table = Table(title='robot tests', box=ROUNDED, title_style='bold')
    table.add_column('suite')
    table.add_column('pass', justify='right')
    table.add_column('fail', justify='right')
    table.add_column('skip', justify='right')
    table.add_column('time', justify='right')
    table.add_column('', justify='center')

    total = {'passed': 0, 'failed': 0, 'skipped': 0}
    for suite in sorted(suites):
        entry = suites[suite]
        for outcome in total:
            total[outcome] += entry[outcome]
        mark = Text('✓', style=PASS_COLOR) if entry['failed'] == 0 else Text(
            '✗', style=FAIL_COLOR)
        table.add_row(
            suite,
            Text(str(entry['passed']), style=PASS_COLOR),
            Text(str(entry['failed']), style=FAIL_COLOR if entry['failed'] else 'dim'),
            Text(str(entry['skipped']), style=SKIP_COLOR if entry['skipped'] else 'dim'),
            f"{entry['duration'] * 1000:.0f} ms",
            mark)
    console.print(table)

    banner = Text.assemble(
        ('✓ ', PASS_COLOR), (f"{total['passed']} passed", 'default'),
        ('   ✗ ', FAIL_COLOR), (f"{total['failed']} failed", 'default'),
        ('   • ', SKIP_COLOR), (f"{total['skipped']} skipped", 'default'))
    console.print(Panel(
        banner, border_style=PASS_COLOR if total['failed'] == 0 else FAIL_COLOR))
