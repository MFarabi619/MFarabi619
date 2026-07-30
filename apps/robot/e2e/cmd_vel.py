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


import time

from geometry_msgs.msg import TwistStamped
import rclpy
from rich.align import Align
from rich.console import Console, Group
from rich.live import Live
from rich.panel import Panel
from rich.table import Table
from rich.text import Text

COMMAND_TOPIC = '/joy_teleop/cmd_vel'
FRAME_ID = 'base_link'
RATE_HZ = 10.0
MOVE_SECONDS = 1.5
BAR_WIDTH = 28

MOVES = [
    ('forward', '↑', 1.0, 0.0, '#b8bb26'),
    ('backward', '↓', -1.0, 0.0, '#fabd2f'),
    ('left', '↺', 0.0, 1.0, '#83a598'),
    ('right', '↻', 0.0, -1.0, '#d3869b'),
    ('stop', '■', 0.0, 0.0, '#665c54'),
]


def command(clock, linear, angular):
    message = TwistStamped()
    message.header.stamp = clock.now().to_msg()
    message.header.frame_id = FRAME_ID
    message.twist.linear.x = linear
    message.twist.angular.z = angular
    return message


def panel(name, glyph, linear, angular, color, progress):
    heading = Text(f'{glyph}  {name.upper()}', style=f'bold {color}', justify='center')
    filled = int(BAR_WIDTH * progress)
    bar = Text('━' * filled + '╌' * (BAR_WIDTH - filled), style=color, justify='center')
    values = Table.grid(padding=(0, 3))
    values.add_column(justify='right', style='dim')
    values.add_column(justify='left')
    values.add_row('linear.x', f'{linear:+.2f} m/s')
    values.add_row('angular.z', f'{angular:+.2f} rad/s')
    body = Group(heading, Text(''), bar, Text(''), Align.center(values))
    return Panel(body, title='cmd_vel', subtitle=COMMAND_TOPIC,
                 border_style=color, padding=(1, 6))


def main():
    rclpy.init()
    node = rclpy.create_node('cmd_vel_demo')
    publisher = node.create_publisher(TwistStamped, COMMAND_TOPIC, 10)
    clock = node.get_clock()
    period = 1.0 / RATE_HZ
    ticks = int(MOVE_SECONDS * RATE_HZ)
    try:
        for _ in range(int(RATE_HZ)):
            publisher.publish(command(clock, 0.0, 0.0))
            time.sleep(period)
        with Live(console=Console(), refresh_per_second=RATE_HZ, screen=False) as live:
            for name, glyph, linear, angular, color in MOVES:
                for tick in range(ticks):
                    publisher.publish(command(clock, linear, angular))
                    live.update(panel(name, glyph, linear, angular, color, (tick + 1) / ticks))
                    time.sleep(period)
    except KeyboardInterrupt:
        pass
    finally:
        publisher.publish(command(clock, 0.0, 0.0))
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
