# Copyright 2025 M. Boerger, the MBO Works authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""A starlark implementation of versioning functions that mostly follow semver.

SEE [Versions reference](https://github.com/mboworks/bzl/blob/main/docs/versions.md).
"""

load(":expression.bzl", "expression")
load(":pep440.bzl", "pep440")

# Longest tokens first: !~~= must never be consumed as !~= or ~=.
_NAMED_COMPONENTS = {"major": 0, "minor": 1, "patch": 2}
_COMPONENT_OPERATORS = ["==", "!=", ">", ">=", "<", "<="]
_REQUIREMENT_OPERATORS = ["!~~=", "~~=", "!~=", "~=", ">=", "<=", "==", "!=", ">", "<"]

def _maybe_int(value):
    if type(value) == "string" and value.isdigit():
        return int(value)
    return value

def _legacy_parse_pre_release(version):
    parts = [_maybe_int(v) for v in version.split(".")]
    results = []
    for part in parts:
        if type(part) == "int":
            results.append(part)
            continue
        part = str(part)
        if not part[0].isdigit() and part[-1].isdigit():
            p = 0  # The interpreter does not see this is always initialized.
            for p in range(len(part), 0, -1):
                if not part[p - 1].isdigit():
                    break
            if p > 1 and part[p - 1] == "-":
                # A single trailing "-" gets removed iff remainder is not empty.
                results.append(part[:p - 1])
            else:
                results.append(part[:p])
            results.append(part[p:])
        else:
            results.append(part)
    return results

def _split_version_relese_build(version, *, skip_build = False):
    """Parse `version` aspects for pre-release and build.

    The function drops the build component if needed (`skip_build`).

    Args:
        version:    The version to parse.
        skip_build: Whether to drop the build component.
                    Useful ONLY for Semver correct comparisons.

    Returns:
        Array of parsed components (only correctly handling pre-release and build).
            * Any pre_release is preceded by '-'.
            * Any build is preceded by '+'.
    """
    r = None
    b = None
    for p in range(len(version)):
        if not b:
            if version[p] == "+":
                b = p
                break
            if not r and version[p] == "-":
                r = p

    if r and b:
        rel = _legacy_parse_pre_release(version[r + 1:b])
        if skip_build:
            bld = []
        else:
            bld = _parse_build(version[b + 1:])
        return [version[:r], "-"] + rel + ["+"] + bld
    elif r:
        rel = _legacy_parse_pre_release(version[r + 1:])
        return [version[:r], "-"] + rel
    elif b:
        if skip_build:
            bld = []
        else:
            bld = _parse_build(version[b + 1:])
        return [version[:b], "+"] + bld
    else:
        return [version]

def _parse_build(version):
    parts = [_maybe_int(v) for v in version.split(".")]
    return parts

def _list_find(values, needle, default = None):
    for pos in range(len(values)):
        if values[pos] == needle:
            return pos
    return default

def _legacy_parse_version(version, *, skip_build = False, error = "Cannot parse version."):
    """Parses the input into a `list` or `tuple` of version components.

    Args:
        version:    The version to parse.
        skip_build: Whether to drop the build component.
                    Useful ONLY for Semver correct comparisons.
        error:      Error messae to pass to `fail`.

    Returns:
        Array of parsed components.
            * Any pre_release is preceded by '-'.
            * Any build is preceded by '+'.

    The function requires the input to be a single int, string, list or tuple.
    If the input is a string, then it is separated into its components:
        <major>['.' <minor> [ '.' <patch> [.*]]]
    A single integer is turned into a list.
    Lists or tuples are returned as is.
    Everything else is an error.

    While this attempts to retain Semver principles this mostly works for
    simple versions that have components consisting of (major, minor, patch).

    The function is also relaxed about Semver as it is safer to try to parse
    with likely intent rather then exact standard enforcement. If the latter is
    necessary than a separate function, setting or parameter is needed.
    """
    if type(version) == "int":
        return [version]
    elif type(version) == "string":
        if not version:
            return []
        version = version.split(".", 2)
        if version:
            if version[-1].count("-") + version[-1].count("+") == 0:
                # No semver compatible <pre_release> or <build> present.
                # For safety we just split on all dots which is likely the
                # intended behavior.
                version = version[:-1] + version[-1].split(".")
            elif version[-1]:
                # Unlike Semver which requires <major>.<minor>.<patch> we allow
                # any length of number/"." sequence followed by "-" or "+" for
                # <pre_release> and <build> components respectively.
                # Note: Semver allows both <pre_release> and <build> to be "."
                # separated parts. Still separated by "-" and "+" respectively.
                release_build = _split_version_relese_build(
                    version[-1],
                    skip_build = skip_build,
                )
                version = version[:-1] + release_build
    elif type(version) == "tuple":
        version = [v for v in version]
    if type(version) == "list":
        if skip_build:
            end = _list_find(version, "+", len(version))
        else:
            end = len(version)
        return [_maybe_int(version[p]) for p in range(len(version)) if p < end]
    extra_error = "Input was: '{version}'.".format(version = version)
    if error:
        fail([error, extra_error].join(" "))
    else:
        fail(extra_error)

def _release_parse_version(version):
    # Select release components before the legacy suffix normalization. This also
    # handles suffixes on short releases such as 1-rc.1 without losing components.
    if type(version) == "string":
        version = version.split("+", 1)[0].split("-", 1)[0]
    return _legacy_parse_version(version)

def _check_mode(mode):
    if mode not in ["legacy", "semver", "pep440"]:
        fail("Version mode must be 'legacy', 'semver', or 'pep440'; got '{}'.".format(mode))

def _parse_version(version, *, skip_build = False, error = "Cannot parse version.", mode = "legacy"):
    """Parses a version; legacy preserves historical normalization, semver preserves identifiers.

    Args:
        version: Version string, integer, list, or tuple.
        skip_build: Drop build metadata.
        error: Custom failure message for unsupported input types.
        mode: "legacy" (default), "semver", or "pep440"; see docs/versions.md.

    Returns:
        Legacy/SemVer: list of components. PEP 440: named version record.
        All modes preserve the original release component count.
    """
    _check_mode(mode)
    if mode == "pep440":
        return pep440.parse(version)
    if mode == "legacy":
        return _legacy_parse_version(version, skip_build = skip_build, error = error)
    return _constraint_parse(version, skip_build = skip_build)

def _cmp(lhs, rhs):
    if lhs == rhs:
        return 0
    lhs = _maybe_int(lhs)
    rhs = _maybe_int(rhs)
    if type(lhs) == "int" or type(rhs) == "int":
        # Purely numeric identifiers have lower precedence than strings.
        if type(lhs) == "int" and type(rhs) == "string":
            return -1
        if type(lhs) == "string" and type(rhs) == "int":
            return 1
        if type(lhs) == "int" and type(rhs) == "int":
            return int(lhs > rhs) - int(lhs < rhs)
    lhs = str(lhs)
    rhs = str(rhs)
    return int(lhs > rhs) - int(lhs < rhs)

def _release_components(parsed):
    return parsed[:min(_list_find(parsed, "-", len(parsed)), _list_find(parsed, "+", len(parsed)))]

def _version_components(version, *, start = 0, end = None, pad = False, mode = "semver"):
    """Returns selected release components as a dot-separated string.

    Args:
        version: Version to slice; legacy/SemVer slicing is permissive, not validation.
        start: Inclusive index, relative to the original length when negative.
        end: Exclusive index; None uses the original length.
        pad: Extend with zeros to an explicitly supplied positive end before slicing.
        mode: Release-slicing mode; only "pep440" requires a full version parse.

    Returns:
        Selected release components, or an empty string for an empty selection.
    """
    if type(start) != "int" or (end != None and type(end) != "int"):
        fail("Component indices must be integers or end = None.")
    _check_mode(mode)
    parts = list(pep440.parse(version).release) if mode == "pep440" else _release_components(_release_parse_version(version))
    size = len(parts)
    start = max(0, size + start) if start < 0 else start
    end = size if end == None else (max(0, size + end) if end < 0 else end)
    if pad and end > size:
        parts = parts + [0] * (end - size)
    return ".".join([str(part) for part in parts[start:end]])

def _version_prefix(version, count, *, mode = "semver"):
    """Returns at most count release components as a dot-separated string.

    Args:
        version: Version to slice; legacy/SemVer slicing is permissive, not validation.
        count: Non-negative number of components to select, without padding.
        mode: Release-slicing mode; only "pep440" requires a full version parse.

    Returns:
        The release prefix, or an empty string when count is zero.
    """
    if type(count) != "int" or count < 0:
        fail("Prefix count must be a non-negative integer.")
    return _version_components(version, end = count, mode = mode)

def _named_component(version, name, *, mode = "semver"):
    if name not in _NAMED_COMPONENTS:
        fail("Unknown named version component: '{}'".format(name))
    parsed = _parse_version(version, mode = mode)
    release = list(parsed.release) if mode == "pep440" else _release_components(parsed)
    if not release:
        fail("Named version components require a non-empty numeric release.")
    index = _NAMED_COMPONENTS[name]
    value = release[index] if index < len(release) else 0
    if type(value) != "int" or value < 0:
        fail("Named version components require non-negative integers.")
    return value

def _version_major(version, *, mode = "semver"):
    """Returns the integer major component of version under the selected mode."""
    return _named_component(version, "major", mode = mode)

def _version_minor(version, *, mode = "semver"):
    """Returns the integer minor component, or zero when omitted."""
    return _named_component(version, "minor", mode = mode)

def _version_patch(version, *, mode = "semver"):
    """Returns the integer patch component, or zero when omitted."""
    return _named_component(version, "patch", mode = mode)

def _constant_bindings(constants):
    if constants == None:
        return {}
    if type(constants) != "dict":
        fail("Version constants must be a dict or None.")
    for name in constants:
        if not expression.identifier(name):
            fail("Version constant names must be ASCII identifiers other than True, False, or None: '{}'".format(name))
    return constants

def _expression_value(nodes, version, mode, constants):
    functions = {
        "components": _version_components,
        "major": _version_major,
        "minor": _version_minor,
        "patch": _version_patch,
        "prefix": _version_prefix,
    }
    results = {}
    for index in range(len(nodes) - 1, -1, -1):
        node = nodes[index]
        if hasattr(node, "reference"):
            if node.reference not in constants:
                fail("Unknown version constant: '{}'".format(node.reference))
            results[index] = constants[node.reference]
            continue
        args = [results[arg.node] if hasattr(arg, "node") else arg.value for arg in node.args]
        kwargs = {key: results[arg.node] if hasattr(arg, "node") else arg.value for key, arg in node.kwargs.items()}
        if "version" not in kwargs:
            if node.function == "prefix" and len(args) == 1 and "count" not in kwargs:
                args = [version] + args
            elif not args:
                kwargs["version"] = version
        results[index] = functions[node.function](mode = mode, *args, **kwargs)
    return results[0]

def _constraint_parse(version, *, skip_build = True):
    # Validate raw suffix identifiers before converting numeric strings; this
    # retains enough information to reject leading zeros in prereleases.
    if type(version) == "string":
        release_build = version.split("+", 1)
        release_pre = release_build[0].split("-", 1)
        release_parts = release_pre[0].split(".")
        if any([len(part) > 1 and part[0] == "0" and part.isdigit() for part in release_parts]):
            fail("Numeric SemVer release components must not have leading zeros.")
        parsed = _legacy_parse_version(release_pre[0])
        if len(release_pre) == 2:
            parsed += ["-"] + release_pre[1].split(".")
        if len(release_build) == 2:
            parsed += ["+"] + release_build[1].split(".")
    else:
        parsed = _legacy_parse_version(version)
    release = _release_components(parsed)
    if not release or not all([type(part) == "int" and part >= 0 for part in release]):
        fail("Version constraints require non-negative numeric release components.")
    suffix = parsed[len(release):]
    build = False
    for index, part in enumerate(suffix):
        if index == 0 and part == "-":
            continue
        if part == "+" and not build:
            build = True
            continue
        identifier = str(part)
        if not identifier or not all([char in "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-" for char in identifier.elems()]):
            fail("Version suffixes require non-empty SemVer identifiers.")
        if not build and identifier.isdigit() and len(identifier) > 1 and identifier[0] == "0":
            fail("Numeric SemVer prerelease identifiers must not have leading zeros.")
    if suffix and (len(suffix) == 1 or suffix[-1] == "+"):
        fail("Version suffixes require non-empty SemVer identifiers.")
    if skip_build:
        parsed = parsed[:_list_find(parsed, "+", len(parsed))]
    return [_maybe_int(part) for part in parsed]

def _identifiers_cmp(lhs, rhs):
    for left, right in zip(lhs, rhs):
        result = _cmp(left, right)
        if result:
            return result
    return _cmp(len(lhs), len(rhs))

def _constraint_cmp(lhs, rhs):
    left = _release_components(lhs)
    right = _release_components(rhs)
    width = max(len(left), len(right))
    result = _identifiers_cmp(left + [0] * (width - len(left)), right + [0] * (width - len(right)))
    if result:
        return result
    left_suffix = lhs[len(left):]
    right_suffix = rhs[len(right):]
    left_pre = left_suffix[1:_list_find(left_suffix, "+", len(left_suffix))] if left_suffix and left_suffix[0] == "-" else []
    right_pre = right_suffix[1:_list_find(right_suffix, "+", len(right_suffix))] if right_suffix and right_suffix[0] == "-" else []
    if bool(left_pre) != bool(right_pre):
        return -1 if left_pre else 1
    result = _identifiers_cmp(left_pre, right_pre)
    if result:
        return result
    return _identifiers_cmp(
        left_suffix[_list_find(left_suffix, "+", len(left_suffix)) + 1:],
        right_suffix[_list_find(right_suffix, "+", len(right_suffix)) + 1:],
    )

def _has_wildcard(version):
    if type(version) == "string":
        return "*" in version
    if type(version) in ["list", "tuple"]:
        return any(["*" in str(part) for part in version])
    return False

def _match_prefix(pattern):
    parts = pattern.split(".") if type(pattern) == "string" else _parse_version(pattern)
    if len(parts) < 2 or parts[-1] != "*" or not all([str(part).isdigit() for part in parts[:-1]]):
        fail("A wildcard pattern must be a numeric release prefix followed by a single trailing '.*'.")
    return [int(part) for part in parts[:-1]]

def _version_matches(version, pattern, *, skip_build = True, mode = "semver"):
    """Returns whether version matches an exact version or a trailing .* pattern.

    Args:
        version: Candidate with numeric release components and SemVer suffixes.
        pattern: An exact version, or a numeric release prefix followed by .*.
        skip_build: Ignore build metadata, as SemVer requires for precedence.
        mode: "semver" (default), "legacy", or "pep440"; see docs/versions.md.

    Returns:
        Whether the exact version or whole-component release prefix matches.
        Release comparisons pad missing components with zeros. A wildcard ignores
        suffixes; admitting prereleases remains a separate caller policy.
    """
    _check_mode(mode)
    if mode == "pep440":
        return pep440.matches(version, pattern)
    candidate = _parse_version(version, skip_build = skip_build, mode = mode)
    if _has_wildcard(pattern):
        prefix = _match_prefix(pattern)
        release = _release_components(candidate)
        return (release + [0] * max(0, len(prefix) - len(release)))[:len(prefix)] == prefix
    return _version_cmp(candidate, pattern, skip_build = skip_build, mode = mode) == 0

def _version_compatible(version, required, *, skip_build = True, mode = "semver"):
    """Returns whether version satisfies the compatible release requirement ~=required.

    Args:
        version: Candidate version, using SemVer prerelease/build syntax.
        required: Lower bound with at least two numeric release components.
            All but its last release component determine the required prefix.
        skip_build: Ignore build metadata for precedence, as SemVer requires.
        mode: "semver" (default), "legacy", or "pep440"; see docs/versions.md.

    Returns:
        Whether the candidate shares the required prefix and meets the lower bound.
        Release comparisons are zero-padded without discarding operand precision.
        Prerelease admission is a separate caller policy, as with ge/lt.
    """
    _check_mode(mode)
    if mode == "pep440":
        return pep440.compatible(version, required)
    candidate = _parse_version(version, skip_build = skip_build, mode = mode)
    minimum = _parse_version(required, skip_build = skip_build, mode = mode)
    release = _release_components(minimum)
    if len(release) < 2:
        fail("A compatible release requirement needs at least two release components.")
    return _version_matches(candidate, release[:-1] + ["*"], mode = mode) and _version_cmp(candidate, minimum, skip_build = skip_build, mode = mode) >= 0

def _version_extended_compatible(version, pattern, *, skip_build = True, mode = "semver"):
    # This extension adds a stable lower bound to prefix matching. Unlike ==1.2.*,
    # ~~=1.2.* excludes prereleases of 1.2, while admitting later matching cores.
    prefix = _match_prefix(pattern)
    return _version_matches(version, pattern, skip_build = skip_build, mode = mode) and _version_cmp(
        version,
        prefix,
        skip_build = skip_build,
        mode = mode,
    ) >= 0

def _extra_cmp(lhs, rhs):
    """Comparisons respecting `None`, "-" and "+"."""
    if _maybe_int(lhs) == _maybe_int(rhs):
        return 0
    if not lhs:
        if rhs == "-":
            return 1
        else:
            return -1
    if not rhs:
        if lhs == "-":
            return -1
        else:
            return 1

    # Case `lhs == rhs` was already handled.
    if lhs == "-":
        return -1
    elif rhs == "-":
        return 1

    return _cmp(lhs, rhs)

def _at_or(array, pos, default = None):
    if pos < len(array):
        return array[pos]
    return default

def _legacy_version_cmp(version_lhs, version_rhs, *, skip_build = True):
    """Implements `version_lhs` <=> `version_rhs`."""
    lhs = _legacy_parse_version(
        version = version_lhs,
        skip_build = skip_build,
        error = "Left hand argument is neither string, int nor list but {typ}.".format(
            typ = type(version_lhs),
        ),
    )
    rhs = _legacy_parse_version(
        version = version_rhs,
        skip_build = skip_build,
        error = "Right hand argument is neither string, int nor list {typ}.".format(
            typ = type(version_rhs),
        ),
    )
    for part in range(max(len(lhs), len(rhs))):
        lhs_part = _at_or(lhs, part)
        rhs_part = _at_or(rhs, part)
        if lhs_part in ["-", "+"] or rhs_part in ["-", "+"]:
            res = _extra_cmp(lhs_part, rhs_part)
            if res != 0:
                return res
            continue
        if part >= len(lhs) or part >= len(rhs):
            break
        res = _cmp(lhs_part, rhs_part)
        if res != 0:
            return res

    # All parts available on both sides are the same.
    return _cmp(len(lhs), len(rhs))

def _version_cmp(version_lhs, version_rhs, *, skip_build = True, mode = "legacy"):
    """Compares versions using legacy behavior or zero-padded SemVer precedence."""
    _check_mode(mode)
    if mode == "pep440":
        return pep440.cmp(version_lhs, version_rhs)
    if mode == "legacy":
        return _legacy_version_cmp(version_lhs, version_rhs, skip_build = skip_build)
    return _constraint_cmp(
        _constraint_parse(version_lhs, skip_build = skip_build),
        _constraint_parse(version_rhs, skip_build = skip_build),
    )

def _version_ge(version_lhs, version_rhs, *, skip_build = True, mode = "legacy"):
    """Implements `version_lhs` >= `version_rhs`."""
    return _version_cmp(version_lhs, version_rhs, skip_build = skip_build, mode = mode) >= 0

def _version_le(version_lhs, version_rhs, *, skip_build = True, mode = "legacy"):
    """Implements `version_lhs` <= `version_rhs`."""
    return _version_cmp(version_lhs, version_rhs, skip_build = skip_build, mode = mode) <= 0

def _version_eq(version_lhs, version_rhs, *, skip_build = True, mode = "legacy"):
    """Implements `version_lhs` == `version_rhs`."""
    return _version_cmp(version_lhs, version_rhs, skip_build = skip_build, mode = mode) == 0

def _version_lt(version_lhs, version_rhs, *, skip_build = True, mode = "legacy"):
    """Implements `version_lhs` < `version_rhs`."""
    return _version_cmp(version_lhs, version_rhs, skip_build = skip_build, mode = mode) < 0

def _version_gt(version_lhs, version_rhs, *, skip_build = True, mode = "legacy"):
    """Implements `version_lhs` > `version_rhs`."""
    return _version_cmp(version_lhs, version_rhs, skip_build = skip_build, mode = mode) > 0

def _version_ne(version_lhs, version_rhs, *, skip_build = True, mode = "legacy"):
    """Implements `version_lhs` != `version_rhs`."""
    return _version_cmp(version_lhs, version_rhs, skip_build = skip_build, mode = mode) != 0

def _version_compare(lhs, op, rhs, *, skip_build = True, error = None, mode = "legacy"):
    """Implements `lhs OP rhs` using the selected comparison mode."""
    _check_mode(mode)
    if mode == "pep440":
        return pep440.compare(lhs, op, rhs)
    if op in ["~~=", "!~~="]:
        result = _version_extended_compatible(lhs, rhs, skip_build = skip_build, mode = mode)
        return result if op == "~~=" else not result
    if op in ["~=", "!~="] and not _has_wildcard(rhs):
        result = _version_compatible(lhs, rhs, skip_build = skip_build, mode = mode)
        return result if op == "~=" else not result
    if _has_wildcard(rhs):
        if op == "==":
            return _version_matches(lhs, rhs, skip_build = skip_build, mode = mode)
        elif op == "!=":
            return not _version_matches(lhs, rhs, skip_build = skip_build, mode = mode)
        fail("Wildcard requirements only support '==', '!=', '~~=', and '!~~='.")
    if op == ">=":
        return _version_ge(lhs, rhs, skip_build = skip_build, mode = mode)
    elif op == "<=":
        return _version_le(lhs, rhs, skip_build = skip_build, mode = mode)
    elif op == "<":
        return _version_lt(lhs, rhs, skip_build = skip_build, mode = mode)
    elif op == ">":
        return _version_gt(lhs, rhs, skip_build = skip_build, mode = mode)
    elif op == "==":
        return _version_eq(lhs, rhs, skip_build = skip_build, mode = mode)
    elif op == "!=":
        return _version_ne(lhs, rhs, skip_build = skip_build, mode = mode)
    elif error:
        fail(error)
    else:
        fail("Bad comparator: '{op}'.".format(op = op))

def _check_one_requirement_struct(version, requirement, *, skip_build = True, constants = None, mode = "legacy"):
    if hasattr(requirement, "expression"):
        version = _expression_value(requirement.expression, version, mode, constants)
    elif hasattr(requirement, "component"):
        version = _named_component(version, requirement.component, mode = mode)
    return _version_compare(
        version,
        requirement.op,
        requirement.version,
        skip_build = skip_build,
        mode = mode,
        error = "Bad requirement: '{requirement}'.".format(requirement = requirement),
    )

def _check_one_requirement(version, requirement, *, skip_build = True, constants = None, mode = "legacy"):
    """Version comparison of the given `version` against a `requirement` string.

    Compatible operators are ~= and !~=; wildcard-compatible extensions are
    ~~= and !~~=. Exact matching/exclusion uses == and !=, optionally with .*.
    Ordering uses <, <=, >, >=. All operators are requirement-string tokens.
    constants binds bare expression names at evaluation time; calls use library functions.
    """
    constants = _constant_bindings(constants)
    if type(requirement) == "string":
        requirement = _parse_split_requirement(requirement.strip(), mode = mode)
    return _check_one_requirement_struct(version, requirement, skip_build = skip_build, constants = constants, mode = mode)

def _check_all_requirements(version, requirements, *, skip_build = True, constants = None, mode = "legacy"):
    """Checks all clauses, resolving bare expression names from the constants dictionary."""
    _check_mode(mode)
    constants = _constant_bindings(constants)
    if type(requirements) == "list":
        return all([
            _check_one_requirement(version, r, skip_build = skip_build, constants = constants, mode = mode)
            for r in requirements
        ])
    if type(requirements) == "string":
        return all([
            _check_one_requirement(version, r.strip(), skip_build = skip_build, constants = constants, mode = mode)
            for r in expression.clauses(requirements)
        ])
    fail("Requirements must be 'list' or 'string'.")

def _parse_split_requirement(req, *, mode = "legacy"):
    operators = (["==="] if mode == "pep440" else []) + _REQUIREMENT_OPERATORS
    parts = expression.comparison(req, operators)
    left = parts.left
    op = parts.op
    value = parts.right
    fields = {}
    if left:
        nodes = expression.parse(left)
        if len(nodes) == 1 and getattr(nodes[0], "function", None) in _NAMED_COMPONENTS and not nodes[0].args and not nodes[0].kwargs:
            fields["component"] = nodes[0].function
        else:
            fields["expression"] = nodes
    if "component" in fields:
        if op not in _COMPONENT_OPERATORS:
            fail("Named version component '{}' requires ==, !=, <, <=, >, or >=.".format(fields["component"]))
        if not value or not value.isdigit():
            fail("Named version component '{}' requires a non-negative integer operand.".format(fields["component"]))
        return struct(op = op, version = [int(value)], **fields)
    if mode == "pep440":
        return struct(op = op, version = value.strip(), **fields)
    if _has_wildcard(value):
        if op not in ["==", "!=", "~~=", "!~~="]:
            fail("Wildcard requirements only support '==', '!=', '~~=', and '!~~='.")
        return struct(op = op, version = _match_prefix(value) + ["*"], **fields)
    if op in ["~~=", "!~~="]:
        fail("Extended compatible requirements need a single trailing '.*'.")
    return struct(op = op, version = _parse_version(value.strip(), mode = mode), **fields)

def _parse_requirements(requirements, *, mode = "legacy"):
    """Parses clauses without binding constants; supply their values when checking."""
    _check_mode(mode)
    return [
        _parse_split_requirement(req.strip(), mode = mode)
        for req in expression.clauses(requirements)
    ]

versions = struct(
    parse = _parse_version,
    components = _version_components,
    prefix = _version_prefix,
    major = _version_major,
    minor = _version_minor,
    patch = _version_patch,
    compatible = _version_compatible,
    matches = _version_matches,
    ge = _version_ge,
    gt = _version_gt,
    le = _version_le,
    lt = _version_lt,
    eq = _version_eq,
    ne = _version_ne,
    cmp = _version_cmp,
    compare = _version_compare,
    check_one_requirement = _check_one_requirement,
    check_all_requirements = _check_all_requirements,
    parse_requirements = _parse_requirements,
)
