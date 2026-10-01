.syntax unified
.arch armv7-a
.thumb
.text

.global _start
.thumb_func
_start:
    ldr r0, =pixels
    movs r1, #2
    movw r2, #0x1234
    bl pauli_byte_roundtrip

    cmp r0, #0x34
    bne fail

    ldr r3, =pixels
    ldrb r0, [r3, #0]
    cmp r0, #0x11
    bne fail
    ldrb r0, [r3, #1]
    cmp r0, #0x22
    bne fail
    ldrb r0, [r3, #2]
    cmp r0, #0x34
    bne fail
    ldrb r0, [r3, #3]
    cmp r0, #0x44
    bne fail

    movs r0, #0
    movs r7, #1
    svc #0

fail:
    movs r0, #92
    movs r7, #1
    svc #0

.data
.balign 4
pixels:
    .byte 0x11, 0x22, 0x33, 0x44

.section .note.GNU-stack,"",%progbits
