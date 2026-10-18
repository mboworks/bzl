# 0.8.0

- Add `versions.normalize_tuple` and `versions.normalize_string` for grouping
  interleaved version suffixes with configurable string separators.

- Add `runfiles.key(ctx, file)` for constructing runtime lookup keys from Bazel files.

- Add stable version sorting, predicate filtering, earliest/latest selection with data-preserving
  keys and caller-controlled prerelease filtering in every mode.

- Automate README installation-version preparation and reject stale release references
  during validation and release publication.

# 0.7.0

- Add `versions.with_mode` for immutable API objects with a consistent caller-selected default
  across every function. Explicit per-call modes still take precedence; original defaults remain.
- Add component-count/index, prerelease-identification, and build/local-metadata helpers, including
  typed boolean and text comparisons in requirement expressions. Expression calls inherit the
  requirement checker's version mode, including nested calls.

# 0.6.0

- Document both public modules in `docs/versions.md` and `docs/paths.md`, including complete legacy,
  SemVer and PEP 440 mode contracts; keep usage overviews in the root README.

- Add opt-in `mode = "pep440"` for Python version parsing, precedence, and specifier clauses;
  preserve legacy and SemVer defaults. Include a developer-only packaging conformance oracle.

- Add `versions.prefix`, `versions.components`, `versions.compatible`, and `versions.matches`.
- Support compatible-release (`~=`), negated compatible (`!~=`), extended wildcard-compatible
  (`~~=`), and negated extended (`!~~=`) requirements, plus trailing `.*` matching/exclusion
  (`==`, `!=`). Extended compatibility adds a stable lower bound to prefix matching.
- Add `versions.major`, `versions.minor`, `versions.patch` and allowlisted, nested version-function
  expressions with an implied or explicit candidate and literal positional/keyword arguments.
- Add explicit `constants` dictionaries to requirement checkers for caller-defined names, resolved
  at evaluation time on expression left sides and inside function arguments. Functions keep call
  syntax (`major()`), independent of constants with the same name (`major`).
- Add explicit `mode = "semver"` to parsing, comparisons, and requirements; existing APIs keep
  `mode = "legacy"` by default. SemVer mode zero-pads release comparisons and preserves distinct
  prerelease identifiers such as `rc1` and `rc.1`, with lexical `rc10 < rc2` ordering.
- Fetch shallow publication snapshots and report complete site size with a 250 MB advisory budget.

# 0.5.1

- Transfer the canonical repository from `helly25/bzl` to `mboworks/bzl` and
  publish future releases under the new `mboworks_bzl` module name.

# 0.5.0

- [BC] Dropped legacy `WORKSPACE` support; the module is now bzlmod-only.

# 0.4.4

- Re-release of `0.4.3` with no functional changes (release/CI tooling only).

# 0.4.3

- Added `paths.ensure_trailing_slash` and `paths.ensure_trailing_slash_windows` to append a single trailing separator, handling roots and existing trailing separators. An optional `default_if_empty` controls the fallback for empty input (e.g. `"/"` to anchor at the platform root).

# 0.4.2

- Fix release naming and tagging scheme back to "1.2.3" style without 'v' prefix.

# 0.4.1

- Added explicit Windows and Bazel 9 support for the Bazel module releases.

# 0.4.0

- Implement paths library.

# 0.3.1

- Fixed some cases of comparisons that contain '-' or '+' against versions that are missing those parts.

# 0.3.0

- Added `skip_build` parameter to control whether comparisons adhere to Semver-10.
- [BC] Changed `version.parse` and `version.compare` to take parameter `error` as a keyword only parameter.

# 0.2.1

- Improved support for mixed type comparisons.

# 0.2.0

- Added support for parsing out 'pre_release' and 'build' components.
- Added `versions.compare`.
- Added 'pre_release' and 'build' support for comparisons.
- Added CI run for Windows (may be dropped at any future point).

# 0.1.2

- Fixed workspace file to work for transitive repos.

# 0.1.1

- Fixed some naming issues and remove mbo references.

# 0.1.0

Initial version.
