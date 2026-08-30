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

from audio_common_msgs.msg import AudioStamped


class SingleHitSpotter:
    def __init__(self, keyword):
        self.keyword = keyword
        self.accepted_sample_counts = []
        self.accepted_samples = []
        self.reset_count = 0

    def is_ready(self):
        return self.keyword is not None

    def decode(self):
        pass

    def accept_waveform(self, rate, samples):
        self.accepted_sample_counts.append(len(samples))
        self.accepted_samples.append(samples)

    def result(self):
        keyword, self.keyword = self.keyword, None
        return keyword

    def reset(self):
        self.reset_count += 1


MICROPHONE_SAMPLE_RATE_HZ = 16000


def microphone_message(amplitude=10000, sample_count=512):
    message = AudioStamped()
    message.audio.info.rate = MICROPHONE_SAMPLE_RATE_HZ
    message.audio.audio_data.int16_data = [
        int(amplitude * math.sin(index / 10.0)) for index in range(sample_count)
    ]
    return message


def capture(node):
    words = []
    node.word_publisher.publish = words.append
    return words


def test_a_spotted_keyword_becomes_a_lowercase_word(voice_word_detector_node):
    words = capture(voice_word_detector_node)
    voice_word_detector_node.spotter = SingleHitSpotter('FORWARD')
    voice_word_detector_node.on_audio(microphone_message())
    assert [word.data for word in words] == ['forward']


def test_silence_publishes_nothing(voice_word_detector_node):
    words = capture(voice_word_detector_node)
    voice_word_detector_node.spotter = SingleHitSpotter(None)
    voice_word_detector_node.on_audio(microphone_message())
    assert words == []


def test_a_disabled_detector_ignores_audio(voice_word_detector_node):
    words = capture(voice_word_detector_node)
    spotter = SingleHitSpotter('STOP')
    voice_word_detector_node.spotter = spotter
    voice_word_detector_node.is_enabled = False
    voice_word_detector_node.on_audio(microphone_message())
    assert words == []
    assert spotter.accepted_sample_counts == []


def test_int16_audio_is_normalized_to_unit_range(voice_word_detector_module):
    message = microphone_message()
    samples = voice_word_detector_module.normalized_samples(message)
    assert len(samples) == 512
    assert max(samples) <= 1.0 and min(samples) >= -1.0
    assert max(samples) > 0.25


def test_the_committed_model_loads_with_every_keyword(voice_word_detector_node):
    assert voice_word_detector_node.spotter is not None


def test_sensitivity_parameters_reach_the_spotter(voice_word_detector_module):
    import rclpy.parameter
    node = voice_word_detector_module.VoiceWordDetector(
        parameter_overrides=[
            rclpy.parameter.Parameter('keyword_boost', value=3.0),
            rclpy.parameter.Parameter('keyword_threshold', value=0.1),
        ])
    assert node.spotter is not None
    node.destroy_node()


def burst(peak, sample_count=512):
    import numpy as np
    return (peak * np.sin(np.arange(sample_count) / 10.0)).astype(np.float32)


def test_quiet_audio_is_amplified_toward_the_target_level(
        voice_word_detector_module):
    control = voice_word_detector_module.AutomaticGainControl(
        target_level=0.1, max_gain=20.0)
    for _ in range(10):
        leveled = control.leveled(burst(0.04))
    quiet_rms = 0.04 / 2 ** 0.5
    assert max(abs(leveled)) > 3.0 * 0.04
    assert abs(control.speech_level - quiet_rms) < 0.3 * quiet_rms


def test_loud_audio_is_never_attenuated(voice_word_detector_module):
    control = voice_word_detector_module.AutomaticGainControl(
        target_level=0.1, max_gain=20.0)
    loud = burst(0.9)
    for _ in range(10):
        leveled = control.leveled(loud)
    assert max(abs(leveled)) >= max(abs(loud)) - 1e-6


def test_amplification_of_near_silence_is_bounded(voice_word_detector_module):
    control = voice_word_detector_module.AutomaticGainControl(
        target_level=0.1, max_gain=20.0)
    leveled = control.leveled(burst(0.0001))
    assert max(abs(leveled)) <= 0.0001 * 20.0 + 1e-6


def test_speaker_playback_does_not_deafen_following_speech(
        voice_word_detector_module):
    control = voice_word_detector_module.AutomaticGainControl(
        target_level=0.1, max_gain=20.0)
    for _ in range(30):
        control.leveled(burst(0.9))
    for _ in range(30):
        leveled = control.leveled(burst(0.04))
    assert max(abs(leveled)) > 2.5 * 0.04


def test_silence_between_words_holds_the_gain_steady(
        voice_word_detector_module):
    control = voice_word_detector_module.AutomaticGainControl(
        target_level=0.1, max_gain=20.0)
    for _ in range(10):
        control.leveled(burst(0.04))
    level_before_silence = control.speech_level
    for _ in range(50):
        control.leveled(burst(0.0001))
    assert control.speech_level == level_before_silence
    assert control.chunk_is_voiced is False


def test_a_pause_in_speech_resets_the_spotter_once(voice_word_detector_node):
    spotter = SingleHitSpotter(None)
    voice_word_detector_node.spotter = spotter
    voice_word_detector_node.on_audio(microphone_message(amplitude=1500))
    for _ in range(40):
        voice_word_detector_node.on_audio(microphone_message(amplitude=50))
    assert spotter.reset_count == 1


def test_each_pause_resets_the_spotter_again(voice_word_detector_node):
    spotter = SingleHitSpotter(None)
    voice_word_detector_node.spotter = spotter
    for _ in range(2):
        voice_word_detector_node.on_audio(microphone_message(amplitude=1500))
        for _ in range(20):
            voice_word_detector_node.on_audio(microphone_message(amplitude=50))
    assert spotter.reset_count == 2


def test_the_spotter_receives_leveled_audio(voice_word_detector_node):
    spotter = SingleHitSpotter(None)
    voice_word_detector_node.spotter = spotter
    voice_word_detector_node.on_audio(microphone_message(amplitude=1500))
    assert max(abs(spotter.accepted_samples[0])) > 0.1
