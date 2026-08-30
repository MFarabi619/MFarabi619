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


import math

from geometry_msgs.msg import PoseStamped
from nav2_msgs.action import NavigateToPose
import rclpy
from rclpy.action import ActionClient
from rclpy.duration import Duration
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from std_srvs.srv import SetBool
import tf2_geometry_msgs  # noqa: F401
from tf2_ros import Buffer, TransformListener
from vision_msgs.msg import Detection2DArray

TRANSFORM_TIMEOUT = Duration(seconds=0.2)


class PersonGoalBridge(Node):
    def __init__(self):
        super().__init__('person_goal_bridge')
        detections_topic = self.declare_parameter('detections_topic', 'detections').value
        goal_update_topic = self.declare_parameter('goal_update_topic', 'goal_update').value
        self.goal_frame = self.declare_parameter('goal_frame', 'odom').value
        self.base_frame = self.declare_parameter('base_frame', 'base_link').value
        self.min_score = self.declare_parameter('min_score', 0.5).value
        self.is_enabled = self.declare_parameter('start_enabled', False).value

        self.tf_buffer = Buffer()
        self.tf_listener = TransformListener(self.tf_buffer, self)
        self.navigate_client = ActionClient(self, NavigateToPose, 'navigate_to_pose')
        self.navigate_goal_handle = None
        self.goal_update_publisher = self.create_publisher(
            PoseStamped, goal_update_topic, 10)
        self.create_service(SetBool, '~/enable', self.on_enable)
        self.create_subscription(
            Detection2DArray, detections_topic, self.on_detections,
            qos_profile_sensor_data)
        self.get_logger().info(
            f'person goal bridge: {detections_topic} -> {goal_update_topic}')

    def on_enable(self, request, response):
        self.is_enabled = request.data
        if not request.data and self.navigate_goal_handle is not None:
            self.navigate_goal_handle.cancel_goal_async()
            self.navigate_goal_handle = None
        response.success = True
        response.message = 'enabled' if request.data else 'disabled'
        return response

    def on_detections(self, message):
        if not self.is_enabled:
            return
        goal_pose = self.person_goal_pose(message)
        if goal_pose is None:
            return
        if self.navigate_goal_handle is None:
            self.send_navigate_goal(goal_pose)
        self.goal_update_publisher.publish(goal_pose)

    def person_goal_pose(self, message):
        person_point = self.best_person_point(message)
        if person_point is None:
            return None
        pose = PoseStamped()
        pose.header = message.header
        pose.pose.position = person_point
        pose.pose.orientation.w = 1.0
        try:
            goal_pose = self.tf_buffer.transform(
                pose, self.goal_frame, timeout=TRANSFORM_TIMEOUT)
            base_transform = self.tf_buffer.lookup_transform(
                self.goal_frame, self.base_frame, rclpy.time.Time())
        except Exception as error:
            self.get_logger().warning(
                f'transform to {self.goal_frame} failed: {error}',
                throttle_duration_sec=5.0)
            return None
        heading = math.atan2(
            goal_pose.pose.position.y - base_transform.transform.translation.y,
            goal_pose.pose.position.x - base_transform.transform.translation.x)
        goal_pose.pose.position.z = 0.0
        goal_pose.pose.orientation.z = math.sin(heading / 2.0)
        goal_pose.pose.orientation.w = math.cos(heading / 2.0)
        return goal_pose

    def best_person_point(self, message):
        candidates = [
            result
            for detection in message.detections
            for result in detection.results
            if result.hypothesis.score >= self.min_score
            and (result.pose.pose.position.x != 0.0
                 or result.pose.pose.position.y != 0.0
                 or result.pose.pose.position.z != 0.0)
        ]
        if not candidates:
            return None
        best_result = max(candidates, key=lambda result: result.hypothesis.score)
        return best_result.pose.pose.position

    def send_navigate_goal(self, goal_pose):
        if not self.navigate_client.server_is_ready():
            self.get_logger().warning(
                'navigate_to_pose action server not ready', throttle_duration_sec=5.0)
            return
        goal = NavigateToPose.Goal()
        goal.pose = goal_pose
        future = self.navigate_client.send_goal_async(goal)
        future.add_done_callback(self.on_navigate_goal_response)

    def on_navigate_goal_response(self, future):
        goal_handle = future.result() if future.result().accepted else None
        if goal_handle is None:
            return
        if not self.is_enabled:
            goal_handle.cancel_goal_async()
            return
        self.navigate_goal_handle = goal_handle
        goal_handle.get_result_async().add_done_callback(
            lambda _, finished=goal_handle: self.on_navigate_result(finished))

    def on_navigate_result(self, finished_goal_handle):
        if self.navigate_goal_handle is finished_goal_handle:
            self.navigate_goal_handle = None


def main():
    rclpy.init()
    node = PersonGoalBridge()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
