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


import subprocess
import time

VIEW_CONTROL_SENSITIVITY = 0.25
SENSITIVITY_RETRY_DELAY_SECONDS = 2.0
SENSITIVITY_MAX_ATTEMPTS = 60


def set_view_control_sensitivity():
    command = [
        'gz', 'service', '-s', '/gui/camera/view_control/sensitivity',
        '--reqtype', 'gz.msgs.Double', '--reptype', 'gz.msgs.Boolean',
        '--timeout', '1000', '--req', f'data: {VIEW_CONTROL_SENSITIVITY}',
    ]
    for _ in range(SENSITIVITY_MAX_ATTEMPTS):
        completed = subprocess.run(command, capture_output=True)
        if completed.returncode == 0:
            return
        time.sleep(SENSITIVITY_RETRY_DELAY_SECONDS)
