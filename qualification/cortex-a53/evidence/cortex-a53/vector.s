	.arch armv8-a
	.file	"vector.c"
	.text
	.align	2
	.p2align 4,,15
	.global	vector_kernel
	.type	vector_kernel, %function
vector_kernel:
.LFB0:
	.cfi_startproc
	cbz	w3, .L1
	sub	w4, w3, #1
	cmp	w4, 2
	bls	.L5
	lsr	w5, w3, 2
	mov	w4, 0
	fmov	v31.4s, 5.0e-1
	fmov	v30.4s, 2.5e-1
	ubfiz	x6, x5, 4, 30
	.p2align 3,,7
.L4:
	ldr	q29, [x0, x4]
	ldr	q28, [x1, x4]
	fmul	v29.4s, v29.4s, v31.4s
	fadd	v28.4s, v29.4s, v28.4s
	fmul	v28.4s, v28.4s, v30.4s
	str	q28, [x2, x4]
	add	x4, x4, 16
	cmp	x6, x4
	bne	.L4
	lsl	w4, w5, 2
	cmp	w3, w4
	beq	.L1
.L3:
	uxtw	x5, w4
	fmov	s26, 5.0e-1
	fmov	s24, 2.5e-1
	add	w6, w4, 1
	ldr	s3, [x0, x5, lsl 2]
	ldr	s2, [x1, x5, lsl 2]
	fmul	s3, s3, s26
	fadd	s2, s3, s2
	fmul	s2, s2, s24
	str	s2, [x2, x5, lsl 2]
	cmp	w3, w6
	bls	.L1
	uxtw	x5, w6
	add	w4, w4, 2
	ldr	s1, [x0, x5, lsl 2]
	ldr	s0, [x1, x5, lsl 2]
	fmul	s1, s1, s26
	fadd	s0, s1, s0
	fmul	s0, s0, s24
	str	s0, [x2, x5, lsl 2]
	cmp	w3, w4
	bls	.L1
	ldr	s27, [x0, x4, lsl 2]
	ldr	s25, [x1, x4, lsl 2]
	fmul	s27, s27, s26
	fadd	s25, s27, s25
	fmul	s25, s25, s24
	str	s25, [x2, x4, lsl 2]
.L1:
	ret
.L5:
	mov	w4, 0
	b	.L3
	.cfi_endproc
.LFE0:
	.size	vector_kernel, .-vector_kernel
	.ident	"GCC: (GNU) 17.0.0 20260813 (experimental)"
	.section	.note.GNU-stack,"",@progbits
