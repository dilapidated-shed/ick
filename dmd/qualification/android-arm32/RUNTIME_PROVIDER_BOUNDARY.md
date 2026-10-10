# Android ARM32 matching-runtime provider boundary

Matching runtime: DMD v2.113.0 commit `74917954b53f7f35b13e61b4438c7253834929ed`.
Target: `armv7a-linux-androideabi21`, A32, AAPCS32 base PCS/softfp.

`Target.va_listType()` resolves the AAPCS32 `std.__va_list` aggregate instead of
`char*`. The provenance-checked runtime overlay declares DigitalMars ARM Android
`c_long_double = real`; both are IEEE binary64. Imports of config, stdarg and
stdio, including the `pragma(printf/scanf)` signatures, pass semantic analysis.

The A32 object pass now traverses struct declarations. Instance fields remain
layout-only and produce no ELF symbols. Context-free static struct methods enter
the same scalar ABI lowerer as top-level functions, while methods requiring a
hidden `this` context still fail closed.

The exact matching `rt/sections_elf_shared.d` therefore traverses the `DSO`
structure and reaches its first static `opApply` overload. It fails nonzero and
removes a deliberately stale object at the unsupported delegate parameter:

```
rt/sections_elf_shared.d(77): Error: A32 backend: A32 scalar lowering supports int/uint/bool/pointers, float, long/ulong and double
```

This is still a compiler boundary, not an Android runtime link. Aggregate values,
instance methods, delegates, slices, containers, TLS, allocation and lifecycle
remain outside the qualified scalar backend.

## Qualification receipt

- compiler source parent: `11488205563bbfc06d518dfd7d18fee114df52c1`
- arm32.d before SHA-256: `8cc8c02afe54aaf34d53d7f4532953b3e2fe54ca799210a7480a0db3516df5aa`
- arm32.d after SHA-256: `5523d58e065f931e6b88dae425c801fb189c5e8b7fe4e94f883472167588fd2a`
- runtime config original SHA-256: `3b31b94a7a77aa02109693ac98882ba1d2cf0b7e2a68ca35ff61a8f9d52e3302`
- runtime overlay SHA-256: `4d463c525edb3c15d0b16544511d5d5e6621e88e77576954ec342ddb465c36e9`
- runtime config result SHA-256: `a82db909f1dbc5e06ac7eea7a7e5f8be52643720e5f87279853f536299c4b0ea`
- provider SHA-256: `c0638931a15bce7dc5cb007c0417811481f1df2367c5674109404f1acd1974ec`
- candidate compiler SHA-256: `469e3d04320eae2498f772387ecddc4f3fe8c005dbaa5ddf1911a90b93c98e6d`
- full existing Android ARM32 verifier: PASS
- struct/static-member execution oracle: PASS
- provider reached static `DSO.opApply`: PASS
- provider object emitted: NO, fail-closed
- Android druntime link: NOT_QUALIFIED
- physical-device execution: NOT_RUN
