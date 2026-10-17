# MBO Works bzl, a Bazel support library <img src="docs/assets/mboworks-logo.png" alt="MBO Works" width="64" height="64" align="right">

[Release website](https://mboworks.github.io/bzl/) · [Infrastructure and publishing](docs/infrastructure.md)

This library provides [Bazel](http://bazel.build) [Starlark](https://bazel.build/rules/language) functionality meant to help in maintaining other libraries.

[![Test](https://github.com/mboworks/bzl/actions/workflows/main.yml/badge.svg)](https://github.com/mboworks/bzl/actions/workflows/main.yml)

The following libraries are implemented:

- [Versions](#versions)
- [Paths](#paths)

## Versions

Implements versioning functions that mostly follow [Semver](https://semver.org/).

The existing parsing, comparison, and requirement APIs accept `mode = "legacy"` (the default) or
`mode = "semver"`, or `mode = "pep440"`. The default preserves their historical behavior. Select a mode explicitly when
passing parsed versions or requirements between APIs.

- **Legacy:** release component counts affect ordering (`1.2 < 1.2.0`). Prerelease identifiers with
  numeric suffixes are split: `rc1` and `rc-1` become `rc`, `1`. Build identifiers are split only at
  dots. This mode preserves compatibility; it is neither strict SemVer nor Python PEP 440.
- **SemVer:** numeric release components compare with zero padding, so `1.2`, `1.2.0`, and `1.2.0.0`
  compare equal. This extends SemVer's three-component releases using
  [Python's release comparison convention](https://packaging.python.org/en/latest/specifications/version-specifiers/#final-releases).
  [SemVer prerelease precedence](https://semver.org/#spec-item-11) is preserved: numeric identifiers
  precede alphanumeric identifiers, alphanumeric identifiers compare case-sensitively in ASCII order,
  and stable releases follow their prereleases. `rc1` differs from `rc.1`, and `rc10` precedes `rc2`.
  Numeric release/prerelease identifiers with leading zeros and malformed suffix identifiers fail.
  Parsing preserves the written release component count, including trailing zeros.

The new `compatible` and `matches` helpers default to `mode = "semver"`; they also accept `"legacy"`
for callers that explicitly need historical precedence. `prefix` and `components` simply select
release components and never pad unless requested. No existing caller changes behavior by upgrading.

The full functionality is exposed as a single struct containing all functions.

The version parameters support:

- a string that can be parsed according to:
  `major`['.' `minor` [ '.' `patch` [ '.' `digits`]\*]] ['-' [^+]+] ['+' .\*]
- a `list` or `tuple` where each component is a version part. If present, then:
  - a pre-release component must be separated by a single "-" and split by ".".
  - a build component must be separated by a single "+" and split by "."
- a single `int` which will be the major version.
- anything else is an error and the functions will `fail`.
- unlike Semver, the function allows any number of numeric version components.

Note: Most functions support a `skip_build` parameter. If `True`, then any
present build component will be dropped. The parameter defaults to `False`
for parsing and `True` for comparisons since Semver dictates that
the build component must be ignored for precedence (see
[Semver-10](https://semver.org/#spec-item-10)).

The functionality has exhaustive tests. If something still works wrong please,
file a bug report or propose a fix.

Example:

```starlark
load("@mboworks_bzl//bzl/versions:versions.bzl", _versions = "versions")

my_version = "25.33.42"
min_version = (10, 11, 12)
if _versions.lt(my_version, min_version):
  fail("My version {my_version} is earlier than {min_version}.".format(
    my_version = my_version,
    min_version = min_version,
  ))
```

Provides:

- `load("@mboworks_bzl//bzl/versions:versions.bzl", _versions = "versions")`
  - `versions` is a single import structure:
    - `parse`: Parses a version while preserving its release component count.
    - `prefix(version, count, *, mode = "semver")`: Returns at most `count` release components as a dot-separated string.
    - `components(version, *, start = 0, end = None, pad = False, mode = "semver")`: Returns a release component slice.
    - `compatible(version, required, *, skip_build = True, mode = "semver")`: Tests a compatible-release requirement.
    - `matches(version, pattern, *, skip_build = True, mode = "semver")`: Tests an exact version or a trailing `.*` pattern.
    - `ge`: Implements `L >= R`.
    - `gt`: Implements `L > R`.
    - `le`: Implements `L <= R`.
    - `lt`: Implements `L < R`.
    - `eq`: Implements `L == R`.
    - `ne`: Implements `L != R`.
    - `cmp`: Returns -1 if `L < R`, 0 if `L == R`, and 1 if `L > R`.
    - `compare`: Implements `L OP R`.
    - `check_one_requirement`: Checks a version adheres to a single requirement.
    - `check_all_requirements`: Checks a version adheres to a requirements list.
    - `parse_requirements`: Parses a requirements specification.

### Selecting release components

`prefix` and `components` exclude prerelease and build suffixes and return strings. `prefix(v, n)`
is `components(v, end = n)`; it never pads, and `n` must be a non-negative integer.

```starlark
versions.prefix("1.2.3.4", 2)                         # "1.2"
versions.prefix("1.2", 4)                             # "1.2"
versions.components("1.2.3.4", end = 2)               # "1.2"
versions.components("1.2.3.4", start = 1, end = 3)    # "2.3"
versions.components("1.2", end = 4)                   # "1.2"
versions.components("1.2", end = 4, pad = True)       # "1.2.0.0"
versions.components("1.2.3", start = 1, end = 4, pad = True)  # "2.3.0"
```

`start` is inclusive and `end` exclusive. Negative indices are relative to the original release
length. `end = None` uses that original length. With `pad = True`, an explicitly supplied positive
`end` extends the release with zeros before slicing; padding does not change how negative indices
are resolved. An empty selection returns `""`.

### Matching and compatible releases

These helpers adopt Python's
[compatible release](https://packaging.python.org/en/latest/specifications/version-specifiers/#compatible-release)
and [version matching](https://packaging.python.org/en/latest/specifications/version-specifiers/#version-matching)
semantics for numeric release components, using SemVer syntax and precedence for suffixes.
The legacy and SemVer modes are not Python package version parsers: Python epochs, `dev`/`post` suffixes and Python
prerelease normalization are not supported. Prerelease admission is a separate selection policy;
these predicates evaluate a candidate even if it is a prerelease. Build metadata is ignored unless
`skip_build = False`, an extension that opts out of SemVer's metadata precedence rule.

`compatible(candidate, required)` tests a lower bound and a release prefix. The requirement must
have at least two numeric release components; all but its last component form the prefix. Its
original precision is significant, including trailing zeros:

```starlark
versions.compatible("1.4.5", "1.4.0")  # True
versions.compatible("1.5.0", "1.4.0")  # False
versions.compatible("1.9.0", "1.4")    # True
versions.compatible("2.0.0", "1.4")    # False
# ~=1.4     means >=1.4,     ==1.*
# ~=1.4.5   means >=1.4.5,   ==1.4.*
# ~=1.4.5.0 means >=1.4.5.0, ==1.4.5.*
```

The release prefix excludes even prereleases of the next series: `1.5.0-rc.1` does not satisfy
`~=1.4.5`. A prerelease suffix in the requirement affects the lower bound, not the prefix.

`matches(candidate, pattern)` uses zero-padded exact equality without a wildcard. A single trailing
`.*` instead compares whole release components and ignores remaining components and suffixes:

```starlark
versions.matches("1.2", "1.2.0")           # True
versions.matches("1.2.3", "1.2.*")         # True
versions.matches("1.20.3", "1.2.*")        # False
versions.matches("1.2.0-rc.1", "1.2.*")    # True (admission is caller policy)
versions.matches("1", "1.0.*")             # True (zero padding)
```

A wildcard requires a non-empty numeric release prefix. Bare `*`, partial or interior wildcards,
and wildcards after prerelease/build suffixes fail. `compatible` and `matches` require non-negative
numeric release components and valid SemVer suffix identifiers; the general-purpose `parse` helper
remains permissive for historical inputs. Never normalize a requirement with padding before calling
`compatible`, since that would change its compatibility boundary.

The requirement-string APIs (`compare`, `check_one_requirement`, `check_all_requirements`, and
`parse_requirements`) support `~=`, `==` and `!=` with trailing `.*`, and the existing `<`, `<=`, `>`,
`>=` operators. Their default remains legacy precedence; pass `mode = "semver"` for the
zero-padded, identifier-preserving semantics described above. A missing operator means `==`. Comma-separated clauses are ANDed, and whitespace
around clauses and operands is accepted. Wildcards with ordering operators or `~=` fail. These are
operators in strings, not overloaded Starlark operators:

```starlark
versions.compare("1.4.8", "~=", "1.4.5", mode = "semver")  # True
versions.check_one_requirement("1.2.3", "==1.2.*", mode = "semver")  # True
versions.check_all_requirements("1.4.8", "~=1.4.5,!=1.4.7", mode = "semver")  # True
requirements = versions.parse_requirements("==1.2.*,!=1.2.4", mode = "semver")
versions.check_all_requirements("1.2.3", requirements, mode = "semver")  # True
```

### Python PEP 440 mode (draft follow-up)

`mode = "pep440"` implements the
[Python version scheme and specifier clauses](https://packaging.python.org/en/latest/specifications/version-specifiers/):
epochs, arbitrary-length numeric releases, normalized alpha/beta/RC prereleases, post/development
releases, local versions, compatible releases, wildcard matching/exclusion, ordered clauses and
arbitrary equality (`===`). Parsing accepts normalized aliases, optional separators, a leading `v`,
leading zeros, and surrounding whitespace. Direct comparisons include local versions; requirement
matching ignores candidate local labels unless an equality requirement supplies one.

```starlark
versions.eq("1.2-rc1", "1.2rc.1", mode = "pep440")  # True
versions.lt("1.2rc2", "1.2rc10", mode = "pep440")   # True (numeric RC ordering)
versions.lt("1.2.dev1", "1.2a1", mode = "pep440")   # True
versions.lt("1.2", "1.2.post1", mode = "pep440")    # True
versions.eq("1.2+local", "1.2", mode = "pep440")    # False (direct comparison)
versions.matches("1.2+local", "1.2", mode = "pep440")  # True (requirement matching)
versions.check_one_requirement("1.2.post1", ">1.2", mode = "pep440")  # False
versions.check_one_requirement("1.2rc1", "<1.2", mode = "pep440")     # False
```

These clause-specific exclusions are required by PEP 440 even when a caller admits prereleases.
`cmp`, `eq`, `ne`, `lt`, `le`, `gt`, and `ge` compare version precedence directly; `compare` and the
requirement-string APIs evaluate specifier clauses. Thus `gt("1.2.post1", "1.2", mode = "pep440")`
is true, while the `>1.2` requirement above is false. Local identifiers are forbidden in ordered
and compatible-release requirements; an equality requirement can include them. `skip_build` has
no effect in this mode: Python local-version semantics are not SemVer build metadata semantics.

`parse(..., mode = "pep440")` returns an immutable record with `scheme = "pep440"`, `epoch`,
`release` (tuple), `pre` (phase/number tuple or `None`), `post` and `dev` (integer or `None`),
`local` (tuple), and `normalized` (string). Records can be reused in PEP 440 comparisons. This
mode accepts strings, integers, numeric release lists/tuples, or those parsed records. It does not
reinterpret legacy/SemVer suffix lists as Python versions. `prefix` and `components` accept
`mode = "pep440"` and return release components only, excluding even the epoch.

`parse_requirements(..., mode = "pep440")` retains each operand string in its `version` field
because wildcard and `===` operands are patterns. Pass the same mode when evaluating its results.
Malformed operands fail during evaluation. Other modes keep their existing parsed-list shape.

These functions implement version predicates, not a package installer. They do not resolve
packages, interpret environment markers, parse distribution names/URLs, or implement the
collection-level prerelease policy (installed versions, stable preference and prerelease fallback).
Predicate tests use the reference library with `prereleases=True`; callers own admission policy.

PEP 440 tests consume checked-in fixtures generated with `packaging==26.0`; Python is a developer-only
oracle, not a dependency of Starlark consumers. To regenerate or verify them:

```sh
python3 -m pip install -r tools/requirements-pep440.txt
python3 tools/generate_pep440_cases.py
python3 tools/generate_pep440_cases.py --check
```

See [the scope review](docs/pep440-review.md) before accepting the draft's public API.

## Paths

Implements file path manipulation functions.

NOTE: These functions do not support Windows drive letter relative paths.

Provides:

- `load("@mboworks_bzl//bzl/paths:paths.bzl", _paths = "paths")`
  - `paths` is a single import structure:
    - `collapse`: Collapse '.' and '..' path segments for normalized Unix paths.
    - `collapse_windows`: Collapse '.' and '..' path segments for normalized Windows paths.
    - `ensure_trailing_slash`: Ensure a Unix path ends with a single trailing slash.
    - `ensure_trailing_slash_windows`: Ensure a Windows path ends with a single trailing backslash.
    - `is_absolute`: Returns `True` if a Unix path is absolute.
    - `is_absolute_windows`: Returns `True` if a Windows path is absolute.
    - `join`: Join path elements and return as normalized Unix paths.
    - `join_windows`: Join path elements and return as normalized Windows paths.
    - `join_respect_absolute`: Join path elements (respecting absolute paths) and return as normalized Unix paths.
    - `join_respect_absolute_windows`: Join path elements (respecting absolute paths) and return as normalized Windows paths.
    - `normalize`: Normalize a Unix file path.
    - `normalize_windows`: Normalize a Windows file path.

## Installation

The library is available as a Bazel module (bzlmod) and supports macOS, Ubuntu
and Windows with Bazel versions 7.x, 8.x and 9.x (other systems are not tested).
However, future versions may drop Windows support.

### For MODULE.bazel

See [mboworks/bzl releases](https://github.com/mboworks/bzl/releases) to replace the version number.

```starlark
bazel_dep(name = "mboworks_bzl", version = "0.5.1")
```

### Dependencies

- `bazel_skylib`.
