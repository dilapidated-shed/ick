	.arch armv8-a
	.file	"scalar.c"
	.text
	.align	2
	.p2align 4,,11
	.global	scalar_kernel
	.type	scalar_kernel, %function
scalar_kernel:
.LFB0:
	.cfi_startproc
	cbz	w2, .L4
	fmov	s29, 5.0e-1
	fmov	s30, 2.5e-1
	uxtw	x2, w2
	mov	w4, 1031798784
	fmov	s23, s29
	fmov	s24, s30
	mov	w3, 0
	fmov	s31, 1.0e+0
	fmov	s26, w4
	fmov	s28, 7.5e-1
	fmov	s25, 1.25e-1
	.p2align 3,,7
.L3:
	fmul	s27, s31, s26
	fmul	s30, s30, s23
	fmul	s29, s29, s24
	fmul	s28, s28, s25
	ldr	s31, [x0, x3, lsl 2]
	add	x3, x3, 1
	fadd	s30, s30, s31
	fsub	s29, s29, s31
	fadd	s28, s31, s28
	fsub	s31, s27, s31
	cmp	x2, x3
	bne	.L3
	stp	s30, s29, [x1]
	stp	s28, s31, [x1, 8]
	ret
	.p2align 2,,3
.L4:
	fmov	s31, 1.0e+0
	fmov	s28, 7.5e-1
	fmov	s29, 5.0e-1
	fmov	s30, 2.5e-1
	stp	s28, s31, [x1, 8]
	stp	s30, s29, [x1]
	ret
	.cfi_endproc
.LFE0:
	.size	scalar_kernel, .-scalar_kernel
	.ident	"GCC: (GNU) 17.0.0 20260813 (experimental)"
	.section	.note.GNU-stack,"",@progbits
