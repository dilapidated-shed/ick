// Independent A32/base-PCS scalar-memory oracle. D supplies only the functions
// under test: expected values, memory, sentinels and comparisons live here.
// Compile scalar_memory.d without -betterC. The registry below validates the
// compiler's metadata contract only; it is NOT an Android druntime body.
//
// Stages: 1-3 pair loads; 4-6 pair stores/results; 7-9 word regressions;
// 10-12 destination-call preservation; 13 bool dereference; 14 owned bool
// globals; 15 imported bool global; 16-22 indexed long/ulong/double/bool/int/
// float/pointer; 23-25 indexed destinations with two hostile calls; 26 global
// pair alignment/payload; 31/32
// registration/unregistration. Both deliberate source mutants have exact
// required failures: MemoryWrongHighReturn -> 1; MemoryTruncatedStore -> 4.
//
// For the pre-fix compiler only, assemble with MEMORY_BASELINE=1 and compile D
// with -version=MemoryBaseline. MEMORY_START_STORE=1 additionally skips stages
// 1-3 to expose the independent store defect at stage 4. These modes never
// qualify the complete fixed boundary and are not used by the positive run.
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
    expect r5, 0x76543210
.endm
.macro aligned
    tst sp, #7
    bne fail
.endm
.macro expect_word address, value
    ldr r2, =\address
    ldr r3, [r2]
    expect r3, \value
.endm
.macro expect_byte address, value
    ldr r2, =\address
    ldrb r3, [r2]
    expect r3, \value
.endm
.macro expect_pair address, low, high
    expect_word \address, \low
    expect_word \address+4, \high
.endm
.macro pair_guards address
    expect_word \address-4, 0x13579bdf
    expect_word \address+8, 0x2468ace0
.endm
.macro word_guards address
    expect_word \address-4, 0x13579bdf
    expect_word \address+4, 0x2468ace0
.endm
.macro clear_calls
    ldr r2, =address_calls
    mov r3, #0
    str r3, [r2]
    ldr r2, =index_calls
    str r3, [r2]
.endm
.macro expect_calls address_count, index_count
    expect_word address_calls, \address_count
    expect_word index_calls, \index_count
.endm
.macro literal_pool
    b .Lafter_pool\@
    .ltorg
.Lafter_pool\@:
.endm

.text
.global _start
.type _start,%function
_start:
    mov r11, sp
    ldr r4, =0x12345678
    ldr r5, =0x76543210
    mov r10, #31
    ldr r0, =__init_array_start
    ldr r1, =__init_array_end
    sub r1, r1, r0
    cmp r1, #4
    bne fail
    ldr r6, [r0]
    blx r6

.ifndef MEMORY_START_STORE
    mov r10, #1
    ldr r0, =long_input
    ldr r1, =0xa5a5b6b6       // A missing high-word load cannot inherit the answer
    invoke memory_load_long
    expect r0, 0x55667788
    expect r1, 0x11223344

    mov r10, #2
    ldr r0, =ulong_input
    ldr r1, =0xa5a5b6b6
    invoke memory_load_ulong
    expect r0, 0x89abcdef
    expect r1, 0xf1234567

    mov r10, #3
    ldr r0, =double_input
    ldr r1, =0xa5a5b6b6
    invoke memory_load_double
    expect r0, 0x54442d18
    expect r1, 0x400921fb
    ldr r0, =negative_zero
    ldr r1, =0xa5a5b6b6
    invoke memory_load_double
    expect r0, 0
    expect r1, 0x80000000
.endif

    mov r10, #4
    ldr r0, =long_slot
    ldr r1, =0xccccdddd       // AAPCS32 alignment hole before r2:r3
    ldr r2, =0x90abcdef
    ldr r3, =0x81234567
    invoke memory_store_long
    // Inspect target memory BEFORE the result: the truncated-store source
    // mutant returns the correct pair and must fail for its wrong memory.
    expect_pair long_slot, 0x90abcdef, 0x81234567
    pair_guards long_slot
    expect r0, 0x90abcdef
    expect r1, 0x81234567
    literal_pool

    mov r10, #5
    ldr r0, =ulong_slot
    ldr r1, =0xccccdddd
    ldr r2, =0x76543210
    ldr r3, =0xfedcba98
    invoke memory_store_ulong
    expect_pair ulong_slot, 0x76543210, 0xfedcba98
    pair_guards ulong_slot
    expect r0, 0x76543210
    expect r1, 0xfedcba98

    mov r10, #6
    ldr r0, =double_slot
    ldr r1, =0xccccdddd
    ldr r2, =0x89abcdef       // Preserve a NaN payload as raw scalar memory
    ldr r3, =0x7ff81234
    invoke memory_store_double
    expect_pair double_slot, 0x89abcdef, 0x7ff81234
    pair_guards double_slot
    expect r0, 0x89abcdef
    expect r1, 0x7ff81234

    mov r10, #7
    ldr r0, =int_slot
    invoke memory_load_int
    expect r0, 0x87654321
    ldr r0, =int_slot
    ldr r1, =0xabcdef01
    invoke memory_store_int
    expect r0, 0xabcdef01
    expect_word int_slot, 0xabcdef01
    word_guards int_slot

    mov r10, #8
    ldr r0, =float_slot
    invoke memory_load_float
    expect r0, 0x3fa00000
    ldr r0, =float_slot
    ldr r1, =0xffc12345
    invoke memory_store_float
    expect r0, 0xffc12345
    expect_word float_slot, 0xffc12345
    word_guards float_slot
    literal_pool

    mov r10, #9
    ldr r0, =pointer_slot
    invoke memory_load_pointer
    expect r0, pointer_first
    ldr r0, =pointer_slot
    ldr r1, =pointer_second
    invoke memory_store_pointer
    expect r0, pointer_second
    expect_word pointer_slot, pointer_second
    word_guards pointer_slot

    mov r10, #10
    clear_calls
    ldr r0, =long_slot
    ldr r1, =0xccccdddd
    ldr r2, =0x10293847
    ldr r3, =0xabcdef12
    invoke memory_store_long_after_call
    expect_pair long_slot, 0x10293847, 0xabcdef12
    pair_guards long_slot
    expect r0, 0x10293847
    expect r1, 0xabcdef12
    expect_calls 1, 0

    mov r10, #11
    clear_calls
    ldr r0, =ulong_slot
    ldr r1, =0xccccdddd
    ldr r2, =0x456789ab
    ldr r3, =0xcdef0123
    invoke memory_store_ulong_after_call
    expect_pair ulong_slot, 0x456789ab, 0xcdef0123
    pair_guards ulong_slot
    expect r0, 0x456789ab
    expect r1, 0xcdef0123
    expect_calls 1, 0

    mov r10, #12
    clear_calls
    ldr r0, =double_slot
    ldr r1, =0xccccdddd
    ldr r2, =0x89abcdef
    ldr r3, =0xfff81234
    invoke memory_store_double_after_call
    expect_pair double_slot, 0x89abcdef, 0xfff81234
    pair_guards double_slot
    expect r0, 0x89abcdef
    expect r1, 0xfff81234
    expect_calls 1, 0
    literal_pool

.ifndef MEMORY_BASELINE
    mov r10, #13
    ldr r0, =bool_false
    invoke memory_load_bool
    expect r0, 0             // Adjacent nonzero bytes must not make false true
    ldr r0, =bool_true
    invoke memory_load_bool
    expect r0, 1
    ldr r0, =bool_false
    mov r1, #1
    invoke memory_store_bool
    expect r0, 1
    expect_word bool_bytes, 0xd70101c3
    ldr r0, =bool_true
    mov r1, #0
    invoke memory_store_bool
    expect r0, 0
    expect_word bool_bytes, 0xd70001c3

    mov r10, #14
    invoke memory_load_own_bool_true
    expect r0, 1
    invoke memory_load_own_bool_false
    expect r0, 0
    mov r0, #0
    invoke memory_store_own_bool_true
    expect r0, 0
    expect_byte memory_own_bool_true, 0
    mov r0, #1
    invoke memory_store_own_bool_false
    expect r0, 1
    expect_byte memory_own_bool_false, 1
    invoke memory_load_own_bool_true
    expect r0, 0
    invoke memory_load_own_bool_false
    expect r0, 1

    mov r10, #15
    invoke memory_load_external_bool
    expect r0, 0
    mov r0, #1
    invoke memory_store_external_bool
    expect r0, 1
    expect_word external_bool_bytes, 0xe6d501c3
    invoke memory_load_external_bool
    expect r0, 1
    mov r0, #0
    invoke memory_store_external_bool
    expect r0, 0
    expect_word external_bool_bytes, 0xe6d500c3
    literal_pool

    mov r10, #16
    ldr r0, =long_array
    mov r1, #1
    invoke memory_index_long
    expect r0, 0x55667788
    expect r1, 0x11223344
    ldr r0, =long_array+16
    mvn r1, #0
    invoke memory_index_long
    expect r0, 0x55667788
    expect r1, 0x11223344
    ldr r0, =long_array+16
    mvn r1, #0
    ldr r2, =0x10203040
    ldr r3, =0x50607080
    invoke memory_index_store_long
    expect r0, 0x10203040
    expect r1, 0x50607080
    expect_pair long_array+8, 0x10203040, 0x50607080
    expect_pair long_array, 0x01010101, 0x02020202
    expect_pair long_array+16, 0x03030303, 0x04040404

    mov r10, #17
    ldr r0, =ulong_array
    mov r1, #1
    invoke memory_index_ulong
    expect r0, 0x89abcdef
    expect r1, 0xf1234567
    ldr r0, =ulong_array+16
    mvn r1, #0
    ldr r2, =0x2468ace0
    ldr r3, =0xfedcba98
    invoke memory_index_store_ulong
    expect r0, 0x2468ace0
    expect r1, 0xfedcba98
    expect_pair ulong_array+8, 0x2468ace0, 0xfedcba98
    expect_pair ulong_array, 0x05050505, 0x06060606
    expect_pair ulong_array+16, 0x07070707, 0x08080808

    mov r10, #18
    ldr r0, =double_array
    mov r1, #1
    invoke memory_index_double
    expect r0, 0x54442d18
    expect r1, 0x400921fb
    ldr r0, =double_array+16
    mvn r1, #0
    invoke memory_index_double
    expect r0, 0x54442d18
    expect r1, 0x400921fb
    ldr r0, =double_array+16
    mvn r1, #0
    ldr r2, =0x01020304
    ldr r3, =0x7ff8abcd
    invoke memory_index_store_double
    expect r0, 0x01020304
    expect r1, 0x7ff8abcd
    expect_pair double_array+8, 0x01020304, 0x7ff8abcd
    expect_pair double_array, 0x09090909, 0x0a0a0a0a
    expect_pair double_array+16, 0x0b0b0b0b, 0x0c0c0c0c
    literal_pool

    mov r10, #19
    ldr r0, =bool_array
    mov r1, #1
    invoke memory_index_bool
    expect r0, 0
    ldr r0, =bool_array+3
    mvn r1, #0
    invoke memory_index_bool
    expect r0, 1
    ldr r0, =bool_array
    mov r1, #1
    mov r2, #1
    invoke memory_index_store_bool
    expect r0, 1
    expect_word bool_array, 0xd70101c3
    ldr r0, =bool_array+3
    mvn r1, #0
    mov r2, #0
    invoke memory_index_store_bool
    expect r0, 0
    expect_word bool_array, 0xd70001c3

    mov r10, #20
    ldr r0, =int_array
    mov r1, #1
    invoke memory_index_int
    expect r0, 0x1234fedc
    ldr r0, =int_array+8
    mvn r1, #0
    ldr r2, =0x87654321
    invoke memory_index_store_int
    expect r0, 0x87654321
    expect_word int_array+4, 0x87654321
    word_guards int_array+4

    mov r10, #21
    ldr r0, =float_array
    mov r1, #1
    invoke memory_index_float
    expect r0, 0x3f800000
    ldr r0, =float_array+8
    mvn r1, #0
    ldr r2, =0x80000000
    invoke memory_index_store_float
    expect r0, 0x80000000
    expect_word float_array+4, 0x80000000
    word_guards float_array+4

    mov r10, #22
    ldr r0, =pointer_array
    mov r1, #1
    invoke memory_index_pointer
    expect r0, pointer_first
    ldr r0, =pointer_array+8
    mvn r1, #0
    ldr r2, =pointer_second
    invoke memory_index_store_pointer
    expect r0, pointer_second
    expect_word pointer_array+4, pointer_second
    word_guards pointer_array+4
    literal_pool

    mov r10, #23
    clear_calls
    ldr r0, =long_array+16
    ldr r1, =0xccccdddd
    ldr r2, =0xabcdef01
    ldr r3, =0x87654321
    invoke memory_index_store_long_after_calls
    expect r0, 0xabcdef01
    expect r1, 0x87654321
    expect_pair long_array+8, 0xabcdef01, 0x87654321
    expect_pair long_array, 0x01010101, 0x02020202
    expect_pair long_array+16, 0x03030303, 0x04040404
    expect_calls 1, 1

    mov r10, #24
    clear_calls
    ldr r0, =double_array+16
    ldr r1, =0xccccdddd
    ldr r2, =0x0badcafe
    ldr r3, =0xfff84321
    invoke memory_index_store_double_after_calls
    expect r0, 0x0badcafe
    expect r1, 0xfff84321
    expect_pair double_array+8, 0x0badcafe, 0xfff84321
    expect_pair double_array, 0x09090909, 0x0a0a0a0a
    expect_pair double_array+16, 0x0b0b0b0b, 0x0c0c0c0c
    expect_calls 1, 1

    mov r10, #25
    clear_calls
    ldr r0, =bool_array+2
    mov r1, #0
    invoke memory_index_store_bool_after_calls
    expect r0, 0
    expect_word bool_array, 0xd70000c3
    expect_calls 1, 1
.endif

    mov r10, #26
    ldr r0, =memory_own_long
    tst r0, #7
    bne fail
    expect_pair memory_own_long, 0x50607080, 0x10203040
    ldr r0, =memory_own_double
    tst r0, #7
    bne fail
    expect_pair memory_own_double, 0, 0x400c0000
.ifndef MEMORY_BASELINE
    ldr r0, =memory_own_bool_aligned
    tst r0, #15
    bne fail
    expect_byte memory_own_bool_aligned, 1
.endif

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
    expect_word registry_calls, 2
    cmp sp, r11
    bne fail
    mov r0, #0
    mov r7, #1
    svc #0
fail:
    and r0, r10, #255         // Only low exit byte is externally observable
    cmp r0, #0
    moveq r0, #255            // Corrupt stage register can never turn FAIL into 0
    mov r7, #1
    svc #0
.ltorg

// These four signatures have the same pointer argument and pointer return.
// Preserve only the return pointer and LR in our aligned frame, then destroy
// all caller-saved data registers. r0 is overwritten before being restored as
// the required pointer result. Callee-saved registers remain untouched.
.global memory_address_long, memory_address_ulong, memory_address_double, memory_address_bool
.type memory_address_long,%function
.type memory_address_ulong,%function
.type memory_address_double,%function
.type memory_address_bool,%function
memory_address_long:
memory_address_ulong:
memory_address_double:
memory_address_bool:
    aligned
    push {r0, lr}
    ldr r12, =address_calls
    ldr r1, [r12]
    add r1, r1, #1
    str r1, [r12]
    mvn r0, #0
    ldr r1, =0xdeadc0de
    ldr r2, =0xdeadbeef
    ldr r3, =0xbadc0ffe
    mvn r12, #0
    vmov d0, r1, r2
    vmov d1, r2, r3
    pop {r0, pc}

.global memory_index
.type memory_index,%function
memory_index:
    aligned
    ldr r12, =index_calls
    ldr r0, [r12]
    add r0, r0, #1
    str r0, [r12]
    mvn r0, #0               // -1, a signed index within caller-owned memory
    ldr r1, =0xdeadc0de
    ldr r2, =0xdeadbeef
    ldr r3, =0xbadc0ffe
    mvn r12, #0
    vmov d0, r1, r2
    vmov d1, r2, r3
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
    cmp r2, #4               // Exactly the one independently compiled D module
    bne fail
    ldr r2, [r1]
    expect r2, _D13scalar_memory12__ModuleInfoZ
    ldr r1, =registry_calls
    ldr r2, [r1]
    ldr r3, [r0, #4]
    tst r3, #3
    bne fail
    ldr r12, [r3]
    cmp r12, r2              // Initial zero, then oracle-owned backlink
    bne fail
    eor r12, r12, #1
    str r12, [r3]
    add r2, r2, #1
    str r2, [r1]
    bx lr
.ltorg

.data
.balign 8
long_input:
    .word 0x55667788, 0x11223344
ulong_input:
    .word 0x89abcdef, 0xf1234567
double_input:
    .word 0x54442d18, 0x400921fb
negative_zero:
    .word 0, 0x80000000

// Each pair is 8-byte aligned, with independently checked word sentinels.
    .word 0, 0x13579bdf
long_slot:
    .word 0xa0a0a0a0, 0xb0b0b0b0
    .word 0x2468ace0, 0x13579bdf
ulong_slot:
    .word 0xa1a1a1a1, 0xb1b1b1b1
    .word 0x2468ace0, 0x13579bdf
double_slot:
    .word 0xa2a2a2a2, 0xb2b2b2b2
    .word 0x2468ace0

    .word 0x13579bdf
int_slot:
    .word 0x87654321
    .word 0x2468ace0, 0x13579bdf
float_slot:
    .word 0x3fa00000
    .word 0x2468ace0, 0x13579bdf
pointer_slot:
    .word pointer_first
    .word 0x2468ace0
pointer_first:
    .word 11
pointer_second:
    .word 22

.balign 8
long_array:
    .word 0x01010101, 0x02020202
    .word 0x55667788, 0x11223344
    .word 0x03030303, 0x04040404
ulong_array:
    .word 0x05050505, 0x06060606
    .word 0x89abcdef, 0xf1234567
    .word 0x07070707, 0x08080808
double_array:
    .word 0x09090909, 0x0a0a0a0a
    .word 0x54442d18, 0x400921fb
    .word 0x0b0b0b0b, 0x0c0c0c0c
int_array:
    .word 0x13579bdf, 0x1234fedc, 0x2468ace0
float_array:
    .word 0x13579bdf, 0x3f800000, 0x2468ace0
pointer_array:
    .word 0x13579bdf, pointer_first, 0x2468ace0

.balign 4
bool_bytes:
    .byte 0xc3
bool_false:
    .byte 0
bool_true:
    .byte 1, 0xd7
bool_array:
    .byte 0xc3, 0, 1, 0xd7
external_bool_bytes:
    .byte 0xc3
.global memory_external_bool
.type memory_external_bool,%object
memory_external_bool:
    .byte 0
.size memory_external_bool, 1
    .byte 0xd5, 0xe6
.balign 4
registry_calls:
    .word 0
address_calls:
    .word 0
index_calls:
    .word 0
// The following D object must request its .data alignment from the linker.
// A four-byte alignment incorrectly places its pair globals at 4 modulo 8
// because this harness is linked first and ends with four bytes after padding.
// The explicitly aligned bool additionally requires 16-byte alignment.
.balign 16
    .word 0xa11a11a1
.section .note.GNU-stack,"",%progbits
