# PEP 440 follow-up: scope and API review

This draft follows the legacy/SemVer helper PR. It is intentionally separate from the LLVM selector
work: that work requires SemVer precedence and familiar requirement operators, and does not require
a Python package version engine. Keep the draft open until these implications are accepted.

## What the implementation adds

The implementation follows the [PyPA version scheme and specifiers](https://packaging.python.org/en/latest/specifications/version-specifiers/).
Parsing recognizes epochs, releases, prereleases, postreleases, development releases and local
labels. It normalizes their documented aliases and separators. Ordering implements numeric release
padding, normalized prerelease phases, development/postrelease precedence and Python local ordering.
Clause predicates add the PEP 440 compatible release and wildcard rules, local-label restrictions,
exclusive-comparison exclusions, and arbitrary equality.

The implementation is pure Starlark. A pinned developer-only `packaging==26.0` generator produces
normalization, pairwise ordering and clause fixtures; Bazel consumers need neither Python nor a new
module dependency. Pre-commit checks that the generated fixture matches the pinned oracle.

## Public API implications

1. **The parse result has more structure.** A flat list cannot preserve epoch, pre, post, dev and local
   distinctions clearly. PEP 440 parsing returns a record; the other modes still return lists. This
   is opt-in and compatible, but callers accepting arbitrary modes must account for both shapes.
   A separate Python parsing API would avoid the union return type at the cost of another API.
2. **Precedence and requirements are different operations.** Direct `gt(1.0.post1, 1.0)` is true;
   the requirement `>1.0` excludes it. Likewise `eq(1.0+local, 1.0)` is false, while a `==1.0`
   requirement matches it. The existing `compare` entry point means clause evaluation in PEP 440
   mode. This distinction must remain documented and tested.
3. **`skip_build` cannot stand for Python local-version policy.** It retains its current behavior in
   legacy/SemVer mode and has no effect in PEP 440 mode. Direct PEP 440 ordering includes locals;
   requirements ignore or include them as the particular clause requires. Another option is a
   separate Python API with signatures that omit `skip_build` entirely.
4. **Parsed requirements retain pattern strings.** The old modes return component lists; Python
   mode retains operand strings for `.*` and arbitrary equality. Invalid operands fail when checked.
   Reusing parsed requirements requires preserving their mode.
5. **Version predicates do not implement an installer.** The implementation evaluates candidates
   including prereleases and implements the operator-specific exclusions. Candidate-set admission,
   installed-version exceptions, stable preference, and prerelease fallback belong to the resolver.
   Tests compare predicate behavior with `Specifier.contains(..., prereleases=True)`.

## Parts that can be omitted

- The entire follow-up can remain unmerged without delaying SemVer-based LLVM selectors.
- `===` is an isolated escape hatch and can be omitted if arbitrary legacy version identity has no
  consumer. If omitted, document that the supported specifier set excludes arbitrary equality.
- Epochs, normalized prereleases, post/dev releases and local labels are intertwined with PEP 440
  ordering. Removing those while calling the mode full PEP 440 would be misleading. A smaller
  numeric-only requirement engine should be described as such instead.
- The parsed record can remain internal if exposing Python mode on `parse` is too broad. A follow-up
  limited to comparison and requirement predicates would still need an internal complete parser.
- Package resolution, requirements-file syntax beyond version clauses, markers and dependency URLs
  are outside this change and should stay outside the version helper library.

## Recommendation

Keep the SemVer/legacy PR independent. Review the record return type and the difference between
precedence and clause evaluation before adopting this mode. If full Python versions have no concrete
consumer, retain this as a draft rather than creating a permanent compatibility obligation for the
LLVM selector feature alone. Mode naming alone does not justify adoption.
