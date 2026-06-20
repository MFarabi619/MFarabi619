.. _language_zig:

Zig Language Support
####################

Zig is a systems programming language with comptime metaprogramming, explicit
allocators, and seamless C interop.  It has no runtime, links cleanly against
Zephyr's C kernel, and can compile C sources directly.

Enabling Zig Support
********************

Select :kconfig:option:`CONFIG_ZIG` in the application configuration.

Install Zig 0.16 or later from the `Zig downloads page`_ or via a package
manager.  ``riscv32`` works with upstream Zig; ``xtensa`` needs the
`zig-espressif-bootstrap`_ fork.

.. _Zig downloads page: https://ziglang.org/download/
.. _zig-espressif-bootstrap: https://github.com/kassane/zig-espressif-bootstrap

Target and CPU model are derived from ``ARCH``.  Only ``riscv32`` is mapped
today — extend ``cmake/zig-target.cmake`` for more.

Writing a Zig Application
*************************

See :file:`samples/` for ``hello_world``, ``tick_loop``, ``blinky``, ``bench``, and ``sqlite``.

CMake file
----------

.. code-block:: cmake

   cmake_minimum_required(VERSION 3.20.0)

   list(APPEND ZEPHYR_EXTRA_MODULES ${CMAKE_CURRENT_SOURCE_DIR}/../..)

   find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
   project(hello_world LANGUAGES C)

   zig_sample_app()

``zig_sample_app()`` compiles :file:`src/main.zig` with Zephyr's include paths
and links the result into the app target.

Application
-----------

:file:`src/main.zig`:

.. code-block:: zig

   const zephyr = @import("zephyr");

   export fn main() c_int {
       zephyr.print("Hello from Zig on Zephyr!\n", .{});
       return 0;
   }

Pre-registered modules: ``zephyr`` (Zephyr API wrappers), ``timing``
(ms/ticks math), ``ring_buffer`` (SPSC ring buffer), ``build_config`` (Kconfig
values as comptime constants).

Zephyr Functionality
********************

Logging
-------

Route ``std.log`` through Zephyr's ``LOG_*`` macros:

.. code-block:: zig

   pub const std_options: std.Options = .{
       .log_level = .debug,
       .logFn = zephyr.logFn,
   };

Heap
----

``zephyr.KMallocAllocator`` is a ``std.mem.Allocator`` over ``k_aligned_alloc``
/ ``k_free``.  Requires ``CONFIG_HEAP_MEM_POOL_SIZE``.

.. code-block:: zig

   var state = zephyr.KMallocAllocator{};
   const allocator = state.allocator();

Errors
------

``zephyr.checkError(rc)`` lifts negative ``errno`` returns into Zig's typed
error set (``InvalidArg``, ``Busy``, ``TimedOut``, ...).

Sync
----

``zephyr.Mutex`` and ``zephyr.Semaphore`` wrap ``k_mutex`` / ``k_sem``.
``init(handle)`` for runtime, ``fromHandle(handle)`` for ``K_MUTEX_DEFINE``
symbols.

Time
----

``zephyr.Timeout`` mirrors ``k_timeout_t``.  ``sleepMs``, ``uptimeMs``,
``cycleGet32``, ``cycleHz``.

Kconfig at comptime
-------------------

.. code-block:: zig

   const build_config = @import("build_config");
   const ticks_per_sec = build_config.ticks_per_sec;

Add new values in ``cmake/zig.cmake``.

Testing
*******

Host-side:

.. code-block:: console

   $ zig test libs/zephyr-lang-zig/lib/timing.zig

On-target with ``ztest``: a test directory contains :file:`prj.conf`,
:file:`tests.yaml`, :file:`CMakeLists.txt` calling ``zig_ztest_app()``, and
:file:`src/zig_tests.zig`:

.. code-block:: zig

   export fn zig_test_my_case() void {
       t.zig_assert_i64_eq(1 + 1, 2);
   }

The C ``ZTEST`` scaffolding is generated.  Optional
``zig_before`` / ``zig_after`` register per-test hooks.  Add
:file:`src/test_bridge.c` for C-side fixtures (``K_MUTEX_DEFINE``,
``DEVICE_DT_GET``).

Tests enable ``CONFIG_ZTEST_FANCY=y`` (from the sibling
``libs/zephyr-ztest-fancy`` module), which supplies the ``test_main``
runner, colored ``[PASSED]`` / ``[FAILED]`` verdict tags, ``TC_END_REPORT``,
and a SiFive test-finisher poweroff so QEMU exits cleanly after the suite
instead of hanging until twister's timeout.

BDD-style narration is available as ``zephyr.bdd.given`` /
``zephyr.bdd.when`` / ``zephyr.bdd.then`` / ``zephyr.bdd.@"and"`` — Zig
counterparts to the ``GIVEN`` / ``WHEN`` / ``THEN`` / ``AND`` C macros in
the fancy module. Each takes a single comptime string (no varargs); the
function name encodes the BDD phase via ANSI-colored ``[GIVEN]`` /
``[WHEN]`` / ``[THEN]`` prefixes matching the C macros byte-for-byte.

.. code-block:: zig

   export fn zig_test_sem_take_give() void {
       zephyr.bdd.given("an empty semaphore");
       zephyr.bdd.when("we give then immediately take");
       zephyr.bdd.then("count returns to 0");

       // ... assertions ...
   }

Run:

.. code-block:: console

   $ west twister -T libs/zephyr-lang-zig -p qemu_riscv32

Known Limitations
*****************

* Only ``riscv32`` validated.  ``xtensa`` needs the Kassane fork.
* ``@cImport`` doesn't work against picolibc — bindings are ``extern fn``.
* Devicetree exposed via ``@import("dt")`` — ``scripts/gen_dts_zig.py``
  walks the build's ``edt.pickle`` and emits nested ``const`` Zig data;
  phandles become Zig references. ``chosen`` and ``DT_NODELABEL`` labels
  not yet translated.
* ``static inline`` Zephyr APIs (``k_msleep``, ``gpio_pin_*``,
  ``k_sem_count_get``) need C trampolines — see :file:`bridge.c`.
