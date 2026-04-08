# https://www.youtube.com/watch?v=FV6P5eRmMh8
# https://developer.arm.com/documentation/dui0801/l/Structure-of-Assembly-Language-Modules/Syntax-of-source-lines-in-assembly-language?lang=en
# https://www.chromium.org/chromium-os/developer-library/reference/linux-constants/syscalls/#arm-32-biteabi
# ==================================== #
#     projectile compile in emacs
# ==================================== #
# ~/.zvm/bin/zig build-exe learning/assembly/arm.s -target arm-linux-musleabi -fno-entry -femit-bin=learning/assembly/arm

# ~/.zvm/bin/zig build-obj learning/assembly/arm.s -target arm-linux-musleabi -fno-entry
# ==================================== #
# file arm
# nm arm
# llvm-objdump -d arm
# ==================================== #
# ssh framework-desktop
# sshfs mfarabi@macos:/Users/mfarabi/MFarabi619/learning/assembly /home/mfarabi/workspace/learning/assembly -o reconnect
# cd ~/workspace/learning/assembly
# qemu-arm ./arm
# ==================================== #

.global _start
.section .text

_start:
  mov r7, #0x4
  mov r0, #1
  ldr r1, =message
  mov r2, #14
  swi 0

  mov r7, #0x1
  mov r0, #65
  swi 0

.section .data
  message:
  .ascii "Hello, World!\n"
