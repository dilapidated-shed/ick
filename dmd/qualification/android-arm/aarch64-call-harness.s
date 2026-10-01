.text
.global _start
.type _start, %function
_start:
    movz w0, #0x4040, lsl #16
    fmov s0, w0
    bl pauli_call_external
    fmov w1, s0

    movz w2, #0x40e0, lsl #16
    cmp w1, w2
    b.ne fail

    mov x0, #0
    mov x8, #93
    svc #0

fail:
    mov x0, #91
    mov x8, #93
    svc #0

.global pauli_external_scale
.type pauli_external_scale, %function
pauli_external_scale:
    fadd s0, s0, s0
    ret

.section .note.GNU-stack,"",%progbits
