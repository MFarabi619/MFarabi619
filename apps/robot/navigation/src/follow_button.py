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


import rclpy
from rclpy.node import Node
from sensor_msgs.msg import Joy
from std_srvs.srv import SetBool, Trigger


class FollowButton(Node):
    def __init__(self):
        super().__init__('follow_button')
        self.button_index = self.declare_parameter('button_index', 1).value
        follow_node = self.declare_parameter('follow_node', 'person_follow').value
        self.enable_client = self.create_client(SetBool, f'{follow_node}/enable')
        self.reset_parameters_client = self.create_client(
            Trigger, f'{follow_node}/reset_parameters')
        # TODO: read whether follow is on from the follow node instead of tracking it here, so
        # follow turned on elsewhere (enable_behavior) doesn't take two presses to turn off.
        self.is_following = False
        self.is_request_pending = False
        self.was_pressed = None
        self.create_subscription(Joy, 'joy_teleop/joy', self.on_joy, 10)

    def on_joy(self, message):
        is_pressed = (len(message.buttons) > self.button_index
                      and message.buttons[self.button_index] == 1)
        was_pressed, self.was_pressed = self.was_pressed, is_pressed
        if is_pressed and was_pressed is False and not self.is_request_pending:
            self.toggle()

    def toggle(self):
        if self.is_following:
            self.request_enable(False)
        else:
            self.request_reset_parameters()

    def request_reset_parameters(self):
        if not self.reset_parameters_client.service_is_ready():
            self.get_logger().warning('follow is not running')
            return
        self.is_request_pending = True
        self.reset_parameters_client.call_async(Trigger.Request()).add_done_callback(
            self.on_reset_parameters)

    def on_reset_parameters(self, future):
        response = future.result()
        if response is None or not response.success:
            self.is_request_pending = False
            self.get_logger().warning('follow did not reset its parameters')
            return
        self.request_enable(True)

    def request_enable(self, is_enabled):
        if not self.enable_client.service_is_ready():
            self.is_request_pending = False
            self.get_logger().warning('follow is not running')
            return
        self.is_request_pending = True
        self.enable_client.call_async(SetBool.Request(data=is_enabled)).add_done_callback(
            lambda future: self.on_enable(future, is_enabled))

    def on_enable(self, future, is_enabled):
        self.is_request_pending = False
        response = future.result()
        if response is None or not response.success:
            self.get_logger().warning('follow did not switch')
            return
        self.is_following = is_enabled
        self.get_logger().info('follow on' if is_enabled else 'follow off')


def main():
    rclpy.init()
    node = FollowButton()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
