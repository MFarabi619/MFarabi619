# Map the current Zephyr ARCH/CPU to a Zig -target and -mcpu pair.
#
# Sets ZIG_TARGET and ZIG_MCPU as CACHE INTERNAL so they're visible from
# any scope (Zephyr modules are processed via add_subdirectory, but
# add_zig_object is called from the consuming app's top-level scope).
#
# Only riscv32 is mapped — that's the only target we've actually exercised.
# Adding xtensa requires Kassane's zig-espressif-bootstrap (upstream Zig has
# no Xtensa backend); adding arm requires picking the right -mcpu spelling
# per Cortex variant and confirming the soft/hard-float ABI matches. Both
# are tractable but stubs would only be misleading.

if("${ARCH}" STREQUAL "riscv")
  set(_zig_target "riscv32-freestanding-none")

  set(_features "generic_rv32")
  if(CONFIG_RISCV_ISA_EXT_M)
    string(APPEND _features "+m")
  endif()
  if(CONFIG_RISCV_ISA_EXT_A)
    string(APPEND _features "+a")
  endif()
  if(CONFIG_RISCV_ISA_EXT_C)
    string(APPEND _features "+c")
  endif()
  # Gate floating-point on CONFIG_FPU (the "kernel actually uses FP" knob)
  # rather than CONFIG_RISCV_ISA_EXT_F (the "hardware has FP" knob). qemu_riscv32
  # sets the ISA bit but builds soft-float; mixing soft- and single-float modules
  # at link time fails with "can't link single-float modules with soft-float modules".
  if(CONFIG_FPU AND CONFIG_RISCV_ISA_EXT_F)
    string(APPEND _features "+f")
  endif()
  if(CONFIG_RISCV_ISA_EXT_ZICSR)
    string(APPEND _features "+zicsr")
  endif()
  if(CONFIG_RISCV_ISA_EXT_ZIFENCEI)
    string(APPEND _features "+zifencei")
  endif()
  set(_zig_mcpu "${_features}")
  unset(_features)

else()
  message(FATAL_ERROR
    "zephyr-lang-zig: ARCH '${ARCH}' is not yet supported. Only riscv32 has "
    "been validated end-to-end. To add support, extend zig-target.cmake "
    "and verify zig's CPU model spelling matches your Zephyr -march/-mabi.")
endif()

set(ZIG_TARGET "${_zig_target}" CACHE INTERNAL "Zig -target value" FORCE)
set(ZIG_MCPU "${_zig_mcpu}" CACHE INTERNAL "Zig -mcpu value" FORCE)
unset(_zig_target)
unset(_zig_mcpu)

message(STATUS "zephyr-lang-zig: target=${ZIG_TARGET} mcpu=${ZIG_MCPU}")
