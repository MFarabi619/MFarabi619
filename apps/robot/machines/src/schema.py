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


import json
from pathlib import Path

from robot_machines.machine import Machine

SCHEMA_PATH = Path(__file__).resolve().parents[1] / 'robot.schema.json'
LOADER_FIELDS = ('name',)


def robot_schema():
    schema = Machine.model_json_schema()
    for field in LOADER_FIELDS:
        schema['properties'].pop(field)
        schema['required'].remove(field)
    return {
        '$schema': 'https://json-schema.org/draft/2020-12/schema',
        **schema,
        'title': 'robot.yaml',
    }


def main():
    SCHEMA_PATH.write_text(json.dumps(robot_schema(), indent=2) + '\n')
    print(SCHEMA_PATH)


if __name__ == '__main__':
    main()
