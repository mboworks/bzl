# MBO Works bzl, a Bazel support library <img src="docs/assets/mboworks-logo.png" alt="MBO Works" width="64" height="64" align="right">

[Release website](https://mboworks.github.io/bzl/) · [Infrastructure and publishing](docs/infrastructure.md)

This library provides [Bazel](http://bazel.build) [Starlark](https://bazel.build/rules/language) functionality meant to help in maintaining other libraries.

[![Test](https://github.com/mboworks/bzl/actions/workflows/main.yml/badge.svg)](https://github.com/mboworks/bzl/actions/workflows/main.yml)

The following libraries are implemented:

- [Versions](#versions)
- [Paths](#paths)

## Versions

[`bzl/versions`](docs/versions.md) provides version parsing, precedence comparisons, release-component
selection, compatible-release checks and wildcard matching. Requirement strings support ANDed
clauses and version-function expressions.

```starlark
load("@mboworks_bzl//bzl/versions:versions.bzl", "versions")

versions.major("23.2.1")                               # 23
versions.prefix("23.2.1", 2)                           # "23.2"
versions.components("23.2", end=4, pad=True)           # "23.2.0.0"
versions.compatible("1.4.8", "1.4.5")                  # True
versions.matches("1.2.3", "1.2.*")                     # True
versions.check_all_requirements("23.2.1", "major()==23,minor()>=2", mode="semver")  # True
versions.check_one_requirement("23.2.1", "prefix(2)==23.2", mode="semver")      # True
```

| Mode     | Behavior                                                                                                       |
| -------- | -------------------------------------------------------------------------------------------------------------- |
| `legacy` | Historical parsing and comparisons: `1.2 < 1.2.0`; `rc1` and `rc.1` normalize alike                            |
| `semver` | SemVer suffix precedence with variable-length, zero-padded releases: `1.2 == 1.2.0`; `rc1` differs from `rc.1` |
| `pep440` | Python version normalization and specifiers, including epochs, pre/post/dev releases and local labels          |

Existing parsing/comparison APIs default to `legacy`; component helpers, `compatible` and `matches`
default to `semver`. Pass a mode explicitly when sharing parsed values or requirements. In Python
mode, direct version precedence and requirement clauses have different rules: `1.0.post1` sorts
after `1.0`, but does not satisfy `>1.0`.

Requirements use `<`, `<=`, `>`, `>=`, `==`, `!=`, `~=` and the library's `!~=`, `~~=`, `!~~=`
extensions. `~=1.2` permits compatible 1.x releases from 1.2; `~~=1.2.*` selects the 1.2 prefix with
a lower bound at 1.2. `==1.2.*` is prefix matching without that extra lower bound. Function calls require parentheses. Bare identifiers read a caller-supplied `constants` dictionary;
`major==23` works when that dictionary binds `major`, while `major()==23` always calls the library
helper. Functions accept an implied candidate, such as `components(start=1,end=3)==2.1`.

```starlark
candidate = "23.2.1"
versions.check_all_requirements(
    candidate,
    "major==23,minor>=2",
    constants={"major": versions.major(candidate), "minor": versions.minor(candidate)},
    mode="semver",
)  # True
```

Bindings also work inside calls, such as `prefix(width)`. Parsing retains references; callers can
reuse parsed requirements and supply fresh bindings for each candidate. Unknown names fail when
checked, and a constant never replaces a callable function.

The [versions reference](docs/versions.md) documents every API, all three modes, parsing/normalization,
metadata, compatible-release precision, function arguments, errors and prerelease behavior. The
modes use [SemVer](https://semver.org/) and the
[Python version specification](https://packaging.python.org/en/latest/specifications/version-specifiers/)
with the documented differences and extensions.

## Paths

[`bzl/paths`](docs/paths.md) provides lexical normalization, parent collapse, joining, absolute-path
tests and trailing-separator helpers. Choose Unix defaults or `_windows` variants explicitly;
results do not depend on the Bazel host.

```starlark
load("@mboworks_bzl//bzl/paths:paths.bzl", "paths")

paths.normalize("a/./b/../c")                 # "a/b/../c"
paths.normalize("a/./b/../c", collapse=True)  # "a/c"
paths.join("a/b", "/c")                      # "a/b/c"
paths.join_respect_absolute("a/b", "/c")     # "/c"
paths.normalize_windows("C:/a//b")            # "C:\\a\\b"
paths.ensure_trailing_slash("a//b/")          # "a/b/"
```

`normalize` removes redundant separators and `.` but preserves `..` unless collapse is requested.
`join` keeps earlier components; `join_respect_absolute` resets at the last absolute part. Windows
mode treats `C:foo` as `C:\foo`, so Windows drive-relative semantics are unsupported. These
functions manipulate strings and do not resolve symlinks or inspect the filesystem.

The [paths reference](docs/paths.md) documents all generic and Windows APIs, root/UNC handling,
empty values, joining rules, collapse behavior and trailing-separator fallbacks.

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
