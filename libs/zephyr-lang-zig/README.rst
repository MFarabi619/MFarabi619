.. _language_zig:

Zig Language Support
####################

Zig support for Zephyr. Enable with ``CONFIG_ZIG=y``.

Requirements
************

- Zephyr SDK
- Zig 0.16+ (Xtensa toolchain auto-downloaded; RISC-V/host uses system ``zig``)

Hello World
***********

``CMakeLists.txt``::

   cmake_minimum_required(VERSION 3.20.0)
   list(APPEND ZEPHYR_EXTRA_MODULES ${CMAKE_CURRENT_SOURCE_DIR}/../..)
   find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
   project(my_app LANGUAGES C)
   zig_sample_app()

``prj.conf``::

   CONFIG_ZIG=y

``src/main.zig``::

   const zephyr = @import("zephyr");

   pub const panic = zephyr.panic;

   fn app() !void {
       zephyr.say("Hello, Zephyr!\n");
   }

   export fn main() c_int {
       return zephyr.runApp(app);
   }

See ``samples/`` for more.

Architectures
*************

- RISC-V (``qemu_riscv32``, ESP32-Cx) — upstream Zig
- Xtensa (ESP32, ESP32-S2, ESP32-S3) — auto-fetched `kassane/zig-espressif-bootstrap`_

ARM Cortex-M is not supported.

.. _kassane/zig-espressif-bootstrap: https://github.com/kassane/zig-espressif-bootstrap

Tests
*****

::

   $ zig test lib/timing.zig    # host-side, pure-Zig logic
   $ west twister -T .          # on-target via QEMU
