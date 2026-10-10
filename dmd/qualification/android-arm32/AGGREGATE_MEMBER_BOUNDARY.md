# Android ARM32 struct-layout and static-member boundary

Target: `armv7a-linux-androideabi21`, A32, AAPCS32 base PCS/softfp.
Compiler source parent: `11488205563bbfc06d518dfd7d18fee114df52c1`.

## Qualified behavior

- Struct declarations may be traversed as type/layout containers.
- Instance fields are frontend-owned layout declarations and do not become ELF data symbols.
- Context-free static struct methods with the existing scalar C/D ABI subset are emitted.
- An independent A32 harness calls `aggregate_static_add(19, 23)` and exits zero under QEMU.
- Instance methods are visited rather than silently dropped and fail closed because their hidden `this` context is not yet represented.
- Unions, classes and interfaces remain rejected before any object is published.

The exact matching runtime provider advances from the `DSO` declaration to:

```
rt/sections_elf_shared.d(77): Error: A32 backend: A32 scalar lowering supports int/uint/bool/pointers, float, long/ulong and double
```

## Receipt

- arm32.d before SHA-256: `8cc8c02afe54aaf34d53d7f4532953b3e2fe54ca799210a7480a0db3516df5aa`
- arm32.d after SHA-256: `5523d58e065f931e6b88dae425c801fb189c5e8b7fe4e94f883472167588fd2a`
- positive fixture SHA-256: `15ab5506fc792ff9c26ef5bb7656fcbefc51ffbe02005a806ae907362fb1d64a`
- negative fixture SHA-256: `21a79b3b2c281d599da43925018bd9e25ac367bdfb6c9b770e1e8502019cc0b5`
- harness SHA-256: `1004ceff26df8bdc207f4e80e6fbbbe041536fd9271e4136e86d16a8172810d1`
- candidate compiler SHA-256: `469e3d04320eae2498f772387ecddc4f3fe8c005dbaa5ddf1911a90b93c98e6d`
- positive object SHA-256: `a38ac8cbc154a8288d6ecf572e20cad7e8f97d85c6f07158d88c32cd86f0981d`
- execution oracle SHA-256: `5468cfa72481cf4a87d8d3f8f16cdeead6e7d86e45dc690cea8bc4a1e16e66e5`
- layout fields emitted as ELF symbols: NO
- static method execution: PASS
- instance method stale-output removal: PASS
- full prior ARM32 regression suite: PASS
- Android druntime link: NOT_QUALIFIED
- physical-device execution: NOT_RUN


The subsequent [delegate transport qualification](DELEGATE_TRANSPORT_BOUNDARY.md)
admits two-pointer delegate parameters without changing this aggregate boundary.
The matching runtime provider then enters `DSO.opApply` and stops while lowering
the `foreach` header's aggregate `Array!(DSO*)` range.
