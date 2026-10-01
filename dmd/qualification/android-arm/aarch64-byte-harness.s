.text
.global _start
.type _start, %function
_start:
    adrp x0, pixels
    add x0, x0, :lo12:pixels
    mov w1, #2
    mov w2, #0x1234
    bl pauli_byte_roundtrip

    cmp w0, #0x34
    b.ne fail

    adrp x3, pixels
    add x3, x3, :lo12:pixels
    ldrb w0, [x3, #0]
    cmp w0, #0x11
    b.ne fail
    ldrb w0, [x3, #1]
    cmp w0, #0x22
    b.ne fail
    ldrb w0, [x3, #2]
    cmp w0, #0x34
    b.ne fail
    ldrb w0, [x3, #3]
    cmp w0, #0x44
    b.ne fail

    mov x0, #0
    mov x8, #93
    svc #0

fail:
    mov x0, #92
    mov x8, #93
    svc #0

.data
.balign 4
pixels:
    .byte 0x11, 0x22, 0x33, 0x44

.section .note.GNU-stack,"",%progbits
