# MB21 partial benchmark package

Run `python3 benchmarks/bigmul/release/check_mb21.py --run-controls
--allow-missing-bc --output PATH` as one argument-array invocation. The driver
runs the available MB controls, preserves complete command/stdout/stderr/status
and raw child receipts, verifies an optional expected native architecture and
lists missing check drivers. The missing-bc option is explicit and never upgrades
Python-only oracle coverage to independent bc acceptance.

The package always reports benchmark readiness BLOCKED while required providers,
modes and actual paper implementation are absent. `--require-ready` returns
nonzero. Synthetic gate controls reject wrong products, stale source/corpus,
example substitution, absent or partial stage receipts and unpaired inputs.
Those synthetic controls prove gate behavior only; they are not real receipts.
Actual ready-manifest ingestion/admission is deliberately not enabled for this
partial package. It must consume qualified immutable stage receipts and rerun
the combined source once all mandatory deliverables exist.

Current available scope is MB01, extended MB02, MB03, MB04 (bc required unless
explicitly omitted), MB05 host comparison providers, standalone MB06 and
baseline/control portions of MB17–MB20. MB07–MB16 are absent.
MB14/AIX native access and accepted MUL5 remain concrete external or
implementation dependencies. MB17's recursive trace, MB19's paper certificate
contracts and MB20's paper component schedules remain pending. No complete
campaign, ICK code generation, physical-device speed or paper speedup is claimed.

This follows the existing MUL6 qualification ownership. It adds no competing
workflow, merge policy or default provider-selection rule.

MB05 requires the GMP 6.3.0 header/runtime pair by default. The native workflow
installs its development package and bc. For a host using an extracted matching
development package, `MB05_GMP_INCLUDE` and `MB05_GMP_LIBRARY` explicitly select
the header directory and shared library; both are recorded and hashed by MB05.
The standalone MB05 driver's `--allow-missing-gmp` records omitted coverage;
the integrated campaign does not silently pass that option.
