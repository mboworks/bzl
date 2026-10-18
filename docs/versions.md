# Versions

Load the module's public `versions` struct:

```starlark
load("@mboworks_bzl//bzl/versions:versions.bzl", "versions")
```

The module parses versions, compares precedence, selects release components and evaluates version
requirements. All operations are pure Starlark. Select a mode explicitly when exchanging parsed
versions or requirements between calls.

## API and defaults

| Function                                                                                           | Result                                                | Default mode |
| -------------------------------------------------------------------------------------------------- | ----------------------------------------------------- | ------------ |
| `with_mode(mode)`                                                                                  | Immutable API object with one default mode            | Explicit     |
| `parse(version, *, skip_build=False, error="Cannot parse version.", mode="legacy")`                | Component list or PEP 440 record                      | `legacy`     |
| `cmp(lhs, rhs, *, skip_build=True, mode="legacy")`                                                 | `-1`, `0`, or `1`                                     | `legacy`     |
| `eq`, `ne`, `lt`, `le`, `gt`, `ge` with the same arguments as `cmp`                                | Boolean precedence comparison                         | `legacy`     |
| `compare(lhs, op, rhs, *, skip_build=True, error=None, mode="legacy")`                             | Boolean requirement-clause result                     | `legacy`     |
| `check_one_requirement(version, requirement, *, skip_build=True, constants=None, mode="legacy")`   | Boolean; string or parsed clause                      | `legacy`     |
| `check_all_requirements(version, requirements, *, skip_build=True, constants=None, mode="legacy")` | Boolean; all clauses must hold                        | `legacy`     |
| `parse_requirements(requirements, *, mode="legacy")`                                               | List of parsed clause records                         | `legacy`     |
| `prefix(version, count, *, mode="semver")`                                                         | First at most `count` release components, as a string | `semver`     |
| `components(version, *, start=0, end=None, pad=False, mode="semver")`                              | Release slice, as a string                            | `semver`     |
| `major`, `minor`, `patch` with `(version, *, mode="semver")`                                       | Individual integer component                          | `semver`     |
| `component_count(version, *, mode="semver")`                                                       | Number of explicitly written release components       | `semver`     |
| `component(version, index, *, mode="semver")`                                                      | Integer at an index, or zero if missing               | `semver`     |
| `prerelease(version, *, mode="semver")`                                                            | Prerelease label, or empty string                     | `semver`     |
| `is_prerelease(version, *, mode="semver")`                                                         | Prerelease/development predicate                      | `semver`     |
| `has_prerelease_prefix(version, prefix, *, mode="semver")`                                         | Textual prefix of first prerelease identifier         | `semver`     |
| `build(version, *, mode="semver")`                                                                 | SemVer/legacy build metadata                          | `semver`     |
| `local(version, *, mode="pep440")`                                                                 | Normalized Python local label                         | `pep440`     |
| `compatible(version, required, *, skip_build=True, mode="semver")`                                 | Compatible-release predicate                          | `semver`     |
| `matches(version, pattern, *, skip_build=True, mode="semver")`                                     | Exact or trailing-wildcard match                      | `semver`     |

Existing parsing/comparison APIs default to historical behavior; the newer component/matching
helpers default to SemVer mode, except Python-only `local`, which defaults to PEP 440.
`eq`/`ne` mean equality/inequality, `lt`/`le` mean less than/at most,
and `gt`/`ge` mean greater than/at least. `cmp` compares precedence directly. In PEP 440 mode,
`compare` and the requirement APIs instead implement the additional rules of specifier clauses.

An unknown mode fails. `error` supplies the historical unsupported-input diagnostic in legacy
parsing, or the unsupported-comparator diagnostic in `compare`; malformed standards-mode input
uses the relevant parser's diagnostic.

### Consistent defaults with `with_mode`

Create a mode-bound API object when a client consistently uses one scheme:

```starlark
semver = versions.with_mode("semver")
python = versions.with_mode("pep440")

semver.eq("1.2", "1.2.0")                           # True
semver.prerelease("1.2.3-rc1")                       # "rc1"
semver.check_one_requirement("1.2.3-rc1", 'prerelease()=="rc1"')  # True
python.is_prerelease("1.2.post1.dev2")               # True
python.local("1.2+Ubuntu-01")                       # "ubuntu.1"
```

The returned immutable Starlark struct exposes the same functions as `versions`, including
`with_mode`. Each wrapper supplies the selected mode only when the call omits it. All other
arguments, return values and errors come from the original function. In particular keyword-only
options such as `constants`, `skip_build`, slicing/padding, and diagnostics still work.

An explicit per-call mode takes precedence: `semver.eq("1.2", "1.2.0", mode="legacy")` is false.
This does not change the object or subsequent calls. `semver.with_mode("legacy")` creates another
independent API. The original `versions` defaults remain unchanged; no global or ambient state is
used. Unknown modes fail when the API is created or when an explicit override is evaluated.

The bound mode applies to **every** method, even one with a different standalone default:
`semver.local("1.2+abc")` fails because local labels require Python mode. Use the Python API or an
explicit per-call override. Requirement checks forward their effective mode to every nested
expression call. Expression syntax continues to inherit that mode rather than accepting its own
`mode` keyword. Keep parsing and evaluation on the same API/mode when reusing parsed requirements.

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

## Version introspection

`component_count` counts the numeric release components actually supplied, excluding every suffix
and the PEP 440 epoch. It does not count comparison padding. `component` accepts an integer index;
negative indices count from the original release's end. An out-of-range index returns zero in
either direction. These helpers parse the complete version in the selected mode and require a
non-empty numeric release, including in legacy mode.

```starlark
versions.component_count("1.2.0.0-rc.1")  # 4
versions.component("1.2.3.4", -1)        # 4
versions.component("1.2", 3)             # 0
versions.component_count("1!1.2rc1", mode="pep440")  # 2
```

`prerelease` returns the label without its leading delimiter. SemVer preserves the identifier
spelling and boundaries (`rc1` and `rc.1` differ); legacy returns its historical normalized
identifiers (`rc1` becomes `rc.1`). PEP 440 returns the normalized pre segment, such as `a0`, `b2`,
or `rc1`, excluding post/dev/local segments. A version without a pre segment returns `""`.

`is_prerelease` is true for any SemVer/legacy prerelease segment. In PEP 440 it follows
[Python's `Version.is_prerelease`](https://packaging.pypa.io/en/stable/version.html#packaging.version.Version.is_prerelease):
a pre **or development** segment makes it true, including a development release of a postrelease.
A postrelease alone and a local label alone do not. Consequently a Python development-only
version can have `is_prerelease()==True` while `prerelease()==""`.

`has_prerelease_prefix` tests a case-sensitive textual prefix of the first prerelease identifier,
without interpreting phases: both `rc1` and `rc.1` match `"rc"`, but `"rc."` does not match the first
identifier of `rc.1`. Normalization happens before matching in legacy/Python modes. An empty prefix
matches any non-empty pre segment; it never matches a final or development-only Python release.
No helper changes a resolver's separate prerelease-admission policy.

```starlark
versions.prerelease("1.2.3-rc.4")                    # "rc.4"
versions.has_prerelease_prefix("1.2.3-rc1", "rc")     # True
versions.is_prerelease("1.2.post1.dev2", mode="pep440")  # True
versions.prerelease("1.2.post1.dev2", mode="pep440")  # ""
```

`build` returns the metadata after `+`, or `""` when absent. SemVer string inputs retain the exact
metadata spelling, including case and leading zeros (`+001.X-y` gives `"001.X-y"`), after validating
the complete version. Legacy input uses historical normalization, including numeric conversion.
Parsed lists/tuples have already lost numeric spelling, so those inputs return their normalized
identifiers. `build` rejects Python mode: Python local labels participate in precedence, whereas
SemVer metadata does not.

`local` accepts Python mode only, defaults to that mode, and returns the normalized local label:
lowercase text, dot-separated identifiers and normalized numeric components. It returns `""`
when absent. Neither helper includes `+` in its result.

```starlark
versions.build("1.2.3+001.X-y")           # "001.X-y"
versions.local("1.2+Ubuntu-01_FOO")       # "ubuntu.1.foo"
```

## Requirement expressions and constants

Requirement clauses can use the release-selection and introspection helpers as function calls on
the left side. Omit the version to use the candidate. Calls require parentheses. Bare identifiers
refer to caller-supplied constants, described below:

```starlark
versions.check_all_requirements("23.2.1", "major()==23,minor()>=2", mode="semver")  # True
versions.check_one_requirement("23.2.1", "prefix(2)==23.2", mode="semver")  # True
versions.check_one_requirement("23.2.1", "components(start=1,end=3)==2.1", mode="semver")  # True
versions.check_one_requirement("23.2.1", "major(prefix(2))==23", mode="semver")  # True
versions.check_one_requirement("23.2.1-rc1", "is_prerelease()==True", mode="semver")  # True
versions.check_one_requirement("23.2.1-rc1", 'prerelease()=="rc1"', mode="semver")  # True
versions.check_one_requirement("23.2.1-rc1", 'has_prerelease_prefix("rc")==True', mode="semver")  # True
```

`major()==23,minor()>=2` compares the individual major and minor integers, not a release prefix.
Zero-argument component calls use one non-negative integer operand with `==`, `!=`, `<`,
`<=`, `>`, or `>=`. A missing minor/patch component is zero. Use `prefix` or `components` for a
multi-component version value and compatible-release/prefix operations.

`prefix(2)` supplies the candidate as the omitted first argument; `prefix(count=2)` is equivalent.
Use `prefix("24.3.2", 2)` or `prefix(version="24.3.2", count=2)` for an explicit version.
`components()` selects the candidate's complete release; `components("24.3.2", start=1, end=3)`
uses an explicit version. `major("24.3.2")` and the corresponding minor/patch calls are also allowed.

`component(3)` and `component(index=3)` use the candidate; pass a version and index explicitly to
inspect another version. The same convention applies to `has_prerelease_prefix("rc")` or
`has_prerelease_prefix(prefix="rc")`. `component_count`, `prerelease`, `is_prerelease`, `build`, and
`local` take no positional arguments when inspecting the candidate.

The new integer introspection results require non-negative integer operands and ordered/exact
comparators. Boolean results require literal `True`/`False` with `==`/`!=`; metadata/prerelease text
requires a quoted string with `==`/`!=`. These comparisons use the returned value directly, without
version normalization or SemVer's metadata-ignoring equality. For example, `build()=="001"` tests the
exact metadata text. Existing release-valued helpers retain their version comparison semantics.
Bare predicate calls without a comparator are not supported.
Quoted-text operand handling applies only to actual calls, including `prerelease ()` with
whitespace before the parentheses. A constant named `prerelease`, `build`, or `local` keeps the
ordinary version-operand grammar; sharing a function name does not change its interpretation.

Arguments can be integer/string/boolean/`None` literals, constant references, keyword arguments,
and nested calls to these helpers. Version strings can use either quote style and ordinary quote/backslash or newline,
carriage-return and tab escapes. Positional arguments precede keyword arguments. `mode` is inherited
from the requirement check and cannot be overridden inside an expression. This applies at every
nesting level and takes precedence over a helper's standalone default. In particular `local()`
inside a SemVer expression fails rather than silently switching to Python parsing. Pass
`mode="pep440"` to the checker when using Python-only helpers. Arbitrary Starlark code,
attribute access, arithmetic and other functions are outside this grammar.

Comma-separated clauses are ANDed. Commas inside calls or quoted literals do not split clauses.
Whitespace around clauses, names, operators and arguments is accepted. A plain version without a
comparator means `==`; function expressions require an explicit comparator. A single `=` is not an
equality comparator.

### Caller-supplied constants

`check_one_requirement` and `check_all_requirements` accept a keyword-only `constants` dictionary,
defaulting to `None` (no bindings). A bare identifier on the left side, or inside a function's
arguments, looks up that name in the dictionary. The right side retains the existing version-operand
grammar; constant substitution does not rewrite version literals or arbitrary-equality operands.

```starlark
candidate = "23.2.1"
constants = {
    "major": versions.major(candidate),
    "minor": versions.minor(candidate),
    "patch": versions.patch(candidate),
    "width": 2,
}
versions.check_all_requirements(
    candidate,
    "major==23,minor>=2,prefix(width)==23.2",
    constants=constants,
    mode="semver",
)  # True
```

Names are case-sensitive ASCII identifiers matching `[A-Za-z_][A-Za-z0-9_]*`; `True`, `False`, and
`None` remain literals and cannot be dictionary keys. The library supplies no implicit constants.
Calls always use the library's function namespace: a `major` binding does not change `major()`.
For example, with candidate `"23.2.1"` and `constants={"major": 99}`, `major==99,major()==23` holds.
A dictionary key does not introduce a callable function.

Values are passed to the surrounding version comparison or function and must be valid for that
context. Integer/string/list/tuple versions, or Python-mode parsed records, can serve as comparison
values; booleans and `None` can serve as helper arguments, such as `components(end=stop,pad=padding)`.
Quoted strings remain literal. Values are never evaluated as source code or invoked as callbacks.
Comparison uses the selected mode regardless of the constant's name: integer `23` equals `23.0`
in SemVer/Python modes but precedes it in legacy mode.

Parsing stores unresolved references without capturing a dictionary. Supply bindings when checking
both string and pre-parsed requirements; a missing name fails at evaluation. Reuse parsed clauses
across candidates and construct a fresh dictionary for each candidate when values depend on its
version. The library neither recomputes values nor mutates the supplied dictionary.

## Filtering, sorting and picking versions

Collection operations preserve your original items, including their version spelling and associated
metadata. They accept a list or tuple and never mutate it. Pass dictionary `keys()`, `values()` or
`items()` explicitly to say what should be returned. Collection operations default to `semver`;
`versions.with_mode(...)` changes that default, and an explicit `mode` overrides it.

| Operation         | Result                                                  | Optional keyword arguments                                                                       |
| :---------------- | :------------------------------------------------------ | :----------------------------------------------------------------------------------------------- |
| `sorted(items)`   | New list in stable version order                        | `key`, `reverse=False`, `skip_build=True`, `mode`                                                |
| `filter(items)`   | New list of matching items in input order               | `key`, `include_requirements`, `exclude_requirements`, `mode`                                    |
| `earliest(items)` | First item in a stable ascending sort of matching items | `key`, `include_requirements`, `exclude_requirements`, `default=None`, `skip_build=True`, `mode` |
| `latest(items)`   | Last item in a stable ascending sort of matching items  | `key`, `include_requirements`, `exclude_requirements`, `default=None`, `skip_build=True`, `mode` |

`key=None` treats each item as its version. Otherwise `key(item)` extracts the version **once per
item per operation**. Predicates receive this extracted value, not the surrounding record and not
an automatically normalized replacement. The original item is returned.

### Plain versions and ordering modes

```starlark
semver = versions.with_mode("semver")

semver.sorted(["2.0", "1.10", "1.2"])                 # ["1.2", "1.10", "2.0"]
semver.sorted(["2.0", "1.10", "1.2"], reverse=True)   # ["2.0", "1.10", "1.2"]
semver.earliest(["2.0", "1.10", "1.2"])               # "1.2"
semver.latest(["2.0", "1.10", "1.2"])                 # "2.0"
```

Equal-precedence items retain input order even with `reverse=True`. In SemVer mode, `"1.2"` and
`"1.2.0"` compare equally, and build metadata is ignored by default. Nothing is deduplicated:

```starlark
same = ["1.2.0+001", "1.2", "1.2+1"]
semver.sorted(same)                  # All three, in their original order.
semver.sorted(same, reverse=True)    # Still in their original order.
semver.earliest(same)                # "1.2.0+001": first tie.
semver.latest(same)                  # "1.2+1": last tie.
```

Use `skip_build=False` to apply the existing SemVer/legacy build-metadata tie breaker. PEP 440
ordering always includes local labels, as with `cmp`; `skip_build` does not change that behavior.
The other modes use their existing precedence rules:

```starlark
python = versions.with_mode("pep440")
python.sorted(["1.0", "1.0rc10", "1.0rc2", "1.0.dev1"])
# ["1.0.dev1", "1.0rc2", "1.0rc10", "1.0"]

versions.with_mode("legacy").sorted(["1.2.0", "1.2"])
# ["1.2", "1.2.0"]: legacy does not zero-pad releases.
```

### Records, tuples and dictionaries

```starlark
releases = [
    struct(version="2.0", archive="new.tar.xz"),
    struct(version="1.0", archive="old.tar.xz"),
]
ordered = semver.sorted(releases, key=lambda release: release.version)
# [releases[1], releases[0]]: records, not extracted version strings.
chosen = semver.latest(releases, key=lambda release: release.version)
# chosen.archive == "new.tar.xz"

catalogue = {"2.0": "new.tar.xz", "1.0": "old.tar.xz"}
ordered_pairs = semver.sorted(catalogue.items(), key=lambda entry: entry[0])
# [("1.0", "old.tar.xz"), ("2.0", "new.tar.xz")]

by_name = {"new": releases[0], "old": releases[1]}
chosen_pair = semver.latest(by_name.items(), key=lambda entry: entry[1].version)
# ("new", releases[0]): preserve both the dictionary key and its value.
```

Dictionary entries and other `(version, data)` tuples need no special sorting algorithm: `key`
identifies the version. A dictionary passed directly fails instead of guessing your intent.

### Inclusion and exclusion are functions, not expression lists

Both callbacks default to `None`. Inclusion must return `True` for an item to proceed; exclusion
must return `False` for it to survive. Exclusion wins if both return `True`. The exact sequence is:

1. Extract the version with `key`, if supplied.
2. Evaluate `include_requirements(version)`, if supplied; skip the item if false.
3. Evaluate `exclude_requirements(version)`, if supplied; skip the item if true.
4. Validate the retained version using the selected mode, then retain the original item.

Callbacks must return actual booleans, not truthy strings or integers. Exclusion is not called for
an item rejected by inclusion. Rejected values are not parsed by the collection operation, so an
inclusion predicate may screen malformed data before version validation. Retained values are
validated even for singleton lists and `filter`, which does not sort. Callback failures propagate.
An empty collection still validates mode and callback argument types, but calls no callbacks.

Use ordinary Starlark `and`, `or`, and `not` to make grouping explicit:

```starlark
matching = semver.filter(
    ["23.0", "23.1", "23.1.2", "23.2-rc1", "24.0"],
    include_requirements=lambda v: semver.major(v) == 23 and semver.ge(v, "23.1"),
    exclude_requirements=lambda v: semver.is_prerelease(v) or semver.eq(v, "23.1.2"),
)
# ["23.1"]
```

There is no implicit AND/OR interpretation of lists, no additional `requirements` attribute, and
no hidden prerelease preference. Without callbacks, prereleases participate in ordinary version
ordering. For example, `latest(["23.1", "24.0-rc1"])` returns `"24.0-rc1"` in SemVer mode.
Predicates are ordinary functions; selecting a collection mode does not change their bodies.
Use methods from the same mode-bound API inside predicates when consistent semantics are wanted.

### Reusing requirement expressions

The existing expression parser and checker remain available. Parse once when checking many
candidates, then close over the result in your predicate:

```starlark
requirements = semver.parse_requirements("major()==23,>=23.1,<24")
chosen = semver.latest(
    releases,
    key=lambda release: release.version,
    include_requirements=lambda v: semver.check_all_requirements(v, requirements),
    exclude_requirements=semver.is_prerelease,
    default=None,
)
```

`default` is returned unchanged when no item survives, including for empty input. A default does
not suppress invalid-version or callback errors. If `None` itself can be an original item (with
a custom `key`), use a distinct default such as a sentinel struct to distinguish no match.

`earliest` and `latest` perform a linear selection rather than sorting the entire list. Their
results equal stable ascending sorting followed by `[0]` and `[-1]`, respectively. This includes
tie behavior: earliest takes the first equal-precedence item; latest takes the last. Use `filter`
and `sorted` separately when you need all candidates or custom post-processing.

### Prerelease filtering is caller-owned

Use the existing `is_prerelease` predicate to choose whether prereleases participate. This works
in every mode; Python mode also identifies development releases as prereleases. No collection
operation inspects requirement clauses to infer a separate admission policy.

```starlark
semver = versions.with_mode("semver")
values = ["23.1.0", "24.0.0-rc1"]
semver.latest(values)                                                          # "24.0.0-rc1"
semver.latest(values, exclude_requirements=semver.is_prerelease)               # "23.1.0"
semver.latest(values, include_requirements=semver.is_prerelease)               # "24.0.0-rc1"

python = versions.with_mode("pep440")
python.latest(["1.0", "2.0.dev1"])                                             # "2.0.dev1"
python.latest(["1.0", "2.0.dev1"], exclude_requirements=python.is_prerelease)  # "1.0"
```

A caller can expose a boolean option without inspecting requirement syntax:

```starlark
allow_prereleases = False
chosen = semver.latest(
    values,
    exclude_requirements=None if allow_prereleases else semver.is_prerelease,
)
```

To allow prereleases within a particular range, just use that range as the inclusion predicate:

```starlark
requirements = semver.parse_requirements(">=23.1.0-rc1,<23.1.0")
chosen = semver.latest(
    ["23.1.0-rc1", "23.1.0-rc2", "23.1.0", "23.2.0-rc1"],
    include_requirements=lambda v: semver.check_all_requirements(v, requirements),
)
# "23.1.0-rc2"
```

An explicit exclusion still wins: adding `exclude_requirements=semver.is_prerelease` to this
example leaves no matches and returns `None`. Eligibility is exactly what your predicates express.

For toolchain catalogues, first restrict entries to compatible host/platform archives. These
operations do not query registries, download archives, or determine platform compatibility. Preserve
archive data with `key`, and select only among the candidates your toolchain can actually use.

## Parsed requirements and failures

`check_all_requirements` accepts a comma-separated string or a list of strings/parsed records.
`check_one_requirement` accepts one string or one record. `parse_requirements` returns records with
`op` and `version`; zero-argument component-call records also carry `component`, and other expression clauses carry
an opaque `expression` description, including unresolved constant references. Legacy/SemVer plain operands are parsed component lists, whereas
Python plain operands retain strings for wildcard/arbitrary equality. New introspection expressions
also carry `result_type`; their `version` field holds the typed integer, boolean or text operand.
Keep the same mode when
parsing and checking; treating a normalized legacy suffix list as SemVer cannot restore its spelling.

Invalid modes, malformed standards-mode versions, unsupported comparators, malformed wildcard
shapes, invalid component indices/counts, invalid function expressions, malformed constant dictionaries, and unknown constant references fail. Some argument/arity
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
