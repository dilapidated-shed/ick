# Android ARM32 delegate-parameter transport boundary

Target: `armv7a-linux-androideabi21`, A32, AAPCS32 base PCS/softfp.
Compiler source parent: `fbbffab091652a84cf9c3238f28226dc23b2936a`.

D delegates are fat pointers with the context pointer at offset zero and the
function pointer at offset four. Unlike eight-byte scalar types, their natural
alignment is four bytes. This qualification transports delegates as opaque values;
it does not invoke them or return them.

## Qualified behavior

- A delegate after one word occupies r1:r2; a following word occupies r3.
- A delegate after four register arguments occupies `[sp]` and `[sp + 4]`;
  the following word occupies `[sp + 8]`.
- A D forwarding function preserves both words while staging arguments
  left-to-right and calling a declaration-only D callee.
- Independent assembly sinks check every register and stack word.
- Independently compiled Clang C functions using an equivalent two-pointer
  struct accept the same AAPCS32 register and stack layout.
- A delegate that would straddle r3 and the stack is rejected until AAPCS32
  composite splitting is implemented; stale output is removed.
- Delegate invocation, return values, globals and arbitrary memory access remain
  rejected or outside this transport-only slice.

The matching runtime provider enters `DSO.opApply` and stops while lowering the
`foreach (dso; _loadedDSOs)` header's aggregate `Array!(DSO*)` range:

```
rt/sections_elf_shared.d(79): Error: A32 backend: A32 lowering supports the scalar subset, delegate transport, and 16-byte float4 vectors
```

## Receipt

- backend arm32.d before SHA-256: `ecacefb28816d25cf4be439661605f123b1a1d5686774dfce60ef5a3c86f740e`
- backend arm32.d after SHA-256: `bdeefd69bfc20c30bc8bfb5032f7db20f156f04630533a540760d403cacf735a`
- glue arm32.d before SHA-256: `5523d58e065f931e6b88dae425c801fb189c5e8b7fe4e94f883472167588fd2a`
- glue arm32.d after SHA-256: `95d64090e34593c76d10b9418b16d9c095f5ada5148ab7aeb5a69a8aec17b7e6`
- positive D source SHA-256: `aad638cbf2647cd30a7e6db0487b59fca29bb5b2d2f981b4abf499204868dfcb`
- negative split source SHA-256: `1d924ff8afa47e87068e70e80d170b70f3e795dd23bfc2f3954932e6cfbe2cf4`
- C reference SHA-256: `4a0a0966615251f8465fe22a28baaa7fc529b328a4fad6866c666bd1bca0c04f`
- assembly harness SHA-256: `715b53692f5173165c5a7cde3e96cf75948ecfd1aa7a7c5db1b72c6ffb185b62`
- candidate compiler SHA-256: `e343542e8ce5d00c20f218883f7938837cacb45e75833a95cdbaccca8fec158f`
- D object SHA-256: `53062e3ca8fa5110381c1d91642012be2bb92cd558e1f7ab62257938b96af9ce`
- C reference object SHA-256: `e767dc563765eee29451cd4f9155914e29b323a2ebd66a654993db77efa5de60`
- execution oracle SHA-256: `91c98a660339929dfd6f0e39b0ed90c05685721c7ea0f94cb7fd2013390e8577`
- register transport: PASS
- stack transport: PASS
- r3/stack split stale-output removal: PASS
- full prior ARM32 regression suite: PASS
- Android druntime link: NOT_QUALIFIED
- physical-device execution: NOT_RUN
