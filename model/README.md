# Meaning model

ICK and IRK use `minishlab/potion-base-2M`, pinned at revision
`389b9f64be5aa4ae7a6bc6fe95ef20ce485ae5da`.

This is a 64-dimensional static embedding table with 29,528 token vectors and
simple pooling. It does not run a transformer during compilation. The
published weights are 7.56 MB and MIT licensed.

The vector model proposes semantic kinds for unfamiliar words. The compiler's
ordinary types, runtime guards, refinements, or proofs must establish that the
proposal is true.

`fetch.sh` downloads the three inference files and checks every SHA-256 digest.

Source and model card:
https://huggingface.co/minishlab/potion-base-2M

