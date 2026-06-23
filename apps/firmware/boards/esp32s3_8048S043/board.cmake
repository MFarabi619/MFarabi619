# SPDX-License-Identifier: Apache-2.0

board_runner_args(esp32 "--esp-device=hwgrep://1A86:7523")
board_runner_args(esp32 "--esp-baud-rate=460800")

include(${ZEPHYR_BASE}/boards/common/esp32.board.cmake)
