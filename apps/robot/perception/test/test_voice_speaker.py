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


from std_msgs.msg import String


class CannedSynthesis:
    samples = [0.0, 0.25, -0.25]
    sample_rate = 24000


class RecordingSynthesizer:
    def __init__(self):
        self.spoken_texts = []

    def generate(self, text, speaker_id):
        self.spoken_texts.append(text)
        return CannedSynthesis()


def spoken(text):
    return String(data=text)


def capture(node):
    audio_messages = []
    node.audio_publisher.publish = audio_messages.append
    return audio_messages


def recording_synthesizers(node):
    node.synthesizers = {
        'en': RecordingSynthesizer(),
        'fr': RecordingSynthesizer(),
    }
    return node.synthesizers


def test_speech_is_synthesized_and_played(voice_speaker_node):
    audio_messages = capture(voice_speaker_node)
    synthesizers = recording_synthesizers(voice_speaker_node)
    voice_speaker_node.on_speech(spoken('acknowledged'))
    assert synthesizers['en'].spoken_texts == ['acknowledged']
    assert len(audio_messages) == 1


def test_the_language_parameter_picks_the_voice(voice_speaker_node):
    capture(voice_speaker_node)
    synthesizers = recording_synthesizers(voice_speaker_node)
    voice_speaker_node.language = 'fr'
    voice_speaker_node.on_speech(spoken('bien compris'))
    assert synthesizers['fr'].spoken_texts == ['bien compris']
    assert synthesizers['en'].spoken_texts == []


def test_playback_carries_the_synthesis_format(
        voice_speaker_node, voice_speaker_module):
    audio_messages = capture(voice_speaker_node)
    recording_synthesizers(voice_speaker_node)
    voice_speaker_node.on_speech(spoken('acknowledged'))
    info = audio_messages[0].audio.info
    assert info.format == voice_speaker_module.PORTAUDIO_FLOAT32
    assert info.channels == 1
    assert info.rate == CannedSynthesis.sample_rate
    assert info.chunk == len(CannedSynthesis.samples)


def test_empty_text_is_not_spoken(voice_speaker_node):
    audio_messages = capture(voice_speaker_node)
    synthesizers = recording_synthesizers(voice_speaker_node)
    voice_speaker_node.on_speech(spoken(''))
    assert synthesizers['en'].spoken_texts == []
    assert audio_messages == []


def test_both_committed_voice_models_load(voice_speaker_node):
    assert set(voice_speaker_node.synthesizers) == {'en', 'fr'}
