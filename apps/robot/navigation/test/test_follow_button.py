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


import pytest
from rclpy.task import Future
from sensor_msgs.msg import Joy
from std_srvs.srv import SetBool, Trigger


class FakeClient:
    def __init__(self, response_type):
        self.response_type = response_type
        self.is_ready = True
        self.requests = []
        self.futures = []

    def service_is_ready(self):
        return self.is_ready

    def call_async(self, request):
        future = Future()
        self.requests.append(request)
        self.futures.append(future)
        return future

    def answer(self, success=True):
        self.futures.pop(0).set_result(self.response_type.Response(success=success))


@pytest.fixture
def follow_button(follow_button_node):
    follow_button_node.enable_client = FakeClient(SetBool)
    follow_button_node.reset_parameters_client = FakeClient(Trigger)
    return follow_button_node


def joy_message(is_pressed):
    message = Joy()
    message.buttons = [0, int(is_pressed), 0, 0, 0, 0, 0, 0]
    return message


def press(node):
    node.on_joy(joy_message(False))
    node.on_joy(joy_message(True))


def turn_follow_on(node):
    press(node)
    node.reset_parameters_client.answer()
    node.enable_client.answer()


def test_a_press_resets_parameters_then_turns_follow_on(follow_button):
    press(follow_button)
    assert len(follow_button.reset_parameters_client.requests) == 1
    assert follow_button.enable_client.requests == []
    follow_button.reset_parameters_client.answer()
    assert [request.data for request in follow_button.enable_client.requests] == [True]
    follow_button.enable_client.answer()
    assert follow_button.is_following


def test_a_second_press_turns_follow_off(follow_button):
    turn_follow_on(follow_button)
    press(follow_button)
    assert follow_button.enable_client.requests[-1].data is False
    follow_button.enable_client.answer()
    assert not follow_button.is_following


def test_holding_the_button_toggles_once(follow_button):
    press(follow_button)
    for _ in range(10):
        follow_button.on_joy(joy_message(True))
    assert len(follow_button.reset_parameters_client.requests) == 1


def test_a_button_held_at_startup_is_not_a_press(follow_button):
    follow_button.on_joy(joy_message(True))
    assert follow_button.reset_parameters_client.requests == []


def test_presses_while_follow_is_answering_are_ignored(follow_button):
    press(follow_button)
    press(follow_button)
    assert len(follow_button.reset_parameters_client.requests) == 1


def test_a_failed_reset_leaves_follow_off(follow_button):
    press(follow_button)
    follow_button.reset_parameters_client.answer(success=False)
    assert follow_button.enable_client.requests == []
    assert not follow_button.is_following
    press(follow_button)
    assert len(follow_button.reset_parameters_client.requests) == 2


def test_a_refused_switch_keeps_the_previous_state(follow_button):
    turn_follow_on(follow_button)
    press(follow_button)
    follow_button.enable_client.answer(success=False)
    assert follow_button.is_following


def test_nothing_is_sent_when_follow_is_not_running(follow_button):
    follow_button.reset_parameters_client.is_ready = False
    press(follow_button)
    assert follow_button.reset_parameters_client.requests == []
    assert not follow_button.is_request_pending
