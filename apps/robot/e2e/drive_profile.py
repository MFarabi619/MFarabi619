#!/usr/bin/env python3

from collections import deque
from dataclasses import dataclass

import numpy as np
import rclpy
from geometry_msgs.msg import TwistStamped
from message_filters import Cache, Subscriber
from nav_msgs.msg import Odometry
from rclpy.duration import Duration
from rclpy.node import Node
from rclpy.qos import QoSHistoryPolicy, QoSProfile, QoSReliabilityPolicy
from rich.align import Align
from rich.box import ROUNDED
from rich.console import Console, Group
from rich.live import Live
from rich.panel import Panel
from rich.table import Table
from rich.text import Text

LINEAR_MAX_VELOCITY = 2.0
ANGULAR_MAX_VELOCITY = 3.0
LINEAR_MAX_ACCELERATION = 8.0
LINEAR_MAX_JERK = 60.0

RAMP_LINEAR_ACCELERATION = 1.5
RAMP_ANGULAR_ACCELERATION = 2.5

CONTROL_RATE_HZ = 50.0
RENDER_RATE_HZ = 15.0
SETTLE_WINDOW_SECONDS = 0.75
ODOM_TIMEOUT_SECONDS = 15.0
MOTION_EPSILON = 0.02

SETTLE_LINEAR_TOLERANCE = 0.12
SETTLE_ANGULAR_TOLERANCE = 0.2
ACCELERATION_TOLERANCE_FRACTION = 0.25
ACCELERATION_CEILING_FRACTION = 1.15

PROGRESS_BAR_WIDTH = 30
SPARK_SAMPLE_COUNT = 48

FORWARD_COLOR = "#b8bb26"
REVERSE_COLOR = "#fe8019"
TURN_COLOR = "#fabd2f"
STOP_COLOR = "#fb4934"
IDLE_COLOR = "#665c54"
SPARK_GLYPHS = "▁▂▃▄▅▆▇█"


@dataclass
class Phase:
    name: str
    kind: str
    linear: float
    angular: float
    ramp_seconds: float
    hold_seconds: float
    check: str
    swing_seconds: float = 0.0

    @property
    def duration_seconds(self):
        return self.ramp_seconds + self.hold_seconds


@dataclass
class PhaseResult:
    name: str
    commanded: str
    measured: str
    delta: str
    passed: bool


PHASES = [
    Phase("ramp up", "ramp", LINEAR_MAX_VELOCITY, 0.0, 1.6, 2.0, "linear"),
    Phase("ramp down", "ramp", 0.0, 0.0, 1.6, 1.0, "linear"),
    Phase("reverse", "ramp", -LINEAR_MAX_VELOCITY, 0.0, 1.6, 2.0, "linear"),
    Phase("halt", "ramp", 0.0, 0.0, 1.4, 0.6, "none"),
    Phase("spin ccw", "ramp", 0.0, ANGULAR_MAX_VELOCITY, 1.3, 2.0, "angular"),
    Phase("spin cw", "ramp", 0.0, -ANGULAR_MAX_VELOCITY, 1.3, 2.0, "angular"),
    Phase("halt", "ramp", 0.0, 0.0, 1.4, 0.6, "none"),
    Phase("arc left", "ramp", 1.0, 1.0, 1.3, 2.0, "arc"),
    Phase("arc right", "ramp", 1.0, -1.0, 1.3, 2.0, "arc"),
    Phase("halt", "ramp", 0.0, 0.0, 1.4, 0.6, "none"),
    Phase("fast reversal", "swing", LINEAR_MAX_VELOCITY, 0.0, 0.0, 4.0, "swing", swing_seconds=0.5),
    Phase("accel probe", "swing", LINEAR_MAX_VELOCITY, 0.0, 0.0, 5.0, "accel", swing_seconds=1.6),
    Phase("halt", "ramp", 0.0, 0.0, 1.2, 1.0, "none"),
]


class ProfileComplete(Exception):
    pass


def moving_average(values, window):
    if len(values) < window:
        return np.asarray(values, dtype=float)
    kernel = np.ones(window) / window
    return np.convolve(values, kernel, mode="same")


class DriveProfile(Node):
    def __init__(self):
        super().__init__("drive_profile")
        self.command_topic = self.declare_parameter(
            "command_topic", "/joy_teleop/cmd_vel"
        ).value
        self.odom_topic = self.declare_parameter(
            "odom_topic", "diff_drive_controller/odom"
        ).value

        self.command_linear = 0.0
        self.command_angular = 0.0
        self.phase_index = 0
        self.phase_start = None
        self.is_armed = False
        self.started_at = self.get_clock().now()
        self.latest_odometry = None
        self.linear_samples = deque(maxlen=SPARK_SAMPLE_COUNT)
        self.results = []
        self.live = None

        self.publisher = self.create_publisher(TwistStamped, self.command_topic, 10)
        odom_qos = QoSProfile(
            reliability=QoSReliabilityPolicy.RELIABLE,
            history=QoSHistoryPolicy.KEEP_LAST,
            depth=50,
        )
        self.odom = Subscriber(self, Odometry, self.odom_topic, qos_profile=odom_qos)
        self.odom_cache = Cache(self.odom, cache_size=400)
        self.odom_cache.registerCallback(self.on_odom)

        self.create_timer(1.0 / CONTROL_RATE_HZ, self.on_control)
        self.create_timer(1.0 / RENDER_RATE_HZ, self.on_render)

    def on_odom(self, message):
        self.latest_odometry = message
        self.linear_samples.append(message.twist.twist.linear.x)

    def on_control(self):
        now = self.get_clock().now()
        if not self.is_armed:
            if self.latest_odometry is not None:
                self.is_armed = True
                self.phase_start = now
            elif (now - self.started_at) > Duration(seconds=ODOM_TIMEOUT_SECONDS):
                raise ProfileComplete
            return

        phase = PHASES[self.phase_index]
        elapsed = (now - self.phase_start).nanoseconds * 1e-9
        target_linear, target_angular = self.target(phase, elapsed)
        self.step_command(phase, target_linear, target_angular)
        self.publish()

        if elapsed >= phase.duration_seconds:
            self.verify(phase)
            self.phase_index += 1
            self.phase_start = now
            if self.phase_index >= len(PHASES):
                self.finish()

    def target(self, phase, elapsed):
        if phase.kind == "swing":
            sign = 1.0 if int(elapsed / phase.swing_seconds) % 2 == 0 else -1.0
            return sign * phase.linear, phase.angular
        return phase.linear, phase.angular

    def step_command(self, phase, target_linear, target_angular):
        if phase.kind == "swing":
            self.command_linear = target_linear
            self.command_angular = target_angular
            return
        dt = 1.0 / CONTROL_RATE_HZ
        linear_step = RAMP_LINEAR_ACCELERATION * dt
        angular_step = RAMP_ANGULAR_ACCELERATION * dt
        self.command_linear += float(
            np.clip(target_linear - self.command_linear, -linear_step, linear_step)
        )
        self.command_angular += float(
            np.clip(target_angular - self.command_angular, -angular_step, angular_step)
        )

    def publish(self):
        message = TwistStamped()
        message.header.stamp = self.get_clock().now().to_msg()
        message.header.frame_id = "base_link"
        message.twist.linear.x = self.command_linear
        message.twist.angular.z = self.command_angular
        self.publisher.publish(message)

    def settle_mean(self):
        latest_time = self.odom_cache.getLatestTime()
        if latest_time is None:
            return None, None
        messages = self.odom_cache.getInterval(
            latest_time - Duration(seconds=SETTLE_WINDOW_SECONDS), latest_time
        )
        if not messages:
            return None, None
        linear = float(np.mean([m.twist.twist.linear.x for m in messages]))
        angular = float(np.mean([m.twist.twist.angular.z for m in messages]))
        return linear, angular

    def phase_series(self):
        latest_time = self.odom_cache.getLatestTime()
        if latest_time is None or self.phase_start is None:
            return None, None
        messages = self.odom_cache.getInterval(self.phase_start, latest_time)
        if len(messages) < 5:
            return None, None
        times = np.array(
            [rclpy.time.Time.from_msg(m.header.stamp).nanoseconds * 1e-9 for m in messages]
        )
        linear = np.array([m.twist.twist.linear.x for m in messages])
        return times, linear

    def acceleration_metrics(self):
        times, linear = self.phase_series()
        if times is None:
            return None, None
        smoothed = moving_average(linear, 3)
        acceleration = np.gradient(smoothed, times)
        jerk = np.gradient(acceleration, times)
        return float(np.max(np.abs(acceleration))), float(np.max(np.abs(jerk)))

    def verify(self, phase):
        if phase.check == "none":
            return
        if phase.check in ("linear", "angular", "arc"):
            self.verify_settle(phase)
        else:
            self.verify_acceleration(phase)

    def verify_settle(self, phase):
        linear, angular = self.settle_mean()
        if linear is None:
            self.results.append(PhaseResult(phase.name, "-", "no odom", "-", False))
            return
        if phase.check == "linear":
            passed = abs(linear - phase.linear) <= SETTLE_LINEAR_TOLERANCE
            self.results.append(
                PhaseResult(
                    phase.name,
                    f"{phase.linear:+.2f} m/s",
                    f"{linear:+.2f} m/s",
                    f"{abs(linear - phase.linear):.2f}",
                    passed,
                )
            )
        elif phase.check == "angular":
            passed = abs(angular - phase.angular) <= SETTLE_ANGULAR_TOLERANCE
            self.results.append(
                PhaseResult(
                    phase.name,
                    f"{phase.angular:+.2f} rad/s",
                    f"{angular:+.2f} rad/s",
                    f"{abs(angular - phase.angular):.2f}",
                    passed,
                )
            )
        else:
            passed = (
                abs(linear - phase.linear) <= SETTLE_LINEAR_TOLERANCE
                and abs(angular - phase.angular) <= SETTLE_ANGULAR_TOLERANCE
            )
            self.results.append(
                PhaseResult(
                    phase.name,
                    f"{phase.linear:+.2f} m/s · {phase.angular:+.2f} rad/s",
                    f"{linear:+.2f} m/s · {angular:+.2f} rad/s",
                    f"{max(abs(linear - phase.linear), abs(angular - phase.angular)):.2f}",
                    passed,
                )
            )

    def verify_acceleration(self, phase):
        measured, jerk = self.acceleration_metrics()
        ceiling = LINEAR_MAX_ACCELERATION * ACCELERATION_CEILING_FRACTION
        if measured is None:
            self.results.append(PhaseResult(phase.name, "-", "no odom", "-", False))
            return
        if phase.check == "accel":
            floor = LINEAR_MAX_ACCELERATION * (1.0 - ACCELERATION_TOLERANCE_FRACTION)
            passed = floor <= measured <= ceiling
            self.results.append(
                PhaseResult(
                    phase.name,
                    f"≈{LINEAR_MAX_ACCELERATION:.1f} m/s²",
                    f"{measured:.1f} m/s²  jerk≈{jerk:.0f}",
                    f"{abs(measured - LINEAR_MAX_ACCELERATION):.1f}",
                    passed,
                )
            )
        else:
            passed = measured <= ceiling
            self.results.append(
                PhaseResult(
                    phase.name,
                    f"≤{ceiling:.1f} m/s²",
                    f"{measured:.1f} m/s²",
                    f"{max(0.0, measured - ceiling):.1f}",
                    passed,
                )
            )

    def finish(self):
        self.command_linear = 0.0
        self.command_angular = 0.0
        for _ in range(5):
            self.publish()
        raise ProfileComplete

    def color_for(self, linear, angular):
        if abs(linear) > MOTION_EPSILON:
            return FORWARD_COLOR if linear > 0.0 else REVERSE_COLOR
        if abs(angular) > MOTION_EPSILON:
            return TURN_COLOR
        return STOP_COLOR

    def bar(self, value, span, color, width=28):
        half = width // 2
        magnitude = int(round(float(np.clip(abs(value) / span, 0.0, 1.0)) * half))
        if value >= 0.0:
            body = " " * half + "┃" + "█" * magnitude + "·" * (half - magnitude)
        else:
            body = "·" * (half - magnitude) + "█" * magnitude + "┃" + " " * half
        return Text(body, style=color)

    def sparkline(self):
        if not self.linear_samples:
            return Text("")
        values = np.asarray(self.linear_samples)
        span = max(LINEAR_MAX_VELOCITY, float(np.max(np.abs(values))), 1e-6)
        steps = len(SPARK_GLYPHS) - 1
        index = np.clip(((values + span) / (2.0 * span) * steps), 0, steps).astype(int)
        glyphs = "".join(SPARK_GLYPHS[i] for i in index)
        return Text(glyphs, style=FORWARD_COLOR)

    def render(self):
        if not self.is_armed:
            return Panel(
                Align.center(
                    Text(f"waiting for odometry on {self.odom_topic}", style="yellow")
                ),
                title="robot3 · drive-profile e2e",
                border_style=IDLE_COLOR,
            )
        phase = PHASES[min(self.phase_index, len(PHASES) - 1)]
        elapsed = (self.get_clock().now() - self.phase_start).nanoseconds * 1e-9
        progress = int(
            np.clip(elapsed / max(phase.duration_seconds, 1e-6), 0, 1) * PROGRESS_BAR_WIDTH
        )
        color = self.color_for(self.command_linear, self.command_angular)

        head = Table.grid(padding=(0, 2))
        head.add_column(justify="left")
        head.add_column(justify="right")
        head.add_row(
            Text(f"◆ {phase.name}", style=f"bold {color}"),
            Text(f"phase {self.phase_index + 1}/{len(PHASES)}  ·  {phase.kind}", style="dim"),
        )
        head.add_row(
            Text("█" * progress + "░" * (PROGRESS_BAR_WIDTH - progress), style=color),
            Text(f"{elapsed:4.1f}s / {phase.duration_seconds:.1f}s", style="dim"),
        )

        measured_linear = (
            self.latest_odometry.twist.twist.linear.x if self.latest_odometry else 0.0
        )
        measured_angular = (
            self.latest_odometry.twist.twist.angular.z if self.latest_odometry else 0.0
        )
        gauges = Table.grid(padding=(0, 1))
        gauges.add_column(justify="right", width=14)
        gauges.add_column()
        gauges.add_column(justify="right", width=14)
        gauges.add_row(
            Text("cmd linear", style="dim"),
            self.bar(self.command_linear, LINEAR_MAX_VELOCITY, color),
            Text(f"{self.command_linear:+.2f} m/s", style=color),
        )
        gauges.add_row(
            Text("odom linear", style="dim"),
            self.bar(measured_linear, LINEAR_MAX_VELOCITY, color),
            Text(f"{measured_linear:+.2f} m/s", style=color),
        )
        turn_color = TURN_COLOR if abs(self.command_angular) > MOTION_EPSILON else IDLE_COLOR
        gauges.add_row(
            Text("cmd angular", style="dim"),
            self.bar(self.command_angular, ANGULAR_MAX_VELOCITY, turn_color),
            Text(f"{self.command_angular:+.2f} rad/s", style=turn_color),
        )
        gauges.add_row(
            Text("odom angular", style="dim"),
            self.bar(measured_angular, ANGULAR_MAX_VELOCITY, turn_color),
            Text(f"{measured_angular:+.2f} rad/s", style=turn_color),
        )
        gauges.add_row(Text("odom vx", style="dim"), self.sparkline(), Text(""))

        passed_count = sum(1 for r in self.results if r.passed)
        tally = Text.assemble(
            ("✓ ", FORWARD_COLOR),
            (f"{passed_count} passed   ", "default"),
            ("✗ ", STOP_COLOR),
            (f"{len(self.results) - passed_count} failed", "default"),
        )
        return Panel(
            Group(head, Text(""), gauges, Text(""), tally),
            title="🌾 robot3 · drive-profile e2e",
            border_style=color,
        )

    def on_render(self):
        if self.live is not None:
            self.live.update(self.render())

    def summary(self):
        table = Table(title="drive-profile e2e — results", box=ROUNDED, title_style="bold")
        table.add_column("phase")
        table.add_column("commanded")
        table.add_column("measured")
        table.add_column("Δ", justify="right")
        table.add_column("result", justify="center")
        for result in self.results:
            mark = Text("PASS", style=f"bold {FORWARD_COLOR}") if result.passed else Text(
                "FAIL", style=f"bold {STOP_COLOR}"
            )
            table.add_row(result.name, result.commanded, result.measured, result.delta, mark)
        passed_count = sum(1 for r in self.results if r.passed)
        table.caption = f"{passed_count}/{len(self.results)} passed"
        table.caption_style = "bold"
        return table


def main():
    rclpy.init()
    node = DriveProfile()
    console = Console()
    try:
        with Live(node.render(), console=console, refresh_per_second=RENDER_RATE_HZ) as live:
            node.live = live
            rclpy.spin(node)
    except (ProfileComplete, KeyboardInterrupt):
        pass
    finally:
        console.print(node.summary())
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == "__main__":
    main()
