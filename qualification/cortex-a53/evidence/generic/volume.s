	.arch armv8-a
	.file	"volume.c"
	.text
	.align	2
	.p2align 4,,11
	.global	volume_kernel
	.type	volume_kernel, %function
volume_kernel:
.LFB0:
	.cfi_startproc
	mov	x1, x0
	mov	w0, 1015021568
	fmov	s7, w0
	adrp	x0, .LC3
	fmov	v26.4s, 5.0e-1
	mov	w3, 0
	fmov	v5.4s, -1.0e+0
	adrp	x4, .LANCHOR0
	ldr	q17, [x0, #:lo12:.LC3]
	fmov	s2, 5.0e-1
	fmov	v18.4s, -8.75e-1
	stp	d9, d10, [sp, -64]!
	.cfi_def_cfa_offset 64
	.cfi_offset 73, -64
	.cfi_offset 74, -56
	fmov	s3, 1.0e+0
	fmov	v29.4s, 2.5e-1
	stp	d11, d12, [sp, 16]
	fmov	s4, 2.5e-1
	fmov	v30.4s, 1.0e+0
	stp	d13, d14, [sp, 32]
	movi	v19.4s, 0x1
	str	d15, [sp, 48]
	.cfi_offset 75, -48
	.cfi_offset 76, -40
	.cfi_offset 77, -32
	.cfi_offset 78, -24
	.cfi_offset 79, -16
	movi	v6.4s, 0x4
.L4:
	scvtf	s31, w3
	add	x2, x1, 1536
	ldr	q16, [x4, #:lo12:.LANCHOR0]
	fadd	s31, s31, s2
	fmul	s31, s31, s7
	fsub	s31, s31, s3
	fmul	s20, s31, s1
	fmul	s31, s31, s4
	dup	v20.4s, v20.s[0]
	dup	v22.4s, v31.s[0]
	.p2align 3,,7
.L3:
	scvtf	v23.4s, v16.4s
	mov	w0, 28
	movi	v27.4s, 0
	movi	v28.4s, 0
	fadd	v23.4s, v23.4s, v26.4s
	mov	v25.16b, v27.16b
	mov	v24.16b, v27.16b
	fmul	v23.4s, v23.4s, v7.s[0]
	fadd	v23.4s, v23.4s, v5.4s
	fmul	v21.4s, v23.4s, v26.4s
	fmul	v23.4s, v23.4s, v0.s[0]
	.p2align 3,,7
.L2:
	scvtf	v31.4s, v28.4s
	subs	w0, w0, #1
	add	v28.4s, v28.4s, v19.4s
	fadd	v31.4s, v31.4s, v26.4s
	fmul	v31.4s, v31.4s, v17.4s
	fadd	v31.4s, v31.4s, v18.4s
	fmul	v15.4s, v31.4s, v0.s[0]
	fmul	v31.4s, v31.4s, v26.4s
	fsub	v15.4s, v15.4s, v21.4s
	fadd	v31.4s, v31.4s, v23.4s
	fmul	v14.4s, v15.4s, v29.4s
	fmul	v15.4s, v15.4s, v1.s[0]
	fmul	v9.4s, v31.4s, v31.4s
	fmul	v13.4s, v31.4s, v29.4s
	fsub	v14.4s, v20.4s, v14.4s
	fadd	v15.4s, v15.4s, v22.4s
	fadd	v13.4s, v13.4s, v30.4s
	fmul	v10.4s, v14.4s, v14.4s
	fmul	v31.4s, v14.4s, v31.4s
	fmul	v11.4s, v15.4s, v15.4s
	fmul	v12.4s, v15.4s, v29.4s
	fadd	v10.4s, v10.4s, v9.4s
	fmul	v31.4s, v31.4s, v15.4s
	fmul	v14.4s, v14.4s, v29.4s
	fadd	v12.4s, v12.4s, v30.4s
	fadd	v15.4s, v10.4s, v11.4s
	fmul	v31.4s, v31.4s, v31.4s
	fadd	v14.4s, v14.4s, v30.4s
	fadd	v15.4s, v15.4s, v30.4s
	fdiv	v31.4s, v31.4s, v15.4s
	fmul	v12.4s, v12.4s, v31.4s
	fmul	v14.4s, v14.4s, v31.4s
	fmul	v13.4s, v13.4s, v31.4s
	fadd	v27.4s, v27.4s, v12.4s
	fadd	v25.4s, v25.4s, v14.4s
	fadd	v24.4s, v24.4s, v13.4s
	bne	.L2
	mov	v13.16b, v24.16b
	mov	v14.16b, v25.16b
	mov	v15.16b, v27.16b
	add	v16.4s, v16.4s, v6.4s
	st3	{v13.4s - v15.4s}, [x1], 48
	cmp	x2, x1
	bne	.L3
	add	w3, w3, 1
	cmp	w3, 128
	beq	.L10
	mov	x1, x2
	b	.L4
.L10:
	ldr	d15, [sp, 48]
	ldp	d11, d12, [sp, 16]
	ldp	d13, d14, [sp, 32]
	ldp	d9, d10, [sp], 64
	.cfi_restore 74
	.cfi_restore 73
	.cfi_restore 79
	.cfi_restore 77
	.cfi_restore 78
	.cfi_restore 75
	.cfi_restore 76
	.cfi_def_cfa_offset 0
	ret
	.cfi_endproc
.LFE0:
	.size	volume_kernel, .-volume_kernel
	.section	.rodata
	.align	4
	.set	.LANCHOR0,. + 0
.LC0:
	.word	0
	.word	1
	.word	2
	.word	3
.LC3:
	.word	1031798784
	.word	1031798784
	.word	1031798784
	.word	1031798784
	.ident	"GCC: (GNU) 17.0.0 20260813 (experimental)"
	.section	.note.GNU-stack,"",@progbits
