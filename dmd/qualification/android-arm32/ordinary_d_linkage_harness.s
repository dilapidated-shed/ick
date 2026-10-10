// Independent AAPCS32/base-PCS oracle for ordinary-D symbols and scalar calls.
// The D symbol spellings are fixed ABI expectations, including type backrefs,
// overloads, attributes and the pragma(mangle) override. They were also checked
// against the pinned upstream DMD 2.113.0 mangler, not derived from this backend.
// The registry body checks CompilerDSOData only; it is NOT Android druntime.
.syntax unified
.arch armv7-a
.fpu vfpv3-d16
.arm

.macro expect register, value
    ldr r12, =\value
    cmp \register, r12
    bne fail
.endm
.macro invoke symbol
    bl \symbol
    cmp sp, r11
    bne fail
    expect r4, 0x12345678
.endm
.macro aligned
    tst sp, #7
    bne fail
.endm

.text
.global _start
.type _start,%function
_start:
    mov r11, sp
    ldr r4, =0x12345678
    mov r10, #31
    ldr r0, =__init_array_start
    ldr r1, =__init_array_end
    sub r1, r1, r0
    cmp r1, #4
    bne fail
    ldr r6, [r0]
    blx r6

    mov r10, #1
    mov r0, #42
    invoke _D18ordinary_d_linkage19ordinary_d_identityFiZi
    cmp r0, #42
    bne fail

    mov r10, #2
    mov r0, #3
    invoke _D18ordinary_d_linkage10overloadedFiZi
    cmp r0, #13
    bne fail
    mov r0, #4
    mov r1, #0
    invoke _D18ordinary_d_linkage10overloadedFlZl
    expect r0, 1004
    cmp r1, #0
    bne fail
    mov r0, #21
    invoke _D15ordinary_d_peer19ordinary_d_identityFiZi
    cmp r0, #121
    bne fail

    mov r10, #3
    ldr r0, =pointer_value
    invoke _D18ordinary_d_linkage7pointerFPiZQd
    expect r0, pointer_value

    mov r10, #4
    sub sp, sp, #8
    ldr r0, =0x3f800000
    ldr r1, =0x40000000
    ldr r2, =0x40400000
    ldr r3, =0x40800000
    ldr r12, =0x40a00000
    str r12, [sp]
    bl _D18ordinary_d_linkage10fifthFloatFfffffZf
    add sp, sp, #8
    expect r0, 0x40a00000
    cmp sp, r11
    bne fail

    mov r10, #5
    sub sp, sp, #8
    mov r0, #1
    mov r1, #99                 // Hole before the aligned double in r2:r3
    mov r2, #0
    ldr r3, =0x400c0000
    mov r12, #3
    str r12, [sp]
    bl _D18ordinary_d_linkage13alignedDoubleFidiZd
    add sp, sp, #8
    cmp r0, #0
    bne fail
    expect r1, 0x400c0000

    mov r10, #6
    sub sp, sp, #8
    mov r0, #1
    mov r1, #2
    mov r2, #3
    mov r3, #99                 // Long cannot split across r3 and the stack
    ldr r12, =0x55667788
    str r12, [sp]
    ldr r12, =0x11223344
    str r12, [sp, #4]
    bl _D18ordinary_d_linkage11stackedLongFiiilZl
    add sp, sp, #8
    expect r0, 0x55667788
    expect r1, 0x11223344

    mov r10, #7
    sub sp, sp, #24
    mov r0, #1
    mov r1, #2
    mov r2, #3
    mov r3, #4
    mov r12, #5
    str r12, [sp]
    mov r12, #99                // Padding before the 8-byte stack argument
    str r12, [sp, #4]
    mov r12, #0
    str r12, [sp, #8]
    ldr r12, =0x40190000
    str r12, [sp, #12]
    mov r12, #7
    str r12, [sp, #16]
    bl _D18ordinary_d_linkage18stackAlignedDoubleFiiiiidiZd
    add sp, sp, #24
    cmp r0, #0
    bne fail
    expect r1, 0x40190000
    cmp sp, r11
    bne fail
    expect r4, 0x12345678

    mov r10, #8
    invoke _D16ordinary_d_calls12crossModulesFZi
    cmp r0, #142
    bne fail
    invoke _D16ordinary_d_calls13callOverloadsFZi
    expect r0, 1017

    mov r10, #9
    mov r0, #21
    invoke _D16ordinary_d_calls5callCFiZi
    cmp r0, #42
    bne fail
    mov r0, #41
    invoke ordinary_d_c_calls_d
    cmp r0, #42
    bne fail

    mov r10, #10
    invoke _D16ordinary_d_calls5orderFZi
    expect r0, 12352
    ldr r0, =ordinary_d_trace
    ldr r0, [r0]
    expect r0, 12345

    mov r10, #11
    invoke _D16ordinary_d_calls9callFloatFZf
    expect r0, 0x41200000

    mov r10, #12
    invoke _D16ordinary_d_calls10callDoubleFZd
    cmp r0, #0
    bne fail
    expect r1, 0x401c0000

    mov r10, #13
    invoke _D16ordinary_d_calls8callLongFZl
    expect r0, 0x55667788
    expect r1, 0x11223344

    mov r10, #14
    ldr r0, =pointer_value
    invoke _D16ordinary_d_calls11callPointerFPiZQd
    expect r0, pointer_value

    mov r10, #15
    invoke _D16ordinary_d_calls15callStackDoubleFZd
    cmp r0, #0
    bne fail
    expect r1, 0x40290000

    mov r10, #16
    invoke _D16ordinary_d_calls13callQualifiedFZi
    cmp r0, #42
    bne fail

    mov r10, #32
    ldr r0, =__fini_array_start
    ldr r1, =__fini_array_end
    sub r1, r1, r0
    cmp r1, #4
    bne fail
    ldr r0, [r0]
    cmp r0, r6
    bne fail
    blx r0
    ldr r0, =registry_calls
    ldr r0, [r0]
    cmp r0, #2
    bne fail
    cmp sp, r11
    bne fail

    mov r0, #0
    mov r7, #1
    svc #0
fail:
    and r0, r10, #255          // Linux exposes only the low byte of exit status
    cmp r0, #0
    moveq r0, #255             // A corrupted stage register cannot pass a failure
    mov r7, #1
    svc #0
.ltorg

.global ordinary_d_c_twice
.type ordinary_d_c_twice,%function
ordinary_d_c_twice:
    aligned
    add r0, r0, r0
    bx lr

.global _D16ordinary_d_calls9asmScalarFiiiiiZi
.type _D16ordinary_d_calls9asmScalarFiiiiiZi,%function
_D16ordinary_d_calls9asmScalarFiiiiiZi:
    aligned
    expect r0, 1
    expect r1, 2
    expect r2, 3
    expect r3, 4
    ldr r0, [sp]
    expect r0, 5
    ldr r0, =ordinary_d_trace
    ldr r0, [r0]
    expect r0, 12345
    // Adversarial caller-saved registers. The caller must retain argument and
    // result temporaries in its own frame across nested calls.
    mvn r1, #0
    mvn r2, #0
    mvn r3, #0
    vmov d0, r1, r2
    vmov d1, r1, r2
    mov r0, #7
    bx lr

.global _D16ordinary_d_calls8asmFloatFfffffZf
.type _D16ordinary_d_calls8asmFloatFfffffZf,%function
_D16ordinary_d_calls8asmFloatFfffffZf:
    aligned
    expect r0, 0x3f800000
    expect r1, 0x40000000
    expect r2, 0x40400000
    expect r3, 0x40800000
    ldr r0, [sp]
    expect r0, 0x40a00000
    vmov d0, r1, r2
    vmov d1, r1, r2
    bx lr

.global _D16ordinary_d_calls9asmDoubleFidiZd
.type _D16ordinary_d_calls9asmDoubleFidiZd,%function
_D16ordinary_d_calls9asmDoubleFidiZd:
    aligned
    expect r0, 1
    expect r2, 0
    expect r3, 0x400c0000
    ldr r0, [sp]
    expect r0, 3
    mov r0, r2
    mov r1, r3
    bx lr

.global _D16ordinary_d_calls7asmLongFiiilZl
.type _D16ordinary_d_calls7asmLongFiiilZl,%function
_D16ordinary_d_calls7asmLongFiiilZl:
    aligned
    expect r0, 1
    expect r1, 2
    expect r2, 3
    ldr r0, [sp]
    ldr r1, [sp, #4]
    expect r0, 0x55667788
    expect r1, 0x11223344
    bx lr

.global _D16ordinary_d_calls10asmPointerFPiZQd
.type _D16ordinary_d_calls10asmPointerFPiZQd,%function
_D16ordinary_d_calls10asmPointerFPiZQd:
    aligned
    expect r0, pointer_value
    bx lr

.global _D16ordinary_d_calls14asmStackDoubleFiiiiidiZd
.type _D16ordinary_d_calls14asmStackDoubleFiiiiidiZd,%function
_D16ordinary_d_calls14asmStackDoubleFiiiiidiZd:
    aligned
    expect r0, 1
    expect r1, 2
    expect r2, 3
    expect r3, 4
    ldr r0, [sp]
    expect r0, 5
    ldr r0, [sp, #16]
    expect r0, 7
    ldr r0, [sp, #8]
    ldr r1, [sp, #12]
    expect r0, 0
    expect r1, 0x40190000
    bx lr

.global _d_dso_registry
.type _d_dso_registry,%function
_d_dso_registry:
    aligned
    cmp r0, sp
    bne fail
    ldr r1, [r0]
    cmp r1, #1
    bne fail
    ldr r1, [r0, #8]
    expect r1, __start_minfo
    ldr r2, [r0, #12]
    expect r2, __stop_minfo
    sub r2, r2, r1
    cmp r2, #12                 // All three separately compiled D modules
    bne fail
    ldr r2, [r1]
    expect r2, _D18ordinary_d_linkage12__ModuleInfoZ
    ldr r2, [r1, #4]
    expect r2, _D15ordinary_d_peer12__ModuleInfoZ
    ldr r2, [r1, #8]
    expect r2, _D16ordinary_d_calls12__ModuleInfoZ
    ldr r1, =registry_calls
    ldr r2, [r1]
    ldr r3, [r0, #4]
    tst r3, #3
    bne fail
    ldr r12, [r3]
    cmp r12, r2
    bne fail
    eor r12, r12, #1
    str r12, [r3]
    add r2, r2, #1
    str r2, [r1]
    bx lr
.ltorg

.data
.balign 4
pointer_value:
    .word 42
registry_calls:
    .word 0
.section .note.GNU-stack,"",%progbits
