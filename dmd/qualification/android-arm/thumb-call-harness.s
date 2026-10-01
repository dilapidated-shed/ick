.syntax unified
.arch armv7-a
.fpu vfpv3-d16
.thumb
.text

.global _start
.thumb_func
_start:
    movw r0, #0
    movt r0, #0x4040
    bl pauli_thumb_call_external

    movw r1, #0
    movt r1, #0x40e0
    cmp r0, r1
    bne fail

    movs r0, #0
    movs r7, #1
    svc #0

fail:
    movs r0, #91
    movs r7, #1
    svc #0

.global pauli_external_scale
.thumb_func
pauli_external_scale:
    vmov s0, r0
    vadd.f32 s0, s0, s0
    vmov r0, s0
    bx lr

.section .note.GNU-stack,"",%progbits
