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
`mode = "semver"`. The default preserves their historical behavior. Select a mode explicitly when
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
    - `major(version, *, mode = "semver")`, `minor(...)`, `patch(...)`: Individual integer release components.
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
These two modes are not a full Python package version parser: Python epochs, `dev`/`post` suffixes and Python
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
`parse_requirements`) support compatible release `~=`, its negation `!~=`, extended compatible
release `~~=`, its negation `!~~=`, exact/prefix matching `==` and exclusion `!=`, and ordering
`<`, `<=`, `>`, `>=`. Their default remains legacy precedence; pass `mode = "semver"` for the
zero-padded, identifier-preserving semantics described above. A missing operator means `==`. Comma-separated clauses are ANDed, and whitespace
around clauses and operands is accepted. These are operators in strings, not overloaded Starlark
operators:

| Operator | Meaning                                             | Example     | Stable-release equivalent           |
| -------- | --------------------------------------------------- | ----------- | ----------------------------------- |
| `~=`     | PEP 440 compatible release boundary                 | `~=1.2`     | `>=1.2, <2.0`                       |
| `!~=`    | Logical negation of `~=`                            | `!~=1.2`    | Outside the compatible set          |
| `~~=`    | Extended compatible release with an explicit prefix | `~~=1.2.*`  | `>=1.2, <1.3`                       |
| `!~~=`   | Logical negation of `~~=`                           | `!~~=1.2.*` | Outside the extended compatible set |

`~~=` and the negated operators are library extensions, not PEP 440 operators. `~~=` requires a
numeric release prefix followed by a single trailing `.*`. It combines a lower bound at the written
prefix with whole-component prefix matching. Its prefix keeps prereleases of the next series out,
just as `~=` does. The range column describes stable releases; prefix boundaries are also enforced
for prereleases.

In SemVer mode, unlike `==1.2.*`, `~~=1.2.*` excludes `1.2-rc.1` and `1.2.0-rc.1` because they precede the `1.2`
lower bound. It can still match `1.2.1-rc.1`; collection-level prerelease admission remains the
caller's policy. Negated operators return the exact logical complement of their positive form,
without negating malformed-input errors. `versions.compatible()` and `versions.matches()` retain
their separate meanings; the extended operator adds a lower bound to prefix matching.

Wildcards with ordering operators, `~=`, or `!~=` fail. Exact operands with `~~=` or `!~~=` fail.
Operators are recognized longest first so `!~~=` is never mistaken for one of its shorter tokens.

```starlark
versions.compare("1.4.8", "~=", "1.4.5", mode = "semver")  # True
versions.compare("2.0", "!~=", "1.2", mode = "semver")     # True
versions.compare("1.2.9", "~~=", "1.2.*", mode = "semver")  # True
versions.compare("1.3", "!~~=", "1.2.*", mode = "semver")   # True
versions.check_one_requirement("1.2.3", "==1.2.*", mode = "semver")  # True
versions.check_all_requirements("1.4.8", "~=1.4.5,!=1.4.7", mode = "semver")  # True
requirements = versions.parse_requirements("==1.2.*,!=1.2.4", mode = "semver")
versions.check_all_requirements("1.2.3", requirements, mode = "semver")  # True
```

### Named release components

Requirement clauses can compare individual numeric release components directly:

```starlark
versions.check_all_requirements("23.2.1", "major()==23,minor()>=2", mode = "semver")  # True
versions.check_one_requirement("23.1.9", "minor()>=2", mode = "semver")  # False
versions.check_one_requirement("23.2.1.9", "patch()==1", mode = "semver")  # True
```

`major()`, `minor()`, and `patch()` select indices 0, 1, and 2, respectively. Missing minor or
patch components are zero. Their zero-argument clauses require a single non-negative integer and
one of `==`, `!=`, `<`, `<=`, `>`, `>=`. Function-call syntax is required: bare identifiers are
reserved for future customizable constants and currently fail. Wildcards, suffixes, multi-part
operands and compatible-release operators are invalid for zero-argument component clauses.

`parse_requirements` adds `component = "major"`, `"minor"`, or `"patch"` to zero-argument component-call records;
plain records keep their existing `op`/`version` shape. Both string and parsed requirement checks
support the calls, under either comparison mode. Function expressions are library extensions to Python's
specifier syntax and can be passed through by a selector such as `latest:major()==23,minor()>=2`.

### Version-function expressions

The ordinary Starlark helpers `versions.major(version)`, `minor(version)`, and `patch(version)`
return integer components; missing minor/patch components are zero. Requirement clauses support
calls to `major`, `minor`, `patch`, `prefix`, and `components` with an implied candidate when the
version is omitted. Calls require parentheses; bare identifiers remain reserved for future constants.

```starlark
versions.major("23.2.1")  # 23
versions.check_all_requirements("23.2.1", "major()==23,minor()>=2", mode = "semver")  # True
versions.check_one_requirement("23.2.1", "prefix(2)==23.2", mode = "semver")  # True
versions.check_one_requirement("23.2.1", "components(start=1,end=3)==2.1", mode = "semver")  # True
versions.check_one_requirement("23.2.1", "major(prefix(2))==23", mode = "semver")  # True
```

`prefix(2)` and `prefix(count=2)` use the candidate. Explicit versions use forms such as
`prefix("24.3.2", 2)` or `components("24.3.2", start=1, end=3)`. Arguments can be integer,
quoted-string, boolean and `None` literals, keyword arguments, or nested calls to these five
functions. Positional arguments precede keywords. The expression inherits the requirement mode;
`mode` cannot be overridden inside it. Variables, arithmetic, attributes and arbitrary Starlark
code are outside this grammar. Top-level commas combine clauses; commas inside calls or quoted
literals remain part of the expression.

Parsed function clauses carry an opaque `expression` description; bare and zero-argument component
calls use the same `component` record. Pass parsed records through to requirement checks with the
same mode, rather than interpreting their function metadata independently.

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
