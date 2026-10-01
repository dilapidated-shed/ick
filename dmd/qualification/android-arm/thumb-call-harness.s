.syntax unified
.arch armv7-a
.fpu vfpv3-d16
.thumb
.text

.global _start
.thumb_func
_start:
    mov r5, sp
    movw r4, #0x4444
    movw r8, #0x8888

    movw r0, #0
    movt r0, #0x4040
    bl pauli_thumb_call_external

    movw r1, #0
    movt r1, #0x40e0
    cmp r0, r1
    bne fail

    cmp sp, r5
    bne fail
    movw r2, #0x4444
    cmp r4, r2
    bne fail
    movw r2, #0x8888
    cmp r8, r2
    bne fail

    movs r0, #1
    movs r1, #2
    movs r2, #3
    movs r3, #4
    bl pauli_thumb_call_four

    movw r1, #0x0201
    movt r1, #0x0403
    cmp r0, r1
    bne fail
    cmp sp, r5
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
    mov r1, sp
    tst r1, #7
    bne fail
    vmov s0, r0
    vadd.f32 s0, s0, s0
    vmov r0, s0
    bx lr

.global pauli_external_mix
.thumb_func
pauli_external_mix:
    mov r12, sp
    tst r12, #7
    bne fail
    orr r0, r0, r1, lsl #8
    orr r0, r0, r2, lsl #16
    orr r0, r0, r3, lsl #24
    bx lr

.section .note.GNU-stack,"",%progbits
