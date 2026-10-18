# SPDX-FileCopyrightText: Copyright (c) M. Boerger, the MBO Works authors
# SPDX-License-Identifier: Apache-2.0
"""Collection contracts and catalogue-selection regression tests."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts", "unittest")
load(":versions.bzl", "versions")

_semver = versions.with_mode("semver")

def _collections_test_impl(ctx):
    env = unittest.begin(ctx)
    values = ["2.0", "1.10", "1.2", "1.2.0", "1.2+001", "1.2+1"]
    expected = ["1.2", "1.2.0", "1.2+001", "1.2+1", "1.10", "2.0"]
    asserts.equals(env, expected, _semver.sorted(values))
    asserts.equals(env, ["2.0", "1.10", "1.2", "1.2.0", "1.2+001", "1.2+1"], _semver.sorted(values, reverse = True))
    asserts.equals(env, expected, _semver.sorted(tuple(values)))
    asserts.equals(env, "2.0", values[0])
    asserts.equals(env, [], _semver.sorted([]))
    asserts.equals(env, [1, 2], _semver.sorted([2, 1], key = str))
    asserts.equals(env, [[1, 2], (2, 0)], _semver.sorted([(2, 0), [1, 2]]))
    asserts.equals(env, ["1.2.0"], _semver.filter(["1.2.0"]))
    asserts.equals(env, ["1.2.0", "1.2"], _semver.sorted(["1.2.0", "1.2"]))
    asserts.equals(env, ["1.2", "1.2.0"], versions.with_mode("legacy").sorted(["1.2.0", "1.2"]))
    asserts.equals(env, ["1.2", "1.2.0"], _semver.sorted(["1.2.0", "1.2"], mode = "legacy"))
    asserts.equals(env, ["1.0.dev1", "1.0rc2", "1.0rc10", "1.0", "1.0.post1"], versions.with_mode("pep440").sorted(["1.0", "1.0rc10", "1.0.post1", "1.0.dev1", "1.0rc2"]))
    asserts.equals(env, ["1+1", "1+2"], _semver.sorted(["1+2", "1+1"], skip_build = False))
    asserts.equals(env, ["1+2", "1+1"], _semver.sorted(["1+2", "1+1"]))
    asserts.equals(env, "1+2", _semver.latest(["1+2", "1+1"], skip_build = False))
    asserts.equals(env, "1+1", _semver.latest(["1+2", "1+1"]))
    python = versions.with_mode("pep440")
    asserts.equals(env, ["1.0", "1.0.post1"], python.filter(["1.0rc1", "1.0", "1.0.dev1", "1.0.post1"], exclude_requirements = python.is_prerelease))
    asserts.equals(env, "1.0+2", python.latest(["1.0+2", "1.0+1"]))

    # Exercise uneven merge runs and a larger descending input.
    numbers = list(range(129, -1, -1))
    asserts.equals(env, list(range(130)), _semver.sorted(numbers))
    asserts.equals(env, numbers, _semver.sorted(list(range(130)), reverse = True))

    records = [struct(version = "1.0+001", name = "a"), struct(version = "2", name = "b"), struct(version = "1.0+1", name = "c")]
    key = lambda item: item.version
    asserts.equals(env, [records[0], records[2], records[1]], _semver.sorted(records, key = key))
    asserts.equals(env, records[0], _semver.earliest(records, key = key))
    asserts.equals(env, records[2], _semver.latest(records, key = key, exclude_requirements = lambda v: _semver.ge(v, "2")))
    asserts.equals(env, records, _semver.filter(records, key = key))
    catalogue = dict([("2", "new.tar"), ("1.0", "old.tar")])
    asserts.equals(env, [("1.0", "old.tar"), ("2", "new.tar")], _semver.sorted(catalogue.items(), key = lambda entry: entry[0]))
    asserts.equals(env, ("2", "new.tar"), _semver.latest(catalogue.items(), key = lambda entry: entry[0]))

    # Stateful local key proves exactly one extraction per item for each operation.
    for operation in [_semver.filter, _semver.sorted, _semver.earliest, _semver.latest]:
        pending = list(values)
        operation(values, key = lambda _: pending.pop(0))
        asserts.equals(env, [], pending)
    asserts.equals(env, ["1+001"], _semver.filter(["1+001"], include_requirements = lambda v: v.endswith("001")))
    asserts.equals(env, [], _semver.filter(["1"], include_requirements = lambda v: True, exclude_requirements = lambda v: True))
    asserts.equals(env, [], _semver.filter(["not a version"], include_requirements = lambda v: False, exclude_requirements = lambda v: fail("must short circuit")))
    asserts.equals(env, None, _semver.latest([]))
    sentinel = struct(missing = True)
    asserts.equals(env, sentinel, _semver.earliest([], default = sentinel))
    asserts.equals(env, sentinel, _semver.latest(["1"], include_requirements = lambda v: False, default = sentinel))
    asserts.equals(env, None, _semver.latest([None], key = lambda _: "1", default = sentinel))
    return unittest.end(env)

def _selection_test_impl(ctx):
    env = unittest.begin(ctx)
    available = ["23.1.0-rc1", "23.1.0-rc2", "23.1.0", "23.1.2", "24.0.0-rc1"]
    for expression in ["major()==23", ">=23.1.0-rc1,<23.1.0", "!=23.1.0-rc1", "==23.1.*", "is_prerelease()==True"]:
        requirements = _semver.parse_requirements(expression)
        include = lambda v: _semver.check_all_requirements(v, requirements)
        exclude = lambda v: not _semver.allows_prerelease(v, requirements)
        matching = _semver.filter(available, include_requirements = include, exclude_requirements = exclude)
        ordered = _semver.sorted(matching)
        asserts.equals(env, ordered[0] if ordered else None, _semver.earliest(available, include_requirements = include, exclude_requirements = exclude))
        asserts.equals(env, ordered[-1] if ordered else None, _semver.latest(available, include_requirements = include, exclude_requirements = exclude))
    for version, requirement, expected in [
        ("23.1.0", None, True),
        ("23.1.0-rc1", None, False),
        ("23.1.0-rc2", ">=23.1.0-rc1,<23.1.0", True),
        ("23.2.0-rc1", ">=23.1.0-rc1", False),
        ("23.1-rc2", ">=23.1.0-rc1", True),
        ("23.1.0-rc1", "!=23.1.0-rc2", False),
        ("23.1.0-rc1", "!~=23.1.0-rc2", False),
        ("23.1.0-rc1", "!~~=23.1.*", False),
        ("23.1.0-rc1", "==23.1.*", False),
        ("23.1.0-rc1", "is_prerelease()==True", False),
        ("23.1.0-rc1", "prefix(3)==23.1.0-rc1", False),
    ]:
        asserts.equals(env, expected, _semver.allows_prerelease(version, requirement), repr((version, requirement)))
    asserts.equals(env, True, _semver.allows_prerelease("23.1-rc2", [">=23.1-rc1"]))
    return unittest.end(env)

_collections_test = unittest.make(_collections_test_impl)
_selection_test = unittest.make(_selection_test_impl)

def _invalid_impl(ctx):
    case = ctx.attr.case
    if case == "dict":
        _semver.sorted({"1": "a"})
    elif case == "key":
        _semver.sorted([], key = "version")
    elif case == "include":
        _semver.filter([], include_requirements = [">=1"])
    elif case == "exclude":
        _semver.latest([], exclude_requirements = "<2")
    elif case == "bool":
        _semver.filter(["1"], include_requirements = lambda v: 1)
    elif case == "exclude_bool":
        _semver.filter(["1"], exclude_requirements = lambda v: "yes")
    elif case == "singleton":
        _semver.sorted(["01.0"])
    elif case == "reverse":
        _semver.sorted([], reverse = 1)
    elif case == "mode":
        versions.sorted([], mode = "unknown")
    elif case == "admission_mode":
        versions.with_mode("pep440").allows_prerelease("1.0rc1")
    return []

_invalid = rule(implementation = _invalid_impl, attrs = {"case": attr.string()})

def _failure_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, ctx.attr.error)
    return analysistest.end(env)

_failure_test = analysistest.make(_failure_test_impl, expect_failure = True, attrs = {"error": attr.string()})

def collections_test_suite(name = "collections"):
    """Instantiates collection and expected-failure tests.

    Args:
        name: Prefix for the generated test targets.
    """
    _collections_test(name = name + "_test")
    _selection_test(name = name + "_selection_test")
    for case, error in [
        ("dict", "list or tuple"),
        ("key", "key must be a function"),
        ("include", "include_requirements must be a function"),
        ("exclude", "exclude_requirements must be a function"),
        ("bool", "must return a bool"),
        ("exclude_bool", "must return a bool"),
        ("singleton", "leading zeros"),
        ("reverse", "reverse must be a bool"),
        ("mode", "Version mode must be"),
        ("admission_mode", "requires semver mode"),
    ]:
        fixture = name + "_invalid_" + case
        _invalid(name = fixture, case = case, tags = ["manual"])
        _failure_test(name = fixture + "_test", target_under_test = ":" + fixture, error = error)
