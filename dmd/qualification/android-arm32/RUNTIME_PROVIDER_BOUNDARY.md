# Android ARM32 matching-runtime provider boundary

Matching runtime: DMD v2.113.0 commit `74917954b53f7f35b13e61b4438c7253834929ed`. Target: `armv7a-linux-androideabi21`,
A32, AAPCS32 base PCS/softfp.

`Target.va_listType()` now resolves the AAPCS32 `std.__va_list` aggregate
instead of `char*`. A provenance-checked runtime overlay declares
DigitalMars ARM Android `c_long_double = real`; both are IEEE binary64.
A semantic fixture importing config, stdarg, and stdio passes, including
the `pragma(printf/scanf)` signatures.

The exact matching `rt/sections_elf_shared.d` then reaches the A32 backend,
fails nonzero, and removes a deliberately stale object. Its first backend
diagnostic is:

```
rt/sections_elf_shared.d(75): Error: A32 backend: declaration requires data/runtime emission not implemented by the initial A32 slice
```

This is a compiler boundary, not an Android runtime link. Aggregate members
and methods, slices, delegates, containers, TLS, allocation and lifecycle
remain outside the qualified scalar backend.

## Qualification receipt

- target.d before SHA-256: `388f7ebdee3346b65d90c915bcc30e6b9cb00abe465b464b9a14451efb957cfc`
- target.d after SHA-256: `6735a1617ddd7ebab1913b3dccb1082f6a0c7f0188711dbf90ab6774076b61b6`
- runtime config original SHA-256: `3b31b94a7a77aa02109693ac98882ba1d2cf0b7e2a68ca35ff61a8f9d52e3302`
- runtime overlay SHA-256: `4d463c525edb3c15d0b16544511d5d5e6621e88e77576954ec342ddb465c36e9`
- runtime config result SHA-256: `a82db909f1dbc5e06ac7eea7a7e5f8be52643720e5f87279853f536299c4b0ea`
- provider SHA-256: `c0638931a15bce7dc5cb007c0417811481f1df2367c5674109404f1acd1974ec`
- candidate compiler SHA-256: `8bcfb6489a4500ace8f93cca07f958e6860697b59f76bffda191db316482f85d`
- frontend ABI fixture: PASS
- provider reached A32 backend: PASS
- provider object emitted: NO, fail-closed
- Android druntime link: NOT_QUALIFIED
- physical-device execution: NOT_RUN
