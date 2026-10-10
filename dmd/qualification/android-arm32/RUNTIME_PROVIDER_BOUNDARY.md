# Android ARM32 matching-runtime provider boundary

Matching runtime: DMD v2.113.0 commit `74917954b53f7f35b13e61b4438c7253834929ed`.
Target: `armv7a-linux-androideabi21`, A32, AAPCS32 base PCS/softfp.

The frontend ABI repairs remain unchanged: AAPCS32 `va_list` resolves as
`std.__va_list`, and the pinned runtime overlay declares DigitalMars ARM Android
`c_long_double = real` with the recorded hashes.

The A32 object pass traverses struct declarations and transports delegate
parameters as their specified two-pointer representation: context pointer first,
function pointer second. The delegate has four-byte alignment, so a delegate after
one word occupies r1:r2 rather than being rounded to r2:r3 like `long` or `double`.
Fully stack-passed delegates occupy consecutive words. The AAPCS32 r3/stack split
case remains explicitly rejected.

The exact matching `rt/sections_elf_shared.d` now enters the first static
`DSO.opApply` body. It fails nonzero and removes a deliberately stale object
while lowering the `foreach (dso; _loadedDSOs)` header's aggregate
`Array!(DSO*)` range value:

```
rt/sections_elf_shared.d(79): Error: A32 backend: A32 lowering supports the scalar subset, delegate transport, and 16-byte float4 vectors
```

This is still a compiler boundary, not an Android runtime link. Aggregate range
values and `foreach`, delegate invocation and returns, instance methods,
containers, TLS, allocation and lifecycle remain outside the qualified backend.

## Qualification receipt

- compiler source parent: `fbbffab091652a84cf9c3238f28226dc23b2936a`
- backend arm32.d before SHA-256: `ecacefb28816d25cf4be439661605f123b1a1d5686774dfce60ef5a3c86f740e`
- backend arm32.d after SHA-256: `bdeefd69bfc20c30bc8bfb5032f7db20f156f04630533a540760d403cacf735a`
- glue arm32.d before SHA-256: `5523d58e065f931e6b88dae425c801fb189c5e8b7fe4e94f883472167588fd2a`
- glue arm32.d after SHA-256: `95d64090e34593c76d10b9418b16d9c095f5ada5148ab7aeb5a69a8aec17b7e6`
- provider SHA-256: `c0638931a15bce7dc5cb007c0417811481f1df2367c5674109404f1acd1974ec`
- candidate compiler SHA-256: `e343542e8ce5d00c20f218883f7938837cacb45e75833a95cdbaccca8fec158f`
- full existing Android ARM32 verifier: PASS
- struct/static-member oracle: PASS
- delegate register and stack transport oracle: PASS
- r3/stack delegate split: FAIL_CLOSED
- provider entered static `DSO.opApply` body: PASS
- provider object emitted: NO, fail-closed
- Android druntime link: NOT_QUALIFIED
- physical-device execution: NOT_RUN
