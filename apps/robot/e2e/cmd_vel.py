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


import argparse
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

COMMAND_TOPIC = "joy_teleop/cmd_vel"
FRAME_ID = "base_link"
COMMAND_RATE_HZ = 20.0
SETTLE_SECONDS = 1.0
GAUGE_WIDTH_CHARACTERS = 26
SCOPE_WIDTH_CHARACTERS = 60

LINEAR_FULL_SCALE_METERS_PER_SECOND = 15.0
ANGULAR_FULL_SCALE_RADIANS_PER_SECOND = 15.0

DEFAULT_FUZZ_COUNT = 6
FUZZ_SEED = 42
FUZZ_KINDS = ["hold", "ramp", "trapezoid", "sine", "reversal"]
KNOWN_KINDS = {"hold", "ramp", "trapezoid", "sine", "reversal", "chirp"}

BLOCKS = " ▁▂▃▄▅▆▇█"

DONE_COLOR = "#689d6a"
PENDING_COLOR = "#504945"
WARN_COLOR = "#fb4934"
FRAME_COLOR = "#665c54"
POSITIVE_COLOR = "#b8bb26"
NEGATIVE_COLOR = "#fb4934"
ACCENT_COLOR = "#83a598"


@dataclass
class Segment:
    name: str
    glyph: str
    color: str
    phase: str
    duration_seconds: float
    kind: str
    parameters: dict


@dataclass
class Frame:
    program: list
    index: int
    fraction: float
    linear_meters_per_second_history: deque
    angular_radians_per_second_history: deque
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


def sample(kind, parameters, fraction):
    if kind == "hold":
        return parameters["linear"], parameters["angular"]
    if kind == "ramp":
        linear_fraction = parameters["linear_start"] + (
            parameters["linear_end"] - parameters["linear_start"]
        ) * fraction
        angular_fraction = parameters["angular_start"] + (
            parameters["angular_end"] - parameters["angular_start"]
        ) * fraction
        return linear_fraction, angular_fraction
    if kind == "trapezoid":
        scale_factor = trapezoid_scale(
            fraction, parameters.get("rise", 0.25), parameters.get("fall", 0.25)
        )
        return parameters["linear"] * scale_factor, parameters["angular"] * scale_factor
    if kind == "sine":
        wave = math.sin(2 * math.pi * parameters["cycles"] * fraction)
        return parameters["linear"], parameters["angular"] * wave
    if kind == "reversal":
        sign = 1.0 if int(fraction * parameters["flips"]) % 2 == 0 else -1.0
        return parameters["linear"] * sign, parameters["angular"] * sign
    if kind == "chirp":
        low, high = parameters["c0"], parameters["c1"]
        phase_radians = 2 * math.pi * (
            low * fraction + (high - low) * fraction * fraction / 2
        )
        return parameters["linear"], parameters["angular"] * math.sin(phase_radians)
    return 0.0, 0.0


def scaled_sample(segment, fraction):
    linear_fraction, angular_fraction = sample(segment.kind, segment.parameters, fraction)
    return (
        linear_fraction * LINEAR_FULL_SCALE_METERS_PER_SECOND,
        angular_fraction * ANGULAR_FULL_SCALE_RADIANS_PER_SECOND,
    )


def segment_ticks(segment):
    return max(1, round(segment.duration_seconds * COMMAND_RATE_HZ))


def fuzz_parameters(kind, linear_fraction, angular_fraction, random_source):
    if kind == "ramp":
        return {
            "linear_start": 0.0,
            "angular_start": 0.0,
            "linear_end": linear_fraction,
            "angular_end": angular_fraction,
        }
    if kind == "sine":
        return {
            "linear": linear_fraction,
            "angular": abs(angular_fraction),
            "cycles": random_source.randint(2, 6),
        }
    if kind == "reversal":
        return {
            "linear": linear_fraction,
            "angular": angular_fraction,
            "flips": random_source.randint(3, 8),
        }
    return {"linear": linear_fraction, "angular": angular_fraction}


def fuzz_segments(count, random_source):
    segments = []
    for number in range(1, count + 1):
        kind = random_source.choice(FUZZ_KINDS)
        linear_fraction = round(random_source.uniform(-1.0, 1.0), 2)
        angular_fraction = round(random_source.uniform(-1.0, 1.0), 2)
        duration_seconds = round(random_source.uniform(1.0, 2.5), 1)
        segments.append(
            Segment(
                f"fuzz {number}",
                "⁇",
                "#928374",
                "fuzz",
                duration_seconds,
                kind,
                fuzz_parameters(kind, linear_fraction, angular_fraction, random_source),
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
            {"linear": 1.0, "angular": 0.0},
        ),
        Segment(
            "ease reverse",
            "↓",
            "#fabd2f",
            "straights",
            3.0,
            "trapezoid",
            {"linear": -1.0, "angular": 0.0},
        ),
        Segment(
            "accelerate",
            "⇈",
            "#b8bb26",
            "straights",
            2.0,
            "ramp",
            {
                "linear_start": 0.0,
                "angular_start": 0.0,
                "linear_end": 1.0,
                "angular_end": 0.0,
            },
        ),
        Segment(
            "brake",
            "⇊",
            "#fe8019",
            "straights",
            1.5,
            "ramp",
            {
                "linear_start": 1.0,
                "angular_start": 0.0,
                "linear_end": 0.0,
                "angular_end": 0.0,
            },
        ),
        Segment(
            "spin left",
            "↺",
            "#83a598",
            "spins",
            2.5,
            "trapezoid",
            {"linear": 0.0, "angular": 1.0},
        ),
        Segment(
            "spin right",
            "↻",
            "#d3869b",
            "spins",
            2.5,
            "trapezoid",
            {"linear": 0.0, "angular": -1.0},
        ),
        Segment(
            "flick left", "↰", "#8ec07c", "turns", 0.5, "hold", {"linear": 0.0, "angular": 1.0}
        ),
        Segment(
            "flick right",
            "↱",
            "#fe8019",
            "turns",
            0.5,
            "hold",
            {"linear": 0.0, "angular": -1.0},
        ),
        Segment(
            "slalom",
            "⇄",
            "#83a598",
            "turns",
            4.0,
            "sine",
            {"linear": 0.5, "angular": 1.0, "cycles": 4},
        ),
        Segment(
            "arc left", "↖", "#8ec07c", "arcs", 2.5, "hold", {"linear": 0.8, "angular": 0.8}
        ),
        Segment(
            "arc right",
            "↗",
            "#fe8019",
            "arcs",
            2.5,
            "hold",
            {"linear": 0.8, "angular": -0.8},
        ),
        Segment(
            "s-curve",
            "∿",
            "#8ec07c",
            "arcs",
            4.0,
            "sine",
            {"linear": 0.7, "angular": 0.9, "cycles": 2},
        ),
        Segment(
            "whiplash",
            "⇋",
            "#fb4934",
            "reversals",
            3.0,
            "reversal",
            {"linear": 1.0, "angular": 0.0, "flips": 6},
        ),
        Segment(
            "spin whiplash",
            "⟳",
            "#fb4934",
            "reversals",
            3.0,
            "reversal",
            {"linear": 0.0, "angular": 1.0, "flips": 6},
        ),
        Segment(
            "chirp turn",
            "≈",
            "#d3869b",
            "sweep",
            5.0,
            "chirp",
            {"linear": 0.3, "angular": 1.0, "c0": 1.0, "c1": 6.0},
        ),
        Segment(
            "full envelope",
            "✦",
            "#fabd2f",
            "sweep",
            5.0,
            "sine",
            {"linear": 1.0, "angular": 1.0, "cycles": 3},
        ),
    ]
    if fuzz:
        program.extend(fuzz_segments(fuzz, random.Random(FUZZ_SEED)))
    program.append(
        Segment(
            "stop",
            "■",
            "#928374",
            "settle",
            1.0,
            "hold",
            {"linear": 0.0, "angular": 0.0},
        )
    )
    return program


def command(clock, linear_meters_per_second, angular_radians_per_second):
    message = TwistStamped()
    message.header.stamp = clock.now().to_msg()
    message.header.frame_id = FRAME_ID
    message.twist.linear.x = linear_meters_per_second
    message.twist.angular.z = angular_radians_per_second
    return message


def velocity_bar(value, limit, color):
    normalized = max(-1.0, min(1.0, value / limit)) if limit else 0.0
    center = 1.0
    return Bar(
        size=2.0,
        begin=center + min(normalized, 0.0),
        end=center + max(normalized, 0.0),
        width=GAUGE_WIDTH_CHARACTERS,
        color=color,
        bgcolor=PENDING_COLOR,
    )


def gauge_grid(linear_meters_per_second, angular_radians_per_second, color):
    grid = Table.grid(padding=(0, 2))
    grid.add_column(justify="right", style="dim")
    grid.add_column()
    grid.add_column(justify="left")
    grid.add_row(
        "linear.x",
        velocity_bar(linear_meters_per_second, LINEAR_FULL_SCALE_METERS_PER_SECOND, color),
        f"{linear_meters_per_second:+.2f} m/s",
    )
    grid.add_row(
        "angular.z",
        velocity_bar(angular_radians_per_second, ANGULAR_FULL_SCALE_RADIANS_PER_SECOND, color),
        f"{angular_radians_per_second:+.2f} rad/s",
    )
    return grid


def sparkline(values, limit, positive, negative):
    line = Text()
    for value in list(values)[-SCOPE_WIDTH_CHARACTERS:]:
        magnitude = min(1.0, abs(value) / limit) if limit else 0.0
        line.append(
            BLOCKS[int(magnitude * (len(BLOCKS) - 1))],
            style=positive if value >= 0 else negative,
        )
    return line


def current_panel(
    segment, index, total, fraction, linear_meters_per_second, angular_radians_per_second
):
    heading = Text(
        f"{segment.glyph}  {segment.name.upper()}", style=f"bold {segment.color}"
    )
    badge = Text(segment.kind.upper(), style="dim")
    bar = ProgressBar(
        total=1.0,
        completed=fraction,
        width=GAUGE_WIDTH_CHARACTERS,
        complete_style=segment.color,
        finished_style=segment.color,
    )
    body = Group(
        Align.center(heading),
        Align.center(badge),
        Text(""),
        Align.center(
            gauge_grid(linear_meters_per_second, angular_radians_per_second, segment.color)
        ),
        Text(""),
        Align.center(bar),
    )
    return Panel(
        body,
        title=f"{index + 1}/{total}  commanding",
        border_style=segment.color,
        padding=(1, 4),
    )


def scope_panel(linear_meters_per_second_history, angular_radians_per_second_history):
    grid = Table.grid(padding=(0, 2))
    grid.add_column(justify="right", style="dim")
    grid.add_column()
    grid.add_row(
        "linear",
        sparkline(
            linear_meters_per_second_history,
            LINEAR_FULL_SCALE_METERS_PER_SECOND,
            POSITIVE_COLOR,
            NEGATIVE_COLOR,
        ),
    )
    grid.add_row(
        "angular",
        sparkline(
            angular_radians_per_second_history,
            ANGULAR_FULL_SCALE_RADIANS_PER_SECOND,
            ACCENT_COLOR,
            "#d3869b",
        ),
    )
    return Panel(grid, title="scope", border_style=FRAME_COLOR)


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
        members = [
            member_index
            for member_index, segment in enumerate(program)
            if segment.phase == phase
        ]
        done = sum(1 for member_index in members if member_index < index)
        if phase == current:
            marker, style = "▶", "#fabd2f"
        elif done == len(members):
            marker, style = "✓", DONE_COLOR
        else:
            marker, style = "·", PENDING_COLOR
        grid.add_row(
            Text(marker, style=style),
            Text(phase, style=style),
            Text(f"{done}/{len(members)}", style=style),
        )
    return Panel(grid, title="phases", border_style=FRAME_COLOR)


def checks_panel(subscribers, sent, peak_linear, peak_angular):
    listening = subscribers > 0
    grid = Table.grid(padding=(0, 2))
    grid.add_column(justify="right", style="dim")
    grid.add_column(justify="left")
    grid.add_row(
        "listeners",
        Text(
            f"{subscribers}  {'✓' if listening else '⚠ none'}",
            style=DONE_COLOR if listening else WARN_COLOR,
        ),
    )
    grid.add_row("sent", Text(str(sent), style=ACCENT_COLOR))
    grid.add_row("peak lin", Text(f"{peak_linear:.2f} m/s", style=POSITIVE_COLOR))
    grid.add_row("peak ang", Text(f"{peak_angular:.2f} rad/s", style="#8ec07c"))
    return Panel(
        grid, title="checks", border_style=DONE_COLOR if listening else WARN_COLOR
    )


def header():
    return Rule(Text(f" cmd_vel · {COMMAND_TOPIC} ", style="bold"), style=FRAME_COLOR)


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
    linear_meters_per_second = (
        frame.linear_meters_per_second_history[-1]
        if frame.linear_meters_per_second_history
        else 0.0
    )
    angular_radians_per_second = (
        frame.angular_radians_per_second_history[-1]
        if frame.angular_radians_per_second_history
        else 0.0
    )
    layout["header"].update(header())
    layout["commanding"].update(
        current_panel(
            segment,
            frame.index,
            len(frame.program),
            frame.fraction,
            linear_meters_per_second,
            angular_radians_per_second,
        )
    )
    layout["scope"].update(
        scope_panel(
            frame.linear_meters_per_second_history,
            frame.angular_radians_per_second_history,
        )
    )
    layout["phases"].update(phases_panel(frame.program, frame.index))
    layout["checks"].update(
        checks_panel(
            frame.subscribers, frame.sent, frame.peak_linear, frame.peak_angular
        )
    )
    layout["footer"].update(
        Panel(frame.progress, border_style=FRAME_COLOR, padding=(0, 1))
    )


def parse_arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument('--robot', default='taro')
    parser.add_argument('--fuzz', type=int, default=DEFAULT_FUZZ_COUNT)
    parser.add_argument('--no-fuzz', action='store_true')
    parser.add_argument('--selftest', action='store_true')
    parser.add_argument('--preview', action='store_true')
    return parser.parse_args()


def fuzz_count(arguments):
    return 0 if arguments.no_fuzz else arguments.fuzz


def selftest():
    failures = 0

    def check(label, condition):
        nonlocal failures
        failures += not condition
        print(f"{'ok  ' if condition else 'FAIL'}  {label}")

    check("trapezoid rise", trapezoid_scale(0.0, 0.25, 0.25) == 0.0)
    check("trapezoid cruise", trapezoid_scale(0.5, 0.25, 0.25) == 1.0)
    check("trapezoid fall", abs(trapezoid_scale(1.0, 0.25, 0.25)) < 1e-9)
    check("hold", sample("hold", {"linear": 1.0, "angular": 0.0}, 0.5) == (1.0, 0.0))
    ramp_linear, _ = sample(
        "ramp",
        {
            "linear_start": 0.0,
            "angular_start": 0.0,
            "linear_end": 1.0,
            "angular_end": 0.0,
        },
        0.5,
    )
    check("ramp midpoint", abs(ramp_linear - 0.5) < 1e-9)
    forward = sample("reversal", {"linear": 1.0, "angular": 0.0, "flips": 2}, 0.1)[0]
    backward = sample("reversal", {"linear": 1.0, "angular": 0.0, "flips": 2}, 0.6)[0]
    check("reversal flips", forward == 1.0 and backward == -1.0)
    _, sine_angular = sample(
        "sine", {"linear": 0.0, "angular": 1.0, "cycles": 1}, 0.25
    )
    check("sine peak", abs(sine_angular - 1.0) < 1e-9)
    program = build_program(4)
    check("program builds", len(program) > 16)
    check("kinds known", all(segment.kind in KNOWN_KINDS for segment in program))
    check(
        "durations positive",
        all(segment.duration_seconds > 0 for segment in program),
    )
    print(f"\n{'PASS' if not failures else 'FAIL'}")
    return 1 if failures else 0


def preview(fuzz):
    program = build_program(fuzz)
    index = next(
        index for index, segment in enumerate(program) if segment.kind == "sine"
    )
    segment = program[index]
    linear_meters_per_second_history = deque(maxlen=SCOPE_WIDTH_CHARACTERS)
    angular_radians_per_second_history = deque(maxlen=SCOPE_WIDTH_CHARACTERS)
    for step in range(SCOPE_WIDTH_CHARACTERS):
        linear_meters_per_second, angular_radians_per_second = scaled_sample(
            segment, step / SCOPE_WIDTH_CHARACTERS
        )
        linear_meters_per_second_history.append(linear_meters_per_second)
        angular_radians_per_second_history.append(angular_radians_per_second)
    progress = make_overall()
    progress.advance(progress.add_task("run", total=100), 62)
    frame = Frame(
        program,
        index,
        0.6,
        linear_meters_per_second_history,
        angular_radians_per_second_history,
        2,
        137,
        2.0,
        2.0,
        progress,
    )
    layout = build_layout()
    render(layout, frame)
    Console(width=118, height=30).print(layout)
    Console().print(checks_panel(0, 0, 0.0, 0.0))


def main():
    arguments = parse_arguments()
    if arguments.selftest:
        sys.exit(selftest())
    if arguments.preview:
        preview(fuzz_count(arguments))
        return
    program = build_program(fuzz_count(arguments))

    from robot_boot.zenoh_router import connect_to_zenoh_router
    from robot_machines.machine import load_machine

    namespace = load_machine(arguments.robot).namespace
    connect_to_zenoh_router(arguments.robot)
    rclpy.init()
    node = rclpy.create_node("cmd_vel", namespace=f'/{namespace}')
    publisher = node.create_publisher(TwistStamped, COMMAND_TOPIC, 10)
    clock = node.get_clock()
    period_seconds = 1.0 / COMMAND_RATE_HZ
    layout = build_layout()
    progress = make_overall()
    task = progress.add_task(
        "run", total=sum(segment_ticks(segment) for segment in program)
    )
    frame = Frame(
        program,
        0,
        0.0,
        deque(maxlen=SCOPE_WIDTH_CHARACTERS),
        deque(maxlen=SCOPE_WIDTH_CHARACTERS),
        0,
        0,
        0.0,
        0.0,
        progress,
    )
    try:
        for _ in range(int(SETTLE_SECONDS * COMMAND_RATE_HZ)):
            publisher.publish(command(clock, 0.0, 0.0))
            frame.sent += 1
            rclpy.spin_once(node, timeout_sec=0.0)
            time.sleep(period_seconds)
        with Live(layout, refresh_per_second=COMMAND_RATE_HZ, screen=True):
            for index, segment in enumerate(program):
                ticks = segment_ticks(segment)
                for tick in range(ticks):
                    linear_meters_per_second, angular_radians_per_second = scaled_sample(
                        segment, (tick + 1) / ticks
                    )
                    publisher.publish(
                        command(clock, linear_meters_per_second, angular_radians_per_second)
                    )
                    frame.index = index
                    frame.fraction = (tick + 1) / ticks
                    frame.sent += 1
                    frame.linear_meters_per_second_history.append(linear_meters_per_second)
                    frame.angular_radians_per_second_history.append(
                        angular_radians_per_second
                    )
                    frame.peak_linear = max(
                        frame.peak_linear, abs(linear_meters_per_second)
                    )
                    frame.peak_angular = max(
                        frame.peak_angular, abs(angular_radians_per_second)
                    )
                    frame.subscribers = node.count_subscribers(COMMAND_TOPIC)
                    progress.advance(task)
                    render(layout, frame)
                    rclpy.spin_once(node, timeout_sec=0.0)
                    time.sleep(period_seconds)
    except KeyboardInterrupt:
        pass
    finally:
        publisher.publish(command(clock, 0.0, 0.0))
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
