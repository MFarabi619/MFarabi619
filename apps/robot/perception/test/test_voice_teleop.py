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


from rclpy.duration import Duration
from rclpy.parameter import Parameter
from std_msgs.msg import String
from std_srvs.srv import SetBool


def spoken(word):
    return String(data=word)


def capture(node):
    twists = []
    node.cmd_vel_publisher.publish = twists.append
    return twists


def age_last_word(node, module):
    node.latest_word_time -= Duration(
        seconds=module.COMPOSITION_WINDOW_SECONDS * 2.0)


def test_forward_drives_immediately_and_keeps_driving(voice_teleop_node):
    twists = capture(voice_teleop_node)
    voice_teleop_node.on_word(spoken('forward'))
    assert len(twists) == 1
    voice_teleop_node.publish_held_twist()
    voice_teleop_node.publish_held_twist()
    assert len(twists) == 3
    assert all(
        twist.twist.linear.x == voice_teleop_node.forward_speed_mps
        for twist in twists)


def test_straight_and_back_are_synonyms(voice_teleop_node):
    twists = capture(voice_teleop_node)
    voice_teleop_node.on_word(spoken('straight'))
    assert twists[-1].twist.linear.x == voice_teleop_node.forward_speed_mps
    voice_teleop_node.on_word(spoken('stop'))
    voice_teleop_node.on_word(spoken('back'))
    assert twists[-1].twist.linear.x == -voice_teleop_node.forward_speed_mps


def test_every_accepted_word_is_acknowledged(voice_teleop_node):
    responses = []
    voice_teleop_node.speech_publisher.publish = responses.append
    capture(voice_teleop_node)
    voice_teleop_node.on_word(spoken('forward'))
    voice_teleop_node.on_word(spoken('banana'))
    assert [response.data for response in responses] == ['acknowledged']


def test_a_repeated_stop_is_acknowledged_once(voice_teleop_node):
    responses = []
    voice_teleop_node.speech_publisher.publish = responses.append
    capture(voice_teleop_node)
    voice_teleop_node.on_word(spoken('forward'))
    voice_teleop_node.on_word(spoken('stop'))
    voice_teleop_node.on_word(spoken('stop'))
    assert len(responses) == 2


def test_acknowledgements_rotate_through_the_phrases(
        voice_teleop_node, voice_teleop_module):
    responses = []
    voice_teleop_node.speech_publisher.publish = responses.append
    capture(voice_teleop_node)
    for word in ('forward', 'left', 'stop', 'backward', 'right'):
        voice_teleop_node.on_word(spoken(word))
    phrases = voice_teleop_module.ACKNOWLEDGEMENTS
    assert [response.data for response in responses] == [
        phrases[0], phrases[1], phrases[2], phrases[3], phrases[0]]


def test_backward_drives_in_reverse(voice_teleop_node):
    twists = capture(voice_teleop_node)
    voice_teleop_node.on_word(spoken('backward'))
    assert twists[-1].twist.linear.x == -voice_teleop_node.forward_speed_mps
    assert twists[-1].twist.angular.z == 0.0


def test_counterclockwise_pivots_with_positive_z(voice_teleop_node):
    twists = capture(voice_teleop_node)
    voice_teleop_node.on_word(spoken('counterclockwise'))
    assert twists[-1].twist.angular.z == voice_teleop_node.angular_speed_radps
    assert twists[-1].twist.linear.x == 0.0


def test_clockwise_pivots_with_negative_z(voice_teleop_node):
    twists = capture(voice_teleop_node)
    voice_teleop_node.on_word(spoken('clockwise'))
    assert twists[-1].twist.angular.z == -voice_teleop_node.angular_speed_radps


def test_left_alone_arcs_forward_and_leftward(voice_teleop_node):
    twists = capture(voice_teleop_node)
    voice_teleop_node.on_word(spoken('left'))
    assert twists[-1].twist.linear.x == voice_teleop_node.forward_speed_mps
    assert twists[-1].twist.angular.z == voice_teleop_node.angular_speed_radps


def test_right_alone_arcs_forward_and_rightward(voice_teleop_node):
    twists = capture(voice_teleop_node)
    voice_teleop_node.on_word(spoken('right'))
    assert twists[-1].twist.linear.x == voice_teleop_node.forward_speed_mps
    assert twists[-1].twist.angular.z == -voice_teleop_node.angular_speed_radps


def test_left_backward_arcs_the_path_to_the_rear_left(voice_teleop_node):
    twists = capture(voice_teleop_node)
    voice_teleop_node.on_word(spoken('left'))
    voice_teleop_node.on_word(spoken('backward'))
    assert twists[-1].twist.linear.x == -voice_teleop_node.forward_speed_mps
    assert twists[-1].twist.angular.z == -voice_teleop_node.angular_speed_radps


def test_backward_left_matches_left_backward(voice_teleop_node):
    twists = capture(voice_teleop_node)
    voice_teleop_node.on_word(spoken('backward'))
    voice_teleop_node.on_word(spoken('left'))
    assert twists[-1].twist.linear.x == -voice_teleop_node.forward_speed_mps
    assert twists[-1].twist.angular.z == -voice_teleop_node.angular_speed_radps


def test_forward_long_after_an_arc_goes_straight(
        voice_teleop_node, voice_teleop_module):
    twists = capture(voice_teleop_node)
    voice_teleop_node.on_word(spoken('left'))
    age_last_word(voice_teleop_node, voice_teleop_module)
    voice_teleop_node.on_word(spoken('forward'))
    assert twists[-1].twist.linear.x == voice_teleop_node.forward_speed_mps
    assert twists[-1].twist.angular.z == 0.0


def test_spoken_linear_two_sets_the_forward_speed(voice_teleop_node):
    capture(voice_teleop_node)
    voice_teleop_node.on_word(spoken('linear'))
    voice_teleop_node.on_word(spoken('two'))
    assert voice_teleop_node.forward_speed_mps == 2.0


def test_spoken_angular_one_sets_the_turn_speed(voice_teleop_node):
    capture(voice_teleop_node)
    voice_teleop_node.on_word(spoken('angular'))
    voice_teleop_node.on_word(spoken('one'))
    assert voice_teleop_node.angular_speed_radps == 1.0


def test_a_speed_change_rescales_the_current_motion(voice_teleop_node):
    twists = capture(voice_teleop_node)
    voice_teleop_node.on_word(spoken('forward'))
    voice_teleop_node.on_word(spoken('linear'))
    voice_teleop_node.on_word(spoken('two'))
    voice_teleop_node.publish_held_twist()
    assert twists[-1].twist.linear.x == 2.0


def test_a_digit_long_after_linear_changes_nothing(
        voice_teleop_node, voice_teleop_module):
    capture(voice_teleop_node)
    original = voice_teleop_node.forward_speed_mps
    voice_teleop_node.on_word(spoken('linear'))
    age_last_word(voice_teleop_node, voice_teleop_module)
    voice_teleop_node.on_word(spoken('two'))
    assert voice_teleop_node.forward_speed_mps == original


def test_a_lone_digit_changes_nothing(voice_teleop_node):
    twists = capture(voice_teleop_node)
    voice_teleop_node.on_word(spoken('three'))
    voice_teleop_node.publish_held_twist()
    assert twists == []


def test_the_speed_parameters_retune_without_a_restart(voice_teleop_node):
    voice_teleop_node.on_parameters_set([
        Parameter('forward_speed_mps', value=0.8)])
    assert voice_teleop_node.forward_speed_mps == 0.8


def test_a_spoken_speed_keeps_the_parameter_store_truthful(voice_teleop_node):
    capture(voice_teleop_node)
    voice_teleop_node.on_word(spoken('linear'))
    voice_teleop_node.on_word(spoken('two'))
    assert voice_teleop_node.get_parameter('forward_speed_mps').value == 2.0


def test_stop_publishes_one_zero_then_goes_quiet(voice_teleop_node):
    twists = capture(voice_teleop_node)
    voice_teleop_node.on_word(spoken('forward'))
    voice_teleop_node.on_word(spoken('stop'))
    assert twists[-1].twist.linear.x == 0.0
    twists.clear()
    voice_teleop_node.publish_held_twist()
    assert twists == []


def test_a_disabled_teleop_ignores_commands(voice_teleop_node):
    twists = capture(voice_teleop_node)
    voice_teleop_node.is_enabled = False
    voice_teleop_node.on_word(spoken('forward'))
    voice_teleop_node.publish_held_twist()
    assert twists == []


def test_disabling_while_driving_stops_the_robot(voice_teleop_node):
    twists = capture(voice_teleop_node)
    voice_teleop_node.on_word(spoken('forward'))
    voice_teleop_node.on_enable(SetBool.Request(data=False), SetBool.Response())
    assert twists[-1].twist.linear.x == 0.0
    twists.clear()
    voice_teleop_node.publish_held_twist()
    assert twists == []


def test_unknown_words_change_nothing(voice_teleop_node):
    twists = capture(voice_teleop_node)
    voice_teleop_node.on_word(spoken('banana'))
    voice_teleop_node.publish_held_twist()
    assert twists == []
