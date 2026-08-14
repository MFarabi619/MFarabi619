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


from dataclasses import dataclass
import statistics
import sys
import time

import odrive
from odrive.enums import (
    AXIS_ERROR_WATCHDOG_TIMER_EXPIRED,
    AXIS_STATE_CLOSED_LOOP_CONTROL,
    AXIS_STATE_IDLE,
    CONTROL_MODE_POSITION_CONTROL,
    CONTROL_MODE_VELOCITY_CONTROL,
    INPUT_MODE_TRAP_TRAJ,
    INPUT_MODE_VEL_RAMP,
)
from odrive.utils import dump_errors
from rich.console import Console
from rich.table import Table

FIND_TIMEOUT_SECONDS = 15.0
EXTRA_MOTOR_TIMEOUT_SECONDS = 2.0
SAMPLE_RATE_HZ = 50.0
SETTLE_MARGIN_SECONDS = 0.5
STATE_ENTRY_TIMEOUT_SECONDS = 2.0
STATE_POLL_SECONDS = 0.05
VEL_RAMP_RATE = 8.0
# TODO: run anticogging calibration to tighten low-speed tracking
TRACKING_TOLERANCE = 0.35
SWEEP_START = 4.0
SWEEP_STEP = 2.0
SWEEP_LIMIT = 30.0
SWEEP_HOLD_SECONDS = 1.5
SWEEP_SHORTFALL_FRACTION = 0.85
SWEEP_SAMPLE_COUNT = 10
SWEEP_VEL_LIMIT_MARGIN = 4.0
VBUS_MINIMUM = 16.0
VBUS_MAXIMUM = 28.0
TRAP_VEL_LIMIT = 2.0
TRAP_ACCEL_LIMIT = 4.0
TRAP_TRAVEL_TURNS = 2.0
POSITION_TOLERANCE_TURNS = 0.05
POSITION_TIMEOUT_SECONDS = 6.0
WATCHDOG_TIMEOUT_SECONDS = 0.5
WATCHDOG_FEED_PHASE_SECONDS = 1.0
WATCHDOG_FEED_INTERVAL_SECONDS = 0.1
WATCHDOG_STARVE_SECONDS = 1.5
WATCHDOG_TRIP_VELOCITY = 0.5

PASS_STYLE = "#689d6a"
FAIL_STYLE = "#fb4934"


@dataclass
class Segment:
    name: str
    velocity: float
    duration_seconds: float


@dataclass
class SegmentResult:
    segment: Segment
    mean_error: float
    worst_error: float
    lowest_vbus: float
    peak_current: float
    fet_temperature: float


PROGRAM = [
    Segment("ease in", 1.0, 3.0),
    Segment("cruise", 3.0, 3.0),
    Segment("reverse", -3.0, 4.0),
    Segment("crawl", 0.5, 3.0),
    Segment("stop", 0.0, 2.0),
]


def has_any_error(device):
    axis = device.axis0
    return bool(
        axis.error or axis.motor.error or axis.encoder.error or axis.controller.error
    )


def fet_temperature(device):
    try:
        return device.axis0.motor.fet_thermistor.temperature
    except AttributeError:
        return float("nan")


def enter_state(device, state):
    device.axis0.requested_state = state
    deadline = time.monotonic() + STATE_ENTRY_TIMEOUT_SECONDS
    while time.monotonic() < deadline:
        if device.axis0.current_state == state:
            return True
        time.sleep(STATE_POLL_SECONDS)
    return False


def run_segment(device, segment, previous_velocity):
    device.axis0.controller.input_vel = segment.velocity
    ramp_seconds = abs(segment.velocity - previous_velocity) / VEL_RAMP_RATE
    settle_ticks = int((ramp_seconds + SETTLE_MARGIN_SECONDS) * SAMPLE_RATE_HZ)
    total_ticks = int(segment.duration_seconds * SAMPLE_RATE_HZ)
    errors = []
    lowest_vbus = device.vbus_voltage
    peak_current = 0.0
    for tick in range(total_ticks):
        lowest_vbus = min(lowest_vbus, device.vbus_voltage)
        peak_current = max(
            peak_current, abs(device.axis0.motor.current_control.Iq_measured)
        )
        if tick >= settle_ticks:
            errors.append(abs(device.axis0.encoder.vel_estimate - segment.velocity))
        time.sleep(1.0 / SAMPLE_RATE_HZ)
    if not errors:
        errors.append(abs(device.axis0.encoder.vel_estimate - segment.velocity))
    return SegmentResult(
        segment,
        statistics.fmean(errors),
        max(errors),
        lowest_vbus,
        peak_current,
        fet_temperature(device),
    )


def run_speed_sweep(device, console, failures):
    device.axis0.controller.config.vel_limit = SWEEP_LIMIT + SWEEP_VEL_LIMIT_MARGIN
    top_tracked_velocity = 0.0
    commanded_velocity = SWEEP_START
    while commanded_velocity <= SWEEP_LIMIT:
        device.axis0.controller.input_vel = commanded_velocity
        time.sleep(SWEEP_HOLD_SECONDS)
        estimated_velocity = statistics.fmean(
            device.axis0.encoder.vel_estimate for _ in range(SWEEP_SAMPLE_COUNT)
        )
        if has_any_error(device):
            dump_errors(device, clear=True)
            break
        if estimated_velocity < commanded_velocity * SWEEP_SHORTFALL_FRACTION:
            break
        top_tracked_velocity = estimated_velocity
        commanded_velocity += SWEEP_STEP
    device.axis0.controller.input_vel = 0.0
    console.print(f"  top speed: {top_tracked_velocity:.1f} turn/s")
    if top_tracked_velocity == 0.0:
        failures.append("speed sweep never tracked a step")
    return top_tracked_velocity


def run_trap_position(device, console, failures):
    controller = device.axis0.controller
    controller.config.control_mode = CONTROL_MODE_POSITION_CONTROL
    controller.config.input_mode = INPUT_MODE_TRAP_TRAJ
    device.axis0.trap_traj.config.vel_limit = TRAP_VEL_LIMIT
    device.axis0.trap_traj.config.accel_limit = TRAP_ACCEL_LIMIT
    device.axis0.trap_traj.config.decel_limit = TRAP_ACCEL_LIMIT
    start = device.axis0.encoder.pos_estimate
    controller.input_pos = start
    for target in (start + TRAP_TRAVEL_TURNS, start):
        console.print(f"  trap move to {target - start:+.1f} turns")
        controller.input_pos = target
        deadline = time.monotonic() + POSITION_TIMEOUT_SECONDS
        while time.monotonic() < deadline:
            if (
                abs(device.axis0.encoder.pos_estimate - target)
                <= POSITION_TOLERANCE_TURNS
            ):
                break
            time.sleep(1.0 / SAMPLE_RATE_HZ)
        final_error = abs(device.axis0.encoder.pos_estimate - target)
        if final_error > POSITION_TOLERANCE_TURNS:
            failures.append(f"trap move missed target by {final_error:.3f} turns")


def run_watchdog_trip(device, console, failures):
    console.print("  watchdog starve")
    device.axis0.controller.config.control_mode = CONTROL_MODE_VELOCITY_CONTROL
    device.axis0.controller.config.input_mode = INPUT_MODE_VEL_RAMP
    device.axis0.config.watchdog_timeout = WATCHDOG_TIMEOUT_SECONDS
    device.axis0.config.enable_watchdog = True
    device.axis0.watchdog_feed()
    if not enter_state(device, AXIS_STATE_CLOSED_LOOP_CONTROL):
        failures.append("watchdog phase: closed loop entry refused")
        return
    device.axis0.controller.input_vel = WATCHDOG_TRIP_VELOCITY
    feed_deadline = time.monotonic() + WATCHDOG_FEED_PHASE_SECONDS
    while time.monotonic() < feed_deadline:
        device.axis0.watchdog_feed()
        time.sleep(WATCHDOG_FEED_INTERVAL_SECONDS)
    time.sleep(WATCHDOG_STARVE_SECONDS)
    has_tripped = bool(device.axis0.error & AXIS_ERROR_WATCHDOG_TIMER_EXPIRED)
    is_stopped = device.axis0.current_state == AXIS_STATE_IDLE
    if not has_tripped:
        failures.append("watchdog never tripped after starvation")
    if not is_stopped:
        failures.append("axis stayed active after watchdog trip")
    device.axis0.config.enable_watchdog = False
    device.clear_errors()


def results_table(results, serial):
    table = Table("segment", title=f"odrive e2e {serial}")
    for header in ("target", "mean err", "worst err", "vbus low", "peak Iq", "fet"):
        table.add_column(header, justify="right")
    table.add_column("verdict")
    for result in results:
        is_within_tolerance = result.worst_error <= TRACKING_TOLERANCE
        table.add_row(
            result.segment.name,
            f"{result.segment.velocity:+.1f}",
            f"{result.mean_error:.3f}",
            f"{result.worst_error:.3f}",
            f"{result.lowest_vbus:.1f}V",
            f"{result.peak_current:.1f}A",
            f"{result.fet_temperature:.0f}C",
            f"[{PASS_STYLE}]ok[/]"
            if is_within_tolerance
            else f"[{FAIL_STYLE}]FAIL[/]",
        )
    return table


def find_all_motors():
    devices = odrive.find_sync(count=1, timeout=FIND_TIMEOUT_SECONDS)
    while True:
        try:
            devices = odrive.find_sync(
                count=len(devices) + 1, timeout=EXTRA_MOTOR_TIMEOUT_SECONDS
            )
        except TimeoutError:
            return devices


def run_suite(device, console):
    serial = f"{device.serial_number:X}"
    console.print(f"motor {serial}", style="bold")

    failures = []
    if has_any_error(device):
        console.print("clearing stale errors:")
        dump_errors(device, clear=True)
    if has_any_error(device):
        failures.append("errors persist after clearing")
    if not VBUS_MINIMUM <= device.vbus_voltage <= VBUS_MAXIMUM:
        failures.append(
            f"vbus {device.vbus_voltage:.1f}V"
            f" outside {VBUS_MINIMUM:.0f}-{VBUS_MAXIMUM:.0f}V"
        )
    if failures:
        return [f"{serial}: {failure}" for failure in failures]

    device.axis0.controller.config.control_mode = CONTROL_MODE_VELOCITY_CONTROL
    device.axis0.controller.config.input_mode = INPUT_MODE_VEL_RAMP
    device.axis0.controller.config.vel_ramp_rate = VEL_RAMP_RATE

    results = []
    try:
        if not enter_state(device, AXIS_STATE_CLOSED_LOOP_CONTROL):
            failures.append("closed loop entry refused")
        else:
            previous_velocity = 0.0
            for segment in PROGRAM:
                console.print(f"  {segment.name}: {segment.velocity:+.1f} turn/s")
                results.append(run_segment(device, segment, previous_velocity))
                previous_velocity = segment.velocity
            run_speed_sweep(device, console, failures)
            run_trap_position(device, console, failures)
            device.axis0.requested_state = AXIS_STATE_IDLE
            run_watchdog_trip(device, console, failures)
    finally:
        device.axis0.config.enable_watchdog = False
        device.axis0.controller.input_vel = 0.0
        device.axis0.requested_state = AXIS_STATE_IDLE

    if has_any_error(device):
        failures.append("errors after run:")
        dump_errors(device)
    failures.extend(
        f"{result.segment.name}: worst error {result.worst_error:.3f} turn/s"
        for result in results
        if result.worst_error > TRACKING_TOLERANCE
    )
    failures.extend(
        f"{result.segment.name}: vbus sagged to {result.lowest_vbus:.1f}V"
        for result in results
        if result.lowest_vbus < VBUS_MINIMUM
    )
    console.print(results_table(results, serial))
    return [f"{serial}: {failure}" for failure in failures]


def main():
    console = Console()
    console.print("finding odrives...")
    devices = find_all_motors()
    console.print(f"found {len(devices)}")
    failures = []
    for device in devices:
        failures.extend(run_suite(device, console))
    verdict = "PASS" if not failures else "FAIL"
    console.print(verdict, style=PASS_STYLE if not failures else FAIL_STYLE)
    for failure in failures:
        console.print(failure, style=FAIL_STYLE)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
