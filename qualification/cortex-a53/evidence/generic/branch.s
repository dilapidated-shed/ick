	.arch armv8-a
	.file	"branch.c"
	.text
	.align	2
	.p2align 4,,11
	.global	branch_kernel
	.type	branch_kernel, %function
branch_kernel:
.LFB0:
	.cfi_startproc
	mov	x5, x0
	cbz	w1, .L6
	uxtw	x8, w1
	mov	w2, 0
	mov	w0, 0
	b	.L5
	.p2align 2,,3
.L9:
	udiv	w0, w7, w1
	add	x2, x2, 1
	msub	w0, w0, w1, w7
	ldr	w3, [x5, x0, lsl 2]
	add	w0, w4, w3
	cmp	x2, x8
	beq	.L1
.L5:
	ldr	w3, [x5, x2, lsl 2]
	add	w6, w2, 3
	add	w7, w2, 7
	add	w4, w3, w3, lsl 4
	add	w4, w4, w0
	tbnz	w3, 0, .L9
	udiv	w4, w6, w1
	add	x2, x2, 1
	msub	w4, w4, w1, w6
	ldr	w4, [x5, x4, lsl 2]
	add	w3, w4, w3, lsr 3
	eor	w0, w0, w3
	cmp	x2, x8
	bne	.L5
.L1:
	ret
	.p2align 2,,3
.L6:
	mov	w0, 0
	ret
	.cfi_endproc
.LFE0:
	.size	branch_kernel, .-branch_kernel
	.ident	"GCC: (GNU) 17.0.0 20260813 (experimental)"
	.section	.note.GNU-stack,"",@progbits
