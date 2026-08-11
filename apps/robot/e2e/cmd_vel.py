#!/usr/bin/env python3

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


from collections import deque
from dataclasses import dataclass
import math
import random
import sys
import time

from geometry_msgs.msg import TwistStamped
import rclpy
from rich.align import Align
from rich.bar import Bar
from rich.console import Console, Group
from rich.layout import Layout
from rich.live import Live
from rich.panel import Panel
from rich.progress import (
    BarColumn,
    MofNCompleteColumn,
    Progress,
    SpinnerColumn,
    TextColumn,
    TimeElapsedColumn,
    TimeRemainingColumn,
)
from rich.progress_bar import ProgressBar
from rich.rule import Rule
from rich.table import Table
from rich.text import Text

COMMAND_TOPIC = "/joy_teleop/cmd_vel"
FRAME_ID = "base_link"
RATE_HZ = 20.0
SETTLE_SECONDS = 1.0
GAUGE_WIDTH = 26
SCOPE_WIDTH = 60

LINEAR_LIMIT = 2.0
ANGULAR_LIMIT = 2.0

DEFAULT_FUZZ = 6
FUZZ_SEED = 42
FUZZ_KINDS = ["hold", "ramp", "trapezoid", "sine", "reversal"]
KNOWN_KINDS = {"hold", "ramp", "trapezoid", "sine", "reversal", "chirp"}

BLOCKS = " ▁▂▃▄▅▆▇█"

DONE = "#689d6a"
PENDING = "#504945"
WARN = "#fb4934"
FRAME = "#665c54"
POSITIVE = "#b8bb26"
NEGATIVE = "#fb4934"
ACCENT = "#83a598"


@dataclass
class Segment:
    name: str
    glyph: str
    color: str
    phase: str
    duration: float
    kind: str
    params: dict


@dataclass
class Frame:
    program: list
    index: int
    fraction: float
    linear_history: deque
    angular_history: deque
    subscribers: int
    sent: int
    peak_linear: float
    peak_angular: float
    progress: Progress


def trapezoid_scale(fraction, rise, fall):
    if fraction < rise:
        return fraction / rise
    if fraction > 1.0 - fall:
        return (1.0 - fraction) / fall
    return 1.0


def sample(kind, params, fraction):
    if kind == "hold":
        return params["lin"], params["ang"]
    if kind == "ramp":
        lin = params["lin0"] + (params["lin1"] - params["lin0"]) * fraction
        ang = params["ang0"] + (params["ang1"] - params["ang0"]) * fraction
        return lin, ang
    if kind == "trapezoid":
        scale = trapezoid_scale(
            fraction, params.get("rise", 0.25), params.get("fall", 0.25)
        )
        return params["lin"] * scale, params["ang"] * scale
    if kind == "sine":
        wave = math.sin(2 * math.pi * params["cycles"] * fraction)
        return params["lin"], params["ang"] * wave
    if kind == "reversal":
        sign = 1.0 if int(fraction * params["flips"]) % 2 == 0 else -1.0
        return params["lin"] * sign, params["ang"] * sign
    if kind == "chirp":
        low, high = params["c0"], params["c1"]
        angle = 2 * math.pi * (low * fraction + (high - low) * fraction * fraction / 2)
        return params["lin"], params["ang"] * math.sin(angle)
    return 0.0, 0.0


def scaled_sample(segment, fraction):
    linear, angular = sample(segment.kind, segment.params, fraction)
    return linear * LINEAR_LIMIT, angular * ANGULAR_LIMIT


def segment_ticks(segment):
    return max(1, round(segment.duration * RATE_HZ))


def fuzz_params(kind, linear, angular, rng):
    if kind == "ramp":
        return {"lin0": 0.0, "ang0": 0.0, "lin1": linear, "ang1": angular}
    if kind == "sine":
        return {"lin": linear, "ang": abs(angular), "cycles": rng.randint(2, 6)}
    if kind == "reversal":
        return {"lin": linear, "ang": angular, "flips": rng.randint(3, 8)}
    return {"lin": linear, "ang": angular}


def fuzz_segments(count, rng):
    segments = []
    for number in range(1, count + 1):
        kind = rng.choice(FUZZ_KINDS)
        linear = round(rng.uniform(-1.0, 1.0), 2)
        angular = round(rng.uniform(-1.0, 1.0), 2)
        duration = round(rng.uniform(1.0, 2.5), 1)
        segments.append(
            Segment(
                f"fuzz {number}",
                "⁇",
                "#928374",
                "fuzz",
                duration,
                kind,
                fuzz_params(kind, linear, angular, rng),
            )
        )
    return segments


def build_program(fuzz):
    program = [
        Segment(
            "ease forward",
            "↑",
            "#b8bb26",
            "straights",
            3.0,
            "trapezoid",
            {"lin": 1.0, "ang": 0.0},
        ),
        Segment(
            "ease reverse",
            "↓",
            "#fabd2f",
            "straights",
            3.0,
            "trapezoid",
            {"lin": -1.0, "ang": 0.0},
        ),
        Segment(
            "accelerate",
            "⇈",
            "#b8bb26",
            "straights",
            2.0,
            "ramp",
            {"lin0": 0.0, "ang0": 0.0, "lin1": 1.0, "ang1": 0.0},
        ),
        Segment(
            "brake",
            "⇊",
            "#fe8019",
            "straights",
            1.5,
            "ramp",
            {"lin0": 1.0, "ang0": 0.0, "lin1": 0.0, "ang1": 0.0},
        ),
        Segment(
            "spin left",
            "↺",
            "#83a598",
            "spins",
            2.5,
            "trapezoid",
            {"lin": 0.0, "ang": 1.0},
        ),
        Segment(
            "spin right",
            "↻",
            "#d3869b",
            "spins",
            2.5,
            "trapezoid",
            {"lin": 0.0, "ang": -1.0},
        ),
        Segment(
            "flick left", "↰", "#8ec07c", "turns", 0.5, "hold", {"lin": 0.0, "ang": 1.0}
        ),
        Segment(
            "flick right",
            "↱",
            "#fe8019",
            "turns",
            0.5,
            "hold",
            {"lin": 0.0, "ang": -1.0},
        ),
        Segment(
            "slalom",
            "⇄",
            "#83a598",
            "turns",
            4.0,
            "sine",
            {"lin": 0.5, "ang": 1.0, "cycles": 4},
        ),
        Segment(
            "arc left", "↖", "#8ec07c", "arcs", 2.5, "hold", {"lin": 0.8, "ang": 0.8}
        ),
        Segment(
            "arc right", "↗", "#fe8019", "arcs", 2.5, "hold", {"lin": 0.8, "ang": -0.8}
        ),
        Segment(
            "s-curve",
            "∿",
            "#8ec07c",
            "arcs",
            4.0,
            "sine",
            {"lin": 0.7, "ang": 0.9, "cycles": 2},
        ),
        Segment(
            "whiplash",
            "⇋",
            "#fb4934",
            "reversals",
            3.0,
            "reversal",
            {"lin": 1.0, "ang": 0.0, "flips": 6},
        ),
        Segment(
            "spin whiplash",
            "⟳",
            "#fb4934",
            "reversals",
            3.0,
            "reversal",
            {"lin": 0.0, "ang": 1.0, "flips": 6},
        ),
        Segment(
            "chirp turn",
            "≈",
            "#d3869b",
            "sweep",
            5.0,
            "chirp",
            {"lin": 0.3, "ang": 1.0, "c0": 1.0, "c1": 6.0},
        ),
        Segment(
            "full envelope",
            "✦",
            "#fabd2f",
            "sweep",
            5.0,
            "sine",
            {"lin": 1.0, "ang": 1.0, "cycles": 3},
        ),
    ]
    if fuzz:
        program.extend(fuzz_segments(fuzz, random.Random(FUZZ_SEED)))
    program.append(
        Segment("stop", "■", "#928374", "settle", 1.0, "hold", {"lin": 0.0, "ang": 0.0})
    )
    return program


def command(clock, linear, angular):
    message = TwistStamped()
    message.header.stamp = clock.now().to_msg()
    message.header.frame_id = FRAME_ID
    message.twist.linear.x = linear
    message.twist.angular.z = angular
    return message


def velocity_bar(value, limit, color):
    normalized = max(-1.0, min(1.0, value / limit)) if limit else 0.0
    center = 1.0
    return Bar(
        size=2.0,
        begin=center + min(normalized, 0.0),
        end=center + max(normalized, 0.0),
        width=GAUGE_WIDTH,
        color=color,
        bgcolor=PENDING,
    )


def gauge_grid(linear, angular, color):
    grid = Table.grid(padding=(0, 2))
    grid.add_column(justify="right", style="dim")
    grid.add_column()
    grid.add_column(justify="left")
    grid.add_row(
        "linear.x", velocity_bar(linear, LINEAR_LIMIT, color), f"{linear:+.2f} m/s"
    )
    grid.add_row(
        "angular.z",
        velocity_bar(angular, ANGULAR_LIMIT, color),
        f"{angular:+.2f} rad/s",
    )
    return grid


def sparkline(values, limit, positive, negative):
    line = Text()
    for value in list(values)[-SCOPE_WIDTH:]:
        magnitude = min(1.0, abs(value) / limit) if limit else 0.0
        line.append(
            BLOCKS[int(magnitude * (len(BLOCKS) - 1))],
            style=positive if value >= 0 else negative,
        )
    return line


def current_panel(segment, index, total, fraction, linear, angular):
    heading = Text(
        f"{segment.glyph}  {segment.name.upper()}", style=f"bold {segment.color}"
    )
    badge = Text(segment.kind.upper(), style="dim")
    bar = ProgressBar(
        total=1.0,
        completed=fraction,
        width=GAUGE_WIDTH,
        complete_style=segment.color,
        finished_style=segment.color,
    )
    body = Group(
        Align.center(heading),
        Align.center(badge),
        Text(""),
        Align.center(gauge_grid(linear, angular, segment.color)),
        Text(""),
        Align.center(bar),
    )
    return Panel(
        body,
        title=f"{index + 1}/{total}  commanding",
        border_style=segment.color,
        padding=(1, 4),
    )


def scope_panel(linear_history, angular_history):
    grid = Table.grid(padding=(0, 2))
    grid.add_column(justify="right", style="dim")
    grid.add_column()
    grid.add_row("linear", sparkline(linear_history, LINEAR_LIMIT, POSITIVE, NEGATIVE))
    grid.add_row(
        "angular", sparkline(angular_history, ANGULAR_LIMIT, ACCENT, "#d3869b")
    )
    return Panel(grid, title="scope", border_style=FRAME)


def phases_panel(program, index):
    order = []
    for segment in program:
        if segment.phase not in order:
            order.append(segment.phase)
    current = program[index].phase
    grid = Table.grid(padding=(0, 1))
    grid.add_column()
    grid.add_column(justify="left")
    grid.add_column(justify="right", style="dim")
    for phase in order:
        members = [i for i, s in enumerate(program) if s.phase == phase]
        done = sum(1 for i in members if i < index)
        if phase == current:
            marker, style = "▶", "#fabd2f"
        elif done == len(members):
            marker, style = "✓", DONE
        else:
            marker, style = "·", PENDING
        grid.add_row(
            Text(marker, style=style),
            Text(phase, style=style),
            Text(f"{done}/{len(members)}", style=style),
        )
    return Panel(grid, title="phases", border_style=FRAME)


def checks_panel(subscribers, sent, peak_linear, peak_angular):
    listening = subscribers > 0
    grid = Table.grid(padding=(0, 2))
    grid.add_column(justify="right", style="dim")
    grid.add_column(justify="left")
    grid.add_row(
        "listeners",
        Text(
            f"{subscribers}  {'✓' if listening else '⚠ none'}",
            style=DONE if listening else WARN,
        ),
    )
    grid.add_row("sent", Text(str(sent), style=ACCENT))
    grid.add_row("peak lin", Text(f"{peak_linear:.2f} m/s", style=POSITIVE))
    grid.add_row("peak ang", Text(f"{peak_angular:.2f} rad/s", style="#8ec07c"))
    return Panel(grid, title="checks", border_style=DONE if listening else WARN)


def header():
    return Rule(Text(f" cmd_vel · {COMMAND_TOPIC} ", style="bold"), style=FRAME)


def make_overall():
    return Progress(
        SpinnerColumn(),
        TextColumn("[bold]program"),
        BarColumn(bar_width=None),
        MofNCompleteColumn(),
        TimeElapsedColumn(),
        TimeRemainingColumn(),
        auto_refresh=False,
    )


def build_layout():
    layout = Layout()
    layout.split_column(
        Layout(name="header", size=1),
        Layout(name="body"),
        Layout(name="footer", size=3),
    )
    layout["body"].split_row(
        Layout(name="left", ratio=2),
        Layout(name="right", ratio=1),
    )
    layout["left"].split_column(
        Layout(name="commanding"),
        Layout(name="scope", size=6),
    )
    layout["right"].split_column(
        Layout(name="phases"),
        Layout(name="checks", size=8),
    )
    return layout


def render(layout, frame):
    segment = frame.program[frame.index]
    linear = frame.linear_history[-1] if frame.linear_history else 0.0
    angular = frame.angular_history[-1] if frame.angular_history else 0.0
    layout["header"].update(header())
    layout["commanding"].update(
        current_panel(
            segment, frame.index, len(frame.program), frame.fraction, linear, angular
        )
    )
    layout["scope"].update(scope_panel(frame.linear_history, frame.angular_history))
    layout["phases"].update(phases_panel(frame.program, frame.index))
    layout["checks"].update(
        checks_panel(
            frame.subscribers, frame.sent, frame.peak_linear, frame.peak_angular
        )
    )
    layout["footer"].update(Panel(frame.progress, border_style=FRAME, padding=(0, 1)))


def fuzz_count():
    if "--no-fuzz" in sys.argv:
        return 0
    for arg in sys.argv:
        if arg.startswith("--fuzz="):
            return int(arg.split("=", 1)[1])
    return DEFAULT_FUZZ


def selftest():
    failures = 0

    def check(label, condition):
        nonlocal failures
        failures += not condition
        print(f"{'ok  ' if condition else 'FAIL'}  {label}")

    check("trapezoid rise", trapezoid_scale(0.0, 0.25, 0.25) == 0.0)
    check("trapezoid cruise", trapezoid_scale(0.5, 0.25, 0.25) == 1.0)
    check("trapezoid fall", abs(trapezoid_scale(1.0, 0.25, 0.25)) < 1e-9)
    check("hold", sample("hold", {"lin": 1.0, "ang": 0.0}, 0.5) == (1.0, 0.0))
    ramp_lin, _ = sample(
        "ramp", {"lin0": 0.0, "ang0": 0.0, "lin1": 1.0, "ang1": 0.0}, 0.5
    )
    check("ramp midpoint", abs(ramp_lin - 0.5) < 1e-9)
    forward = sample("reversal", {"lin": 1.0, "ang": 0.0, "flips": 2}, 0.1)[0]
    backward = sample("reversal", {"lin": 1.0, "ang": 0.0, "flips": 2}, 0.6)[0]
    check("reversal flips", forward == 1.0 and backward == -1.0)
    _, sine_ang = sample("sine", {"lin": 0.0, "ang": 1.0, "cycles": 1}, 0.25)
    check("sine peak", abs(sine_ang - 1.0) < 1e-9)
    program = build_program(4)
    check("program builds", len(program) > 16)
    check("kinds known", all(s.kind in KNOWN_KINDS for s in program))
    check("durations positive", all(s.duration > 0 for s in program))
    print(f"\n{'PASS' if not failures else 'FAIL'}")
    return 1 if failures else 0


def preview():
    program = build_program(fuzz_count())
    index = next(i for i, s in enumerate(program) if s.kind == "sine")
    segment = program[index]
    linear_history = deque(maxlen=SCOPE_WIDTH)
    angular_history = deque(maxlen=SCOPE_WIDTH)
    for step in range(SCOPE_WIDTH):
        linear, angular = scaled_sample(segment, step / SCOPE_WIDTH)
        linear_history.append(linear)
        angular_history.append(angular)
    progress = make_overall()
    progress.advance(progress.add_task("run", total=100), 62)
    frame = Frame(
        program, index, 0.6, linear_history, angular_history, 2, 137, 2.0, 2.0, progress
    )
    layout = build_layout()
    render(layout, frame)
    Console(width=118, height=30).print(layout)
    Console().print(checks_panel(0, 0, 0.0, 0.0))


def main():
    if "--selftest" in sys.argv:
        sys.exit(selftest())
    if "--preview" in sys.argv:
        preview()
        return
    program = build_program(fuzz_count())
    rclpy.init()
    node = rclpy.create_node("cmd_vel_test")
    publisher = node.create_publisher(TwistStamped, COMMAND_TOPIC, 10)
    clock = node.get_clock()
    period = 1.0 / RATE_HZ
    layout = build_layout()
    progress = make_overall()
    task = progress.add_task("run", total=sum(segment_ticks(s) for s in program))
    frame = Frame(
        program,
        0,
        0.0,
        deque(maxlen=SCOPE_WIDTH),
        deque(maxlen=SCOPE_WIDTH),
        0,
        0,
        0.0,
        0.0,
        progress,
    )
    try:
        for _ in range(int(SETTLE_SECONDS * RATE_HZ)):
            publisher.publish(command(clock, 0.0, 0.0))
            frame.sent += 1
            rclpy.spin_once(node, timeout_sec=0.0)
            time.sleep(period)
        with Live(layout, refresh_per_second=RATE_HZ, screen=True):
            for index, segment in enumerate(program):
                ticks = segment_ticks(segment)
                for tick in range(ticks):
                    linear, angular = scaled_sample(segment, (tick + 1) / ticks)
                    publisher.publish(command(clock, linear, angular))
                    frame.index = index
                    frame.fraction = (tick + 1) / ticks
                    frame.sent += 1
                    frame.linear_history.append(linear)
                    frame.angular_history.append(angular)
                    frame.peak_linear = max(frame.peak_linear, abs(linear))
                    frame.peak_angular = max(frame.peak_angular, abs(angular))
                    frame.subscribers = node.count_subscribers(COMMAND_TOPIC)
                    progress.advance(task)
                    render(layout, frame)
                    rclpy.spin_once(node, timeout_sec=0.0)
                    time.sleep(period)
    except KeyboardInterrupt:
        pass
    finally:
        publisher.publish(command(clock, 0.0, 0.0))
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
