# MB01 provider acceptance

`python3 benchmarks/bigmul/acceptance/check_mb01.py` executes the outer checker
under ordinary and optimized Python. The runner requires either explicit source
and output-binary paths, or an explicit binary and its identity manifest. It
never selects `candidate.example.c` implicitly. Build recipes are argument arrays.
Compiler flags, compiler/binary/source hashes, outputs, status and input identity
are retained in the emitted JSON receipt, as required by the campaign interface.

The existing signed hex corpus is checked against Python integers. Full raw limb
write coverage is an MB02 direct-call guard responsibility: hex output strips
high zero limbs and cannot itself prove that every output limb was written.

Known direct calls to schoolbook/GMP/process delegates and declared whole-product
delegation are refused for the candidate role. These lexical/provenance checks
cannot prove absence of obfuscated delegation or dishonest declarations. MB16
must additionally bind the accepted paper implementation, linkage, stage entries
and short-product call dimensions. A successful baseline or smoke run supplies
arithmetic-control evidence only.

This branch uses the host C compiler control lane. Qualified ICK host driver,
ARM32, physical device and real paper candidate acceptance remain separate.
