#!/usr/bin/env python3

import rclpy
from nav_msgs.msg import Odometry
from rclpy.node import Node
from rclpy.qos import QoSHistoryPolicy, QoSProfile, QoSReliabilityPolicy
from rich.align import Align
from rich.box import ROUNDED
from rich.console import Console, Group
from rich.live import Live
from rich.panel import Panel
from rich.table import Table
from rich.text import Text

RED_CONE_COLOR = "#fb4934"
ORANGE_CONE_COLOR = "#fe8019"
YELLOW_CONE_COLOR = "#fabd2f"
BLUE_CONE_COLOR = "#83a598"
CLEARED_COLOR = "#b8bb26"
RUNNING_COLOR = "#fabd2f"
IDLE_COLOR = "#665c54"

SPAWN_X_METERS = -14.0
SPAWN_Y_METERS = -19.0
CONE_LINE_Y_METERS = -19.0
GATE_BAND_METERS = 4.0
START_LINE_X_METERS = -13.0
RENDER_RATE_HZ = 15.0

CONE_LAYOUT = [
    ("red", -12.0, RED_CONE_COLOR),
    ("orange", -10.0, ORANGE_CONE_COLOR),
    ("yellow", -8.0, YELLOW_CONE_COLOR),
    ("blue", -6.0, BLUE_CONE_COLOR),
]


class ConeDrill(Node):
    def __init__(self):
        super().__init__("cone_drill")
        odom_topic = self.declare_parameter(
            "odom_topic", "diff_drive_controller/odom").value
        self.robot = None
        self.gates_cleared = 0
        self.started = False
        self.finished = False
        self.start_time = None
        self.finish_time = None
        self.live = None

        odom_qos = QoSProfile(
            reliability=QoSReliabilityPolicy.RELIABLE,
            history=QoSHistoryPolicy.KEEP_LAST,
            depth=50,
        )
        self.create_subscription(Odometry, odom_topic, self.on_odom, odom_qos)
        self.create_timer(1.0 / RENDER_RATE_HZ, self.on_render)

    def on_odom(self, message):
        position = message.pose.pose.position
        self.robot = (SPAWN_X_METERS + position.x, SPAWN_Y_METERS + position.y)
        self.update_score()

    def update_score(self):
        now = self.get_clock().now()
        if not self.started:
            if self.robot[0] < START_LINE_X_METERS:
                return
            self.started = True
            self.start_time = now
        while (self.gates_cleared < len(CONE_LAYOUT)
               and self.robot[0] >= CONE_LAYOUT[self.gates_cleared][1]
               and abs(self.robot[1] - CONE_LINE_Y_METERS) < GATE_BAND_METERS):
            self.gates_cleared += 1
        if self.gates_cleared >= len(CONE_LAYOUT) and not self.finished:
            self.finished = True
            self.finish_time = now

    def elapsed(self):
        if not self.started:
            return 0.0
        end = self.finish_time if self.finished else self.get_clock().now()
        return (end - self.start_time).nanoseconds * 1e-9

    def render(self):
        if self.robot is None:
            return Panel(
                Align.center(Text("waiting for odometry…", style="yellow")),
                title="🚦 cone drill", border_style=IDLE_COLOR)

        table = Table.grid(padding=(0, 3))
        table.add_column()
        table.add_column()
        for index, (label, _, color) in enumerate(CONE_LAYOUT):
            gate = (Text("✓ gate", style=CLEARED_COLOR) if index < self.gates_cleared
                    else Text("○ gate", style=IDLE_COLOR))
            table.add_row(Text(f"◉ {label}", style=color), gate)

        footer = Text.assemble(
            ("gates ", "dim"), (f"{self.gates_cleared}/{len(CONE_LAYOUT)}", CLEARED_COLOR),
            ("   time ", "dim"), (f"{self.elapsed():5.1f}s", "default"),
            ("   pos ", "dim"), (f"({self.robot[0]:+.1f}, {self.robot[1]:+.1f})", "dim"))

        body = [table, Text(""), footer]
        if self.finished:
            body += [Text(""), self.scorecard()]
        border = (CLEARED_COLOR if self.finished
                  else RUNNING_COLOR if self.started else IDLE_COLOR)
        return Panel(Group(*body), title="🚦 cone drill", border_style=border)

    def scorecard(self):
        summary = Text.assemble(
            ("FINISHED", f"bold {CLEARED_COLOR}"), ("    ", "default"),
            (f"{self.elapsed():.1f}s", "bold"),
            (f"    {self.gates_cleared}/{len(CONE_LAYOUT)} gates", "default"))
        return Panel(summary, border_style=CLEARED_COLOR, box=ROUNDED)

    def on_render(self):
        if self.live is not None:
            self.live.update(self.render())


def main():
    rclpy.init()
    node = ConeDrill()
    console = Console()
    try:
        with Live(node.render(), console=console, refresh_per_second=RENDER_RATE_HZ) as live:
            node.live = live
            rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        console.print(node.render())
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == "__main__":
    main()
