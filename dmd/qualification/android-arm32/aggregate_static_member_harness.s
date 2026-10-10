.syntax unified
.arch armv7-a
.fpu vfpv3-d16
.arm

.text
.global _start
.type _start,%function
_start:
    mov r11, sp
    mov r0, #19
    mov r1, #23
    bl aggregate_static_add
    cmp r0, #42
    bne fail
    cmp sp, r11
    bne fail
    mov r0, #0
    mov r7, #1
    svc #0

fail:
    mov r0, #1
    mov r7, #1
    svc #0

.global _d_dso_registry
.type _d_dso_registry,%function
_d_dso_registry:
    bx lr

.section .note.GNU-stack,"",%progbits
