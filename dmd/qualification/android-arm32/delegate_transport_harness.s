.syntax unified
.arch armv7-a
.fpu vfpv3-d16
.arm

.text
.global _start
.type _start,%function
_start:
    mov r0, #19
    mov r1, #17
    mov r2, #34
    mov r3, #23
    bl c_delegate_register_reference
    cmp r0, #42
    bne fail

    mov r0, #19
    mov r1, #17
    mov r2, #34
    mov r3, #23
    bl delegate_transport_register_forward
    cmp r0, #42
    bne fail

    sub sp, sp, #16
    mov r12, #17
    str r12, [sp]
    mov r12, #34
    str r12, [sp, #4]
    mov r12, #23
    str r12, [sp, #8]
    mov r0, #1
    mov r1, #2
    mov r2, #3
    mov r3, #4
    bl c_delegate_stack_reference
    add sp, sp, #16
    cmp r0, #42
    bne fail

    sub sp, sp, #16
    mov r12, #17
    str r12, [sp]
    mov r12, #34
    str r12, [sp, #4]
    mov r12, #23
    str r12, [sp, #8]
    mov r0, #1
    mov r1, #2
    mov r2, #3
    mov r3, #4
    bl delegate_transport_stack_forward
    add sp, sp, #16
    cmp r0, #42
    bne fail

    mov r0, #0
    mov r7, #1
    svc #0

fail:
    mov r0, #1
    mov r7, #1
    svc #0

.global delegate_transport_register_sink
.type delegate_transport_register_sink,%function
delegate_transport_register_sink:
    cmp r0, #19
    bne sink_fail
    cmp r1, #17
    bne sink_fail
    cmp r2, #34
    bne sink_fail
    cmp r3, #23
    bne sink_fail
    mov r0, #42
    bx lr

.global delegate_transport_stack_sink
.type delegate_transport_stack_sink,%function
delegate_transport_stack_sink:
    cmp r0, #1
    bne sink_fail
    cmp r1, #2
    bne sink_fail
    cmp r2, #3
    bne sink_fail
    cmp r3, #4
    bne sink_fail
    ldr r12, [sp]
    cmp r12, #17
    bne sink_fail
    ldr r12, [sp, #4]
    cmp r12, #34
    bne sink_fail
    ldr r12, [sp, #8]
    cmp r12, #23
    bne sink_fail
    mov r0, #42
    bx lr

sink_fail:
    mov r0, #1
    bx lr

.global _d_dso_registry
.type _d_dso_registry,%function
_d_dso_registry:
    bx lr

.section .note.GNU-stack,"",%progbits
