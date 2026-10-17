# Versions

Load the module's public `versions` struct:

```starlark
load("@mboworks_bzl//bzl/versions:versions.bzl", "versions")
```

The module parses versions, compares precedence, selects release components and evaluates version
requirements. All operations are pure Starlark. Select a mode explicitly when exchanging parsed
versions or requirements between calls.

## API and defaults

| Function                                                                            | Result                                                | Default mode |
| ----------------------------------------------------------------------------------- | ----------------------------------------------------- | ------------ |
| `parse(version, *, skip_build=False, error="Cannot parse version.", mode="legacy")` | Component list or PEP 440 record                      | `legacy`     |
| `cmp(lhs, rhs, *, skip_build=True, mode="legacy")`                                  | `-1`, `0`, or `1`                                     | `legacy`     |
| `eq`, `ne`, `lt`, `le`, `gt`, `ge` with the same arguments as `cmp`                 | Boolean precedence comparison                         | `legacy`     |
| `compare(lhs, op, rhs, *, skip_build=True, error=None, mode="legacy")`              | Boolean requirement-clause result                     | `legacy`     |
| `check_one_requirement(version, requirement, *, skip_build=True, mode="legacy")`    | Boolean; string or parsed clause                      | `legacy`     |
| `check_all_requirements(version, requirements, *, skip_build=True, mode="legacy")`  | Boolean; all clauses must hold                        | `legacy`     |
| `parse_requirements(requirements, *, mode="legacy")`                                | List of parsed clause records                         | `legacy`     |
| `prefix(version, count, *, mode="semver")`                                          | First at most `count` release components, as a string | `semver`     |
| `components(version, *, start=0, end=None, pad=False, mode="semver")`               | Release slice, as a string                            | `semver`     |
| `major`, `minor`, `patch` with `(version, *, mode="semver")`                        | Individual integer component                          | `semver`     |
| `compatible(version, required, *, skip_build=True, mode="semver")`                  | Compatible-release predicate                          | `semver`     |
| `matches(version, pattern, *, skip_build=True, mode="semver")`                      | Exact or trailing-wildcard match                      | `semver`     |

Existing parsing/comparison APIs default to historical behavior; the newer component/matching
helpers default to SemVer mode. `eq`/`ne` mean equality/inequality, `lt`/`le` mean less than/at most,
and `gt`/`ge` mean greater than/at least. `cmp` compares precedence directly. In PEP 440 mode,
`compare` and the requirement APIs instead implement the additional rules of specifier clauses.

An unknown mode fails. `error` supplies the historical unsupported-input diagnostic in legacy
parsing, or the unsupported-comparator diagnostic in `compare`; malformed standards-mode input
uses the relevant parser's diagnostic.

## Mode comparison

| Property                    | `legacy`                             | `semver`                                                | `pep440`                                              |
| --------------------------- | ------------------------------------ | ------------------------------------------------------- | ----------------------------------------------------- |
| Purpose                     | Preserve historical library behavior | SemVer precedence, extended to variable-length releases | Python package version syntax and specifier semantics |
| `1.2` compared with `1.2.0` | Less than                            | Equal                                                   | Equal                                                 |
| `rc1` versus `rc.1`         | Normalized to the same suffix parts  | Distinct identifiers                                    | Normalized to the same RC spelling                    |
| `rc10` versus `rc2`         | Numeric suffix order                 | ASCII lexical order                                     | Numeric RC order                                      |
| Suffix case                 | Case-sensitive                       | Case-sensitive                                          | Normalized to lowercase                               |
| Numeric leading zeros       | Accepted and converted to integers   | Rejected in raw release/prerelease strings              | Accepted and normalized                               |
| Epochs, post/dev releases   | No Python interpretation             | No Python interpretation                                | Supported                                             |
| `+...` in direct comparison | Ignored by default                   | Ignored by default                                      | Local version participates in ordering                |
| Parse result                | Flat list                            | Flat list                                               | Immutable record                                      |

### Legacy

Legacy mode retains the original relaxed parser and comparator. Input may be a string, integer,
list, or tuple. Integers become one-component lists; tuples become lists. Digit-only parts become
integers. Other list components and relaxed string components can remain strings. An empty string
parses as `[]`; unsupported input types fail. Parsing does not pad missing release components.

The historical string parser first separates at most the first two dots and then looks for suffix
delimiters in the remaining part. Consequently, dotted suffixes on short release strings do not
have all the guarantees of three-component strings. Use explicit component lists or SemVer mode
when that distinction matters. Component-slicing helpers strip string suffixes before selecting
release parts.

Prerelease parts are separated at dots. A nonnumeric identifier ending in digits is further split
into its textual prefix and numeric suffix; a single hyphen immediately before the suffix is removed:

```starlark
versions.parse("1.2.3-rc1", mode="legacy")    # [1, 2, 3, "-", "rc", 1]
versions.parse("1.2.3-rc.1", mode="legacy")   # [1, 2, 3, "-", "rc", 1]
versions.parse("1.2.3-rc-1", mode="legacy")   # [1, 2, 3, "-", "rc", 1]
versions.parse("1.2.3-alpha--2", mode="legacy")  # [1, 2, 3, "-", "alpha-", 2]
```

Build identifiers split only at dots. Numeric components compare numerically, numeric identifiers
precede text identifiers, and text compares lexically. Component count breaks ties after equal
available parts, with the historical special handling of prerelease/build delimiters:

```starlark
versions.lt("1.2", "1.2.0", mode="legacy")       # True
versions.eq("1.2.3-rc1", "1.2.3-rc.1", mode="legacy")  # True
versions.lt("1.2.3-rc2", "1.2.3-rc10", mode="legacy")  # True
```

Legacy mode is a compatibility contract, not a SemVer validator or a Python version implementation.
New requirement operators and function expressions can use it, but whole-version lower bounds and
exact comparisons retain its component-count and suffix behavior.

### SemVer

This mode follows [Semantic Versioning 2.0.0](https://semver.org/) precedence and suffix syntax.
As a documented extension to SemVer's exactly three numeric release components, this library
accepts any nonempty number of non-negative numeric release components and pads shorter releases
with zeros for comparison. That padding follows the established
[Python numeric-release convention](https://packaging.python.org/en/latest/specifications/version-specifiers/#final-releases).
The parser retains the written number of release components.

Raw strings have the form `N(.N)*[-IDENT(.IDENT)*][+IDENT(.IDENT)*]`. Identifiers contain only ASCII
letters, digits, and hyphens and are nonempty. Release components and numeric prerelease identifiers
cannot have leading zeros. Build identifiers may have leading zeros. A leading `v`, surrounding
whitespace in a version value, Python epochs, and Python suffix spellings are not normalized.
Whitespace around requirement clauses and their operands is accepted by the requirement parser.

Input may also be an integer or a list/tuple of already parsed parts. Lists use a `"-"` element
before prerelease identifiers and a `"+"` before build identifiers. Numeric strings become integers.
Once an input is pre-parsed, the original spelling of an integer cannot be recovered; leading-zero
validation therefore applies to the raw string spelling.

Precedence compares numeric release components, then prerelease identifiers. A release without a
prerelease suffix follows the same release with one. Numeric prerelease identifiers compare
numerically and precede alphanumeric identifiers. Alphanumeric identifiers compare case-sensitively
in ASCII order; equal shared identifiers are followed by the shorter prerelease sequence first:

```text
1.0.0-alpha < 1.0.0-alpha.1 < 1.0.0-alpha.beta < 1.0.0-beta
            < 1.0.0-beta.2 < 1.0.0-beta.11 < 1.0.0-rc.1 < 1.0.0
```

`rc1` is one alphanumeric identifier; `rc.1` is two identifiers. Thus `rc10 < rc2`, and `rc1` differs
from `rc.1`. Use `rc.10` when numeric RC ordering is intended.

```starlark
versions.eq("1.2", "1.2.0.0", mode="semver")       # True
versions.lt("1.2.3-rc10", "1.2.3-rc2", mode="semver")  # True
versions.parse("1.2.3-rc1+build.7", mode="semver")
# [1, 2, 3, "-", "rc1", "+", "build", 7]
```

`skip_build=True` ignores build metadata for comparison, as SemVer requires. Parsing defaults to
`skip_build=False`; comparison/matching defaults to `True`. `skip_build=False` on a comparison is
an explicit extension: build parts then break ties, using numeric-before-text component ordering.
SemVer mode validates suffix syntax even when metadata is ignored. Numeric identifiers in parsed
lists are integers, so parsing preserves semantics and component count rather than every original
character of metadata spelling.

### Python PEP 440

This mode implements the [PyPA version scheme and version specifiers](https://packaging.python.org/en/latest/specifications/version-specifiers/).
The public version form is `[E!]N(.N)*[{a|b|rc}N][.postN][.devN]`, optionally followed by `+LOCAL`.
The epoch defaults to zero and is compared before release numbers; higher epochs sort later.
Releases compare with numeric zero padding while retaining their original component count in the
parsed value.

Parsing supports the specified normalizations:

- surrounding whitespace and an optional leading `v` are removed;
- letters are lowercased and numeric leading zeros are removed;
- `alpha` becomes `a`, `beta` becomes `b`, and `c`, `pre`, and `preview` become `rc`;
- optional `.`, `-`, and `_` separators around suffix labels/numbers are normalized;
- missing pre/post/dev numbers become zero;
- `rev` and `r` post labels and the `-N` postrelease spelling become `.postN`;
- local labels split at `.`, `-`, or `_`, normalize to dots/lowercase, and convert numeric parts
  to integers.

```starlark
v = versions.parse(" V01.002.000RC_03 ", mode="pep440")
v.normalized  # "1.2.0rc3"
versions.eq("1.2-rc1", "1.2rc.1", mode="pep440")  # True
versions.lt("1.2rc2", "1.2rc10", mode="pep440")   # True
versions.gt("1!1.0", "999.0", mode="pep440")      # True
```

`parse` returns a record with these fields:

| Field        | Value                                                                |
| ------------ | -------------------------------------------------------------------- |
| `scheme`     | `"pep440"`                                                           |
| `epoch`      | Non-negative integer, default `0`                                    |
| `release`    | Tuple of integer release components                                  |
| `pre`        | `("a", n)`, `("b", n)`, `("rc", n)`, or `None`                       |
| `post`       | Integer postrelease number or `None`                                 |
| `dev`        | Integer development-release number or `None`                         |
| `local`      | Tuple of normalized integer/string local components; empty if absent |
| `normalized` | Canonical string, preserving release component count                 |

Version strings, integers, and these parsed records are accepted. Lists/tuples are joined with dots
before Python parsing; legacy/SemVer suffix-token lists are not reinterpreted as Python records.

Within a release, development releases precede prereleases; phases order `a < b < rc`; final
releases follow prereleases, and postreleases follow their corresponding release. Dev/pre/post
combinations retain the PEP 440 ordering. For the same public version, absence of a local label
precedes its presence. Local numeric components sort after lexical components; lexical components
compare case-insensitively after normalization, and a longer equal-prefix local label sorts later.
`skip_build` has no effect in PEP 440 mode: local versions have Python semantics rather than SemVer
metadata semantics.

Precedence helpers and requirement clauses intentionally differ:

| Call                                              | Result  | Reason                                                    |
| ------------------------------------------------- | ------- | --------------------------------------------------------- |
| `gt("1.0.post1", "1.0", mode="pep440")`           | `True`  | Direct version precedence                                 |
| `compare("1.0.post1", ">", "1.0", mode="pep440")` | `False` | `>V` excludes postreleases of V unless V is a postrelease |
| `lt("1.0rc1", "1.0", mode="pep440")`              | `True`  | Prerelease precedes final release                         |
| `compare("1.0rc1", "<", "1.0", mode="pep440")`    | `False` | `<V` excludes prereleases of V unless V is a prerelease   |
| `eq("1.0+local", "1.0", mode="pep440")`           | `False` | Direct comparison includes locals                         |
| `matches("1.0+local", "1.0", mode="pep440")`      | `True`  | A public equality requirement ignores candidate locals    |

`>=`/`<=` use public-version precedence. Equality requirements include local labels only when the
requirement supplies one. Ordered and compatible-release requirements cannot contain local labels.
`>V` also excludes local versions of the same base release. `===` compares the normalized candidate
spelling case-insensitively with the operand; it also accepts arbitrary otherwise-invalid candidate
strings as an escape hatch.

These are version predicates, not package resolution: they do not implement package names, URLs,
markers, installed-version exceptions, stable preference or candidate-set prerelease fallback.
Predicates evaluate candidates with prereleases admitted; PEP 440's operator-specific exclusions
still apply. Callers choose which candidates to consider.

## Selecting release components

`major`, `minor`, and `patch` return integer components at indices 0, 1, and 2. Missing minor or
patch components are zero. They exclude prerelease/build/local suffixes and, in Python mode, epochs.
The version must have a nonempty numeric release. Ordinary Starlark calls require the version:

```starlark
versions.major("23.2.1")  # 23
versions.minor("23.2.1")  # 2
versions.patch("23.2")    # 0
```

`prefix` and `components` return dot-separated strings. `prefix(v, n)` is
`components(v, end=n)` and never pads; `n` must be a non-negative integer. The slice start is
inclusive and end exclusive. Negative indices resolve against the original release length.
`end=None` uses the original length. An explicit positive end with `pad=True` extends the release
with zeros before slicing. Empty selections return `""`.

```starlark
versions.prefix("1.2.3.4", 2)                      # "1.2"
versions.prefix("1.2", 4)                          # "1.2"
versions.components("1.2.3.4", end=2)              # "1.2"
versions.components("1.2.3.4", start=1, end=3)     # "2.3"
versions.components("1.2", end=4)                  # "1.2"
versions.components("1.2", end=4, pad=True)        # "1.2.0.0"
versions.components("1.2.3", start=1, end=4, pad=True)  # "2.3.0"
versions.components("1.2", start=-1, end=4, pad=True)   # "2.0.0"
```

The legacy/SemVer `prefix`/`components` helpers retain permissive historical release slicing;
they do not validate SemVer syntax, including numeric leading zeros or suffixes. For example,
`prefix("01.2", 2, mode="semver")` returns `"1.2"`. Use `parse(..., mode="semver")` first when
validation is required. The integer `major`/`minor`/`patch` helpers do use the selected full parser.
Python mode also parses a full Python version before slicing. Padding is always opt-in.

## Compatible and matching requirements

`compatible(candidate, required)` implements `~=required`: the candidate must meet the lower bound
and share all but the final written numeric release component of the requirement. At least two
components are required. Suffixes affect the lower bound but not the prefix:

| Requirement | Stable-release range |
| ----------- | -------------------- |
| `~=1.4`     | `>=1.4, <2.0`        |
| `~=1.4.5`   | `>=1.4.5, <1.5.0`    |
| `~=1.4.5.0` | `>=1.4.5.0, <1.4.6`  |

The prefix excludes prereleases of the next series, even when their precedence is below that
series' final release. Preserve trailing zeros in requirements; padding them first changes the
compatibility boundary.

`matches(candidate, pattern)` accepts an exact version or one trailing `.*` after a nonempty
numeric release prefix. Exact matching uses the selected mode's equality rules; PEP 440 additionally
applies its local-label rule. Wildcards compare whole numeric components and zero-pad a shorter
candidate, ignoring remaining components and suffixes. Python wildcard prefixes can include epochs.
Bare `*`, interior/partial/multiple wildcards and suffix wildcards fail.

```starlark
versions.compatible("1.4.5", "1.4.0")  # True
versions.compatible("1.5.0", "1.4.0")  # False
versions.compatible("1.9.0", "1.4")    # True
versions.matches("1.2.3", "1.2.*")    # True
versions.matches("1.20.3", "1.2.*")   # False
versions.matches("1", "1.0.*")        # True
```

Requirement tokens are strings interpreted by the library, not overloaded Starlark operators:

| Operator             | Meaning                                                | Example        |
| -------------------- | ------------------------------------------------------ | -------------- |
| `==`, `!=`           | Exact or trailing-prefix match/exclusion               | `==1.2.*`      |
| `<`, `<=`, `>`, `>=` | Ordering; PEP 440 uses clause-specific rules           | `>=1.2,<2`     |
| `~=`                 | Compatible release                                     | `~=1.2`        |
| `!~=`                | Logical complement of compatible release               | `!~=1.2`       |
| `~~=`                | Prefix match plus a lower bound at the explicit prefix | `~~=1.2.*`     |
| `!~~=`               | Logical complement of extended compatibility           | `!~~=1.2.*`    |
| `===`                | Python arbitrary equality; PEP 440 mode only           | `===1.2+local` |

The negated/extended compatible operators are library extensions to Python syntax. `~~=1.2.*`
combines `>=1.2` with the `1.2` prefix. In SemVer/Python modes it excludes `1.2-rc1`/`1.2rc1`, but
can match `1.2.1-rc1`/`1.2.1rc1`. `==1.2.*` has no such lower bound. Negations complement the
positive predicate but still fail on malformed input. Extended compatibility requires `.*`;
compatible and ordered operands cannot use wildcards.

## Requirement function expressions

Requirement clauses can use `major`, `minor`, `patch`, `prefix` and `components` as function calls on
the left side. Omit the version to use the candidate. Calls require parentheses. Bare identifiers
are reserved for future customizable constants and currently fail:

```starlark
versions.check_all_requirements("23.2.1", "major()==23,minor()>=2", mode="semver")  # True
versions.check_one_requirement("23.2.1", "prefix(2)==23.2", mode="semver")  # True
versions.check_one_requirement("23.2.1", "components(start=1,end=3)==2.1", mode="semver")  # True
versions.check_one_requirement("23.2.1", "major(prefix(2))==23", mode="semver")  # True
```

`major()==23,minor()>=2` compares the individual major and minor integers, not a release prefix.
Zero-argument component calls use one non-negative integer operand with `==`, `!=`, `<`,
`<=`, `>`, or `>=`. A missing minor/patch component is zero. Use `prefix` or `components` for a
multi-component version value and compatible-release/prefix operations.

`prefix(2)` supplies the candidate as the omitted first argument; `prefix(count=2)` is equivalent.
Use `prefix("24.3.2", 2)` or `prefix(version="24.3.2", count=2)` for an explicit version.
`components()` selects the candidate's complete release; `components("24.3.2", start=1, end=3)`
uses an explicit version. `major("24.3.2")` and the corresponding minor/patch calls are also allowed.

Arguments can be integer/string/boolean/`None` literals, keyword arguments, and nested calls to these
five functions. Version strings can use either quote style and ordinary quote/backslash or newline,
carriage-return and tab escapes. Positional arguments precede keyword arguments. `mode` is inherited
from the requirement check and cannot be overridden inside an expression. Arbitrary Starlark code,
variables, attribute access, arithmetic and other functions are outside this grammar.

Comma-separated clauses are ANDed. Commas inside calls or quoted literals do not split clauses.
Whitespace around clauses, names, operators and arguments is accepted. A plain version without a
comparator means `==`; function expressions require an explicit comparator. A single `=` is not an
equality comparator.

## Parsed requirements and failures

`check_all_requirements` accepts a comma-separated string or a list of strings/parsed records.
`check_one_requirement` accepts one string or one record. `parse_requirements` returns records with
`op` and `version`; zero-argument component-call records also carry `component`, and other function clauses carry
an opaque `expression` description. Legacy/SemVer plain operands are parsed component lists, whereas
Python plain operands retain strings for wildcard/arbitrary equality. Keep the same mode when
parsing and checking; treating a normalized legacy suffix list as SemVer cannot restore its spelling.

Invalid modes, malformed standards-mode versions, unsupported comparators, malformed wildcard
shapes, invalid component indices/counts, and invalid function expressions fail. Some argument/arity
and Python operand restrictions are checked during evaluation because they depend on the selected
function or clause. A negated requirement does not suppress those failures.

## Reference validation

The tests retain the historical assertions, cover the full published SemVer precedence example,
and compare Python parsing/ordering/clauses with fixtures generated by `packaging==26.0`.
That Python dependency is for fixture generation only; Starlark consumers have no Python dependency.

```sh
python3 -m pip install -r tools/requirements-pep440.txt
python3 tools/generate_pep440_cases.py
python3 tools/generate_pep440_cases.py --check
```
