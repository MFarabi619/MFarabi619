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


import difflib
import hashlib
import json
import os
from pathlib import Path
import sys

import pytest
import yaml

from launch_recording import REPO_ROOT, ROBOT_ROOT

SNAPSHOT_DIRECTORY = Path(__file__).parent / 'snapshots'


def snapshot_payload(recorder, invocation):
    environment_changes = dict(os.environ.items() - recorder.environment_before.items())
    return {
        'launch': invocation,
        'environment': normalize(environment_changes, recorder.temporary_directory),
        'events': normalize(recorder.events, recorder.temporary_directory),
    }


def normalize(value, temporary_directory):
    if isinstance(value, dict):
        return {str(key): normalize(item, temporary_directory) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [normalize(item, temporary_directory) for item in value]
    if callable(value):
        return f'<callable {value.__name__}>'
    if isinstance(value, str):
        return normalize_string(value, temporary_directory)
    return value


def is_xml_document(value):
    return value.lstrip().startswith('<')


def normalize_string(value, temporary_directory):
    if value.startswith(temporary_directory):
        with open(value) as file:
            return {'tempfile': yaml.safe_load(file)}
    if value == sys.executable:
        return '<python>'
    value = without_checkout_paths(value)
    if is_xml_document(value):
        digest = hashlib.sha256(value.encode()).hexdigest()
        return {'xml_sha256': digest, 'bytes': len(value)}
    return value


def without_checkout_paths(value):
    value = value.replace(ROBOT_ROOT + '/', '').replace(REPO_ROOT + '/', '<repo>/')
    return value.replace(os.path.expanduser('~') + '/', '~/')


def snapshot_text(payload):
    return json.dumps(payload, indent=2, sort_keys=True, default=repr) + '\n'


def write_snapshot(case_id, payload):
    path = SNAPSHOT_DIRECTORY / f'{case_id}.json'
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(snapshot_text(payload))


def assert_matches_snapshot(case_id, payload):
    path = SNAPSHOT_DIRECTORY / f'{case_id}.json'
    if not path.is_file():
        pytest.fail(f'{path} missing; run with SNAPSHOT_UPDATE=1 to create it')
    expected = path.read_text()
    actual = snapshot_text(payload)
    if actual != expected:
        difference = difflib.unified_diff(
            expected.splitlines(), actual.splitlines(),
            f'{case_id}.json (committed)', f'{case_id}.json (launch)', lineterm='')
        pytest.fail('launch output changed:\n' + '\n'.join(difference))
