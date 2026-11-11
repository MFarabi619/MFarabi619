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


import os
from unittest import mock

import pytest

from launch_recording import LaunchRecorder, isolate_launch_environment


@pytest.fixture
def launch_recorder(monkeypatch, tmp_path):
    with mock.patch.dict(os.environ):
        recorder = LaunchRecorder(str(tmp_path))
        isolate_launch_environment(recorder, monkeypatch)
        yield recorder
