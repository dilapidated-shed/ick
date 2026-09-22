# ICK licensing

ICK is intended to remain free software and to preserve the licensing boundaries of the work it is derived from.

## GCC-derived compiler source

The compiler line is derived from GCC. GCC-derived source remains under the license stated by the corresponding upstream files, normally GNU GPL version 3 or later. Copyright and license notices inherited from GCC must not be removed merely because a file is renamed, simplified, or moved into ICK.

The `gcc/` submodule records the exact unmodified reference source.
`ick/source/` contains complete GCC-derived files and remains under their
inherited file-level licenses. `ick/SOURCE.lock` records the GCC base and the
transitional `isomorphisms/rhs` commit from which the first squashed ICK source
layer was imported. Materializing the two layers does not change either one's
license.

## Runtime-library exception

Some GCC runtime-library files carry the GCC Runtime Library Exception 3.1. That exception applies only where the relevant file's notice says it applies. It is not a blanket exception for arbitrary GCC-derived compiler source.

The purpose of the exception is to allow eligible compilation processes to produce target programs under the program author's chosen terms even when covered GCC runtime material is combined into the target code. ICK must preserve the exception and the file-level notices on covered runtime material.

## Meaning model

The pinned meaning model in `model/` has its own license. `model/LICENSE` is the authority for that subtree and currently records the MIT license and its upstream copyright notice.

## Compiler output

Using a GPL-licensed compiler does not by itself relicense the input program. Where generated target code incorporates covered GCC runtime-library material, the runtime-library exception and its eligibility conditions matter. ICK must not make broader licensing claims than the notices actually grant.

## Redistribution gate

Before an ICK compiler artifact is published:

1. Record the exact source commit used to build it.
2. Preserve all applicable GCC copyright and license notices.
3. Include the pinned `gcc/` source and `ick/source/` layer, or point unambiguously to the complete corresponding source required by the applicable licenses.
4. Preserve the GCC Runtime Library Exception on every covered runtime file.
5. Record licenses and checksums for separately vendored data such as the meaning model.
6. Do not describe a compiler artifact as clean-room or independently licensed when it contains GCC-derived source.
