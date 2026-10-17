# Copyright 2026 M. Boerger, the MBO Works authors.
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

"""Internal PEP 440 parsing, precedence, and version-clause predicates.

Specification: https://packaging.python.org/en/latest/specifications/version-specifiers/
No Python runtime or regular expression dependency is needed by consumers.
"""

_DIGITS = "0123456789"
_ALNUM = _DIGITS + "abcdefghijklmnopqrstuvwxyz"
_SEPARATORS = ".-_"

def _invalid(value):
    fail("Invalid PEP 440 version: '{}'".format(value))

def _number(value, start):
    end = start
    for index in range(start, len(value)):
        if value[index] not in _DIGITS:
            break
        end = index + 1
    return struct(end = end, value = int(value[start:end]) if end > start else None)

def _suffix(value, start, labels):
    pos = start
    if pos < len(value) and value[pos] in _SEPARATORS:
        pos += 1
    for label, canonical in labels:
        if not value[pos:].startswith(label):
            continue
        pos += len(label)
        if pos < len(value) and value[pos] in _SEPARATORS:
            pos += 1
        number = _number(value, pos)
        return struct(end = number.end, value = (canonical, number.value or 0))
    return struct(end = start, value = None)

def _try_parse(version):
    if type(version) == "struct" and getattr(version, "scheme", None) == "pep440":
        return version
    if type(version) in ["list", "tuple"]:
        version = ".".join([str(part) for part in version])
    value = str(version).strip().lower()
    if value.startswith("v"):
        value = value[1:]
    public_local = value.split("+")
    if len(public_local) > 2:
        return None
    local = []
    if len(public_local) == 2:
        for part in public_local[1].replace("-", ".").replace("_", ".").split("."):
            if not part or not all([char in _ALNUM for char in part.elems()]):
                return None
            local.append(int(part) if part.isdigit() else part)
    epoch_public = public_local[0].split("!")
    epoch = 0
    if len(epoch_public) > 2:
        return None
    if len(epoch_public) == 2:
        if not epoch_public[0] or not epoch_public[0].isdigit():
            return None
        epoch = int(epoch_public[0])
    public = epoch_public[-1]
    first = _number(public, 0)
    if first.value == None:
        return None
    release = [first.value]
    pos = first.end
    for _unused in range(len(public)):
        if pos >= len(public) or public[pos] != ".":
            break
        number = _number(public, pos + 1)
        if number.value == None:
            break
        release.append(number.value)
        pos = number.end
    pre = _suffix(public, pos, [("alpha", "a"), ("beta", "b"), ("preview", "rc"), ("pre", "rc"), ("rc", "rc"), ("a", "a"), ("b", "b"), ("c", "rc")])
    pos = pre.end
    if pos + 1 < len(public) and public[pos] == "-" and public[pos + 1] in _DIGITS:
        number = _number(public, pos + 1)
        post = struct(end = number.end, value = ("post", number.value))
    else:
        post = _suffix(public, pos, [("post", "post"), ("rev", "post"), ("r", "post")])
    dev = _suffix(public, post.end, [("dev", "dev")])
    if dev.end != len(public):
        return None
    normalized = (str(epoch) + "!" if epoch else "") + ".".join([str(part) for part in release])
    if pre.value != None:
        normalized += pre.value[0] + str(pre.value[1])
    if post.value != None:
        normalized += ".post" + str(post.value[1])
    if dev.value != None:
        normalized += ".dev" + str(dev.value[1])
    if local:
        normalized += "+" + ".".join([str(part) for part in local])
    return struct(
        scheme = "pep440",
        epoch = epoch,
        release = tuple(release),
        pre = pre.value,
        post = post.value[1] if post.value != None else None,
        dev = dev.value[1] if dev.value != None else None,
        local = tuple(local),
        normalized = normalized,
    )

def _parse(version):
    parsed = _try_parse(version)
    if parsed == None:
        _invalid(version)
    return parsed

def _cmp(lhs, rhs):
    return int(lhs > rhs) - int(lhs < rhs)

def _sequence_cmp(lhs, rhs, *, local = False):
    for left, right in zip(lhs, rhs):
        if type(left) != type(right):
            # PEP 440 local numeric identifiers sort after lexical identifiers.
            return (1 if type(left) == "int" else -1) if local else _cmp(str(left), str(right))
        result = _cmp(left, right)
        if result:
            return result
    return _cmp(len(lhs), len(rhs))

def _pre_key(version):
    if version.pre != None:
        return [{"a": 0, "b": 1, "rc": 2}[version.pre[0]], version.pre[1]]

    # A development release without a pre/post segment precedes all prereleases.
    return [-1] if version.dev != None and version.post == None else [3]

def _compare(lhs, rhs, *, local = True):
    left = _parse(lhs)
    right = _parse(rhs)
    width = max(len(left.release), len(right.release))
    for result in [
        _cmp(left.epoch, right.epoch),
        _sequence_cmp(list(left.release) + [0] * (width - len(left.release)), list(right.release) + [0] * (width - len(right.release))),
        _sequence_cmp(_pre_key(left), _pre_key(right)),
        _cmp(-1 if left.post == None else left.post, -1 if right.post == None else right.post),
        _sequence_cmp([1] if left.dev == None else [0, left.dev], [1] if right.dev == None else [0, right.dev]),
    ]:
        if result:
            return result
    return _sequence_cmp(left.local, right.local, local = True) if local else 0

def _prefix_pattern(pattern):
    if type(pattern) != "string" or not pattern.endswith(".*") or pattern.count("*") != 1:
        fail("PEP 440 wildcard requires a numeric release prefix and trailing '.*'.")
    parsed = _parse(pattern[:-2])
    if parsed.pre != None or parsed.post != None or parsed.dev != None or parsed.local:
        fail("PEP 440 wildcard requires a numeric release prefix and trailing '.*'.")
    return parsed

def _matches(version, pattern):
    candidate = _parse(version)
    if type(pattern) == "string" and "*" in pattern:
        prefix = _prefix_pattern(pattern)
        release = list(candidate.release) + [0] * max(0, len(prefix.release) - len(candidate.release))
        return candidate.epoch == prefix.epoch and release[:len(prefix.release)] == list(prefix.release)
    required = _parse(pattern)
    return _compare(candidate, required, local = bool(required.local)) == 0

def _compatible(version, required):
    minimum = _parse(required)
    if len(minimum.release) < 2 or minimum.local:
        fail("PEP 440 compatible release requires at least two release components and no local version.")
    prefix = (str(minimum.epoch) + "!" if minimum.epoch else "") + ".".join([str(part) for part in minimum.release[:-1]]) + ".*"
    return _compare(version, minimum, local = False) >= 0 and _matches(version, prefix)

def _clause(version, op, required):
    if op in ["~~=", "!~~="]:
        prefix = _prefix_pattern(required)
        matched = _matches(version, required) and _compare(version, prefix, local = False) >= 0
        return matched if op == "~~=" else not matched
    if op == "!~=":
        return not _compatible(version, required)
    if op == "===":
        # Arbitrary equality is a string escape hatch, including invalid versions.
        parsed = _try_parse(version)
        candidate = parsed.normalized if parsed != None else str(version)
        return candidate.lower() == str(required).lower()
    if op in ["==", "!="]:
        matched = _matches(version, required)
        return matched if op == "==" else not matched
    if type(required) == "string" and "*" in required:
        fail("PEP 440 wildcard requirements only support '==' and '!='.")
    if op == "~=":
        return _compatible(version, required)
    candidate = _parse(version)
    minimum = _parse(required)
    if minimum.local:
        fail("PEP 440 ordered requirements cannot contain local versions.")
    result = _compare(candidate, minimum, local = False)
    if op == ">=":
        return result >= 0
    if op == "<=":
        return result <= 0
    same_base = candidate.epoch == minimum.epoch and _sequence_cmp(
        list(candidate.release) + [0] * max(0, len(minimum.release) - len(candidate.release)),
        list(minimum.release) + [0] * max(0, len(candidate.release) - len(minimum.release)),
    ) == 0
    if op == "<":
        # <V excludes prereleases of V unless V itself is a prerelease.
        excluded = minimum.pre == None and minimum.dev == None and (candidate.pre != None or candidate.dev != None) and same_base
        return result < 0 and not excluded
    if op == ">":
        # >V excludes postreleases of V unless V itself is a postrelease, and
        # always excludes local versions of that same base release.
        excluded = same_base and ((minimum.post == None and candidate.post != None) or bool(candidate.local))
        return result > 0 and not excluded
    fail("Bad PEP 440 comparator: '{}'".format(op))

pep440 = struct(
    parse = _parse,
    cmp = _compare,
    matches = _matches,
    compatible = _compatible,
    compare = _clause,
)
