// Compiler ABI oracle only, NOT an Android druntime implementation.
// Invokes the emitted init/fini pointers and validates CompilerDSOData v1.
.syntax unified
.arm
.text
.global _start
.type _start,%function
_start:
    ldr r4, =__init_array_start
    ldr r5, =__init_array_end
    sub r5, r5, r4
    cmp r5, #4                  // COMDAT: one registration for two modules
    bne fail
    ldr r6, [r4]
    blx r6
    mov r0, #20
    mov r1, #22
    bl ordinary_d_add
    cmp r0, #42
    bne fail
    ldr r4, =__fini_array_start
    ldr r5, =__fini_array_end
    sub r5, r5, r4
    cmp r5, #4
    bne fail
    ldr r5, [r4]
    cmp r5, r6
    bne fail
    blx r5
    ldr r1, =registry_calls
    ldr r1, [r1]
    cmp r1, #2
    bne fail
    mov r0, #0
    mov r7, #1
    svc #0
fail:
    mov r0, #1                  // Never return a stale or zero failure code
    mov r7, #1
    svc #0

.global _d_dso_registry
.type _d_dso_registry,%function
_d_dso_registry:
    tst sp, #7                 // AAPCS32 public-call stack alignment
    bne fail
    cmp r0, sp                 // Descriptor is the 16-byte stack record
    bne fail
    ldr r1, [r0]
    cmp r1, #1                 // version
    bne fail
    ldr r1, [r0, #8]
    ldr r2, =__start_minfo
    cmp r1, r2
    bne fail
    ldr r2, [r0, #12]
    ldr r3, =__stop_minfo
    cmp r2, r3
    bne fail
    sub r2, r2, r1
    cmp r2, #8                 // both minfo pointers survive COMDAT selection
    bne fail
    ldr r2, [r1]
    ldr r3, =_D10ordinary_d12__ModuleInfoZ
    cmp r2, r3
    bne fail
    ldr r2, [r1, #4]
    ldr r3, =_D16ordinary_d_empty12__ModuleInfoZ
    cmp r2, r3
    bne fail
    ldr r1, =registry_calls
    ldr r2, [r1]
    ldr r3, [r0, #4]           // slot (the mutable COMDAT DSORec)
    tst r3, #3
    bne fail
    ldr r12, [r3]
    cmp r12, r2                // initial zero; then registry-owned backlink
    bne fail
    eor r12, r12, #1
    str r12, [r3]
    add r2, r2, #1
    str r2, [r1]
    bx lr
.data
.balign 4
registry_calls:
    .word 0
.section .note.GNU-stack,"",%progbits
