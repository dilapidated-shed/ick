# Compiler lines: IDK and upstream DMD

ICK is the umbrella repository for building, qualifying, and comparing compiler work. It does not require every compiler experiment to be suitable for upstream D.

## IDK

`idk` is the personal compiler line.

IDK may deliberately choose semantics and representations that are not intended for upstream DMD, including:

- Unicode source syntax and alternate operator spellings;
- compact and specialized numeric representations;
- operation-specific widening and requantization rules;
- E5M3 arithmetic policy;
- finite-circle, quaternion, projective, and other specialized value types;
- experiments whose value is application-specific or still being measured.

IDK changes should be judged on their own contracts, measurements, and target applications. They do not need to pretend to be conservative DMD changes.

The historical `dmd` branch already contains early Icky-D syntax merges. Treat it as legacy IDK history rather than the base for new upstream-oriented work. New IDK work should start from `idk`.

## Upstream DMD

`dmd-upstream` is the boring, upstream-facing line.

Changes here should preserve ordinary D semantics and solve general compiler problems, for example:

- ABI and calling-convention correctness;
- Android/ARM target bring-up;
- backend instruction selection and relocation correctness;
- BetterC bugs and unwanted runtime dependencies;
- standard-language frontend/backend bugs;
- representation-preserving compiler infrastructure that does not prescribe an IDK representation policy;
- narrow, regression-tested performance improvements that are useful without IDK-specific assumptions.

An upstream-facing patch should make sense when IDK does not exist.

## Moving an idea between lines

If an IDK experiment exposes a general compiler defect, split the general fix from the policy:

1. reproduce the defect with ordinary D;
2. put the minimal general fix and regression test on `dmd-upstream`;
3. keep IDK-specific semantics, syntax, types, or lowering policy on `idk`;
4. let IDK consume the upstreamable mechanism rather than making DMD adopt the experiment.

Conversely, a DMD backend improvement can be consumed by IDK without moving IDK policy into the upstream patch.

## Existing branches

Some existing branches and pull requests predate this split and use names such as `dmd-compact-representations`. Their names are historical. The compact scalar, E5M3-policy, and specialized-geometry stack is IDK-specific even where the branch name still says `dmd`.

Do not rewrite published history merely to rename those branches. New work should use the explicit lines above.
