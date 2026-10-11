/* Handwritten Thumb-2 boundary probes, NOT compiler-generated IDK evidence.
 * r0=input address, r1=output address. Canonical input is a precondition.
 * No claim of assembled/executed code until a receipt says so.
 */
.syntax unified
.thumb
.text

.global right_load_half
.thumb_func
right_load_half:
    ldrh r0, [r0]
    lsls r0, r0, #7
    bx lr

.global left_load_half
.thumb_func
left_load_half:
    ldrh r0, [r0]
    bx lr

/* Move stored E5M3 into the unchanged exact-integer arithmetic implementation. */
.global right_load_code
.thumb_func
right_load_code:
    ldrh r0, [r0]
    bx lr

.global left_load_code
.thumb_func
left_load_code:
    ldrh r0, [r0]
    lsrs r0, r0, #7
    bx lr

/* r0 is already a canonical nine-bit RESULT of E5M3 arithmetic.
 * These are not arbitrary-FP16 narrowing routines.
 */
.global right_store_code
.thumb_func
right_store_code:
    strh r0, [r1]
    bx lr

.global left_store_code
.thumb_func
left_store_code:
    lsls r0, r0, #7
    strh r0, [r1]
    bx lr

/* r0 is an arbitrary FP16 payload. RNE, with positive canonical E5M3 NaN.
 * Shared helper returns left storage. r2/r3 are scratch GPRs, no stack spills.
 */
.global narrow_half_to_left
.thumb_func
narrow_half_to_left:
    ubfx r2, r0, #0, #15
    movw r3, #0x7c00
    cmp r2, r3
    bhi .Lnan
    beq .Lreturn
    and r3, r2, #0x7f
    bic r0, r0, #0x7f
    cmp r3, #64
    bhi .Lround
    bne .Lreturn
    tst r2, #0x80
    beq .Lreturn
.Lround:
    adds r0, r0, #128
.Lreturn:
    bx lr
.Lnan:
    movw r0, #0x7e00
    bx lr

.global narrow_half_to_right
.thumb_func
narrow_half_to_right:
    push {r4, lr}
    bl narrow_half_to_left
    lsrs r0, r0, #7
    pop {r4, pc}
