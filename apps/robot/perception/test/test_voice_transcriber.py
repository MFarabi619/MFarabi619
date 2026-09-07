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


class SingleUtteranceTranscriber:
    def __init__(self, words):
        self.words = words
        self.accepted_samples = []
        self.reset_count = 0
        self.pending_decodes = 1

    def accept_waveform(self, rate, samples):
        self.accepted_samples.append(samples)

    def is_ready(self):
        return self.pending_decodes > 0

    def decode(self):
        self.pending_decodes -= 1

    def is_endpoint(self):
        return self.reset_count == 0

    def result(self):
        return self.words

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


def test_a_spoken_utterance_publishes_each_teleop_word_in_order(
        voice_transcriber_node):
    words = capture(voice_transcriber_node)
    voice_transcriber_node.transcriber = SingleUtteranceTranscriber(
        ['forward', 'two'])
    voice_transcriber_node.on_audio(microphone_message())
    assert [word.data for word in words] == ['forward', 'two']


def test_an_utterance_ends_with_a_reset(voice_transcriber_node):
    transcriber = SingleUtteranceTranscriber(['stop'])
    voice_transcriber_node.transcriber = transcriber
    voice_transcriber_node.on_audio(microphone_message())
    assert transcriber.reset_count == 1


def test_conversation_around_a_teleop_word_is_ignored(voice_transcriber_node):
    words = capture(voice_transcriber_node)
    voice_transcriber_node.transcriber = SingleUtteranceTranscriber(
        ['take', 'a', 'left', 'up', 'here'])
    voice_transcriber_node.on_audio(microphone_message())
    assert words == []


def test_a_silent_endpoint_publishes_nothing(voice_transcriber_node):
    words = capture(voice_transcriber_node)
    voice_transcriber_node.transcriber = SingleUtteranceTranscriber([])
    voice_transcriber_node.on_audio(microphone_message())
    assert words == []


def test_a_disabled_transcriber_ignores_audio(voice_transcriber_node):
    words = capture(voice_transcriber_node)
    transcriber = SingleUtteranceTranscriber(['forward'])
    voice_transcriber_node.transcriber = transcriber
    voice_transcriber_node.is_enabled = False
    voice_transcriber_node.on_audio(microphone_message())
    assert words == []
    assert transcriber.accepted_samples == []


def test_the_transcriber_receives_leveled_audio(voice_transcriber_node):
    transcriber = SingleUtteranceTranscriber([])
    voice_transcriber_node.transcriber = transcriber
    voice_transcriber_node.on_audio(microphone_message(amplitude=1500))
    assert max(abs(transcriber.accepted_samples[0])) > 0.1


def test_homophones_normalize_to_teleop_words(voice_transcriber_node):
    words = capture(voice_transcriber_node)
    voice_transcriber_node.transcriber = SingleUtteranceTranscriber(
        ['forward', 'to'])
    voice_transcriber_node.on_audio(microphone_message())
    assert [word.data for word in words] == ['forward', 'two']


def test_plural_decodes_normalize_to_teleop_words(voice_transcriber_node):
    words = capture(voice_transcriber_node)
    voice_transcriber_node.transcriber = SingleUtteranceTranscriber(
        ['backwards'])
    voice_transcriber_node.on_audio(microphone_message())
    assert [word.data for word in words] == ['backward']


def test_fillers_around_a_teleop_word_are_tolerated(voice_transcriber_node):
    words = capture(voice_transcriber_node)
    voice_transcriber_node.transcriber = SingleUtteranceTranscriber(
        ['uh', 'left', 'the'])
    voice_transcriber_node.on_audio(microphone_message())
    assert [word.data for word in words] == ['left']


def test_fillers_alone_publish_nothing(voice_transcriber_node):
    words = capture(voice_transcriber_node)
    voice_transcriber_node.transcriber = SingleUtteranceTranscriber(
        ['and', 'the'])
    voice_transcriber_node.on_audio(microphone_message())
    assert words == []


def test_every_teleop_word_is_recognized(voice_transcriber_module):
    assert {'forward', 'backward', 'left', 'right', 'stop', 'clockwise',
            'counterclockwise', 'linear', 'angular', 'zero', 'five',
            'straight', 'back'} <= voice_transcriber_module.TELEOP_WORDS


def test_the_committed_model_loads(voice_transcriber_node):
    assert voice_transcriber_node.transcriber is not None
