# SPDX-FileCopyrightText: Copyright (c) M. Boerger, the MBO Works authors
# SPDX-License-Identifier: Apache-2.0
"""Tests for structural version normalization."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts", "unittest")
load(":versions.bzl", "versions")

def _normalize_test_impl(ctx):
    env = unittest.begin(ctx)
    for value, expected in [
        ("", ()),
        ([], ()),
        ((), ()),
        ("001.02", ("001", "02")),
        ([1, 2, 3], (1, 2, 3)),
        ("123+a-b+c-d", ("123", "-", "b", "d", "+", "a", "c")),
        ("123+a.b-c.d+e.f-g.h", ("123", "-", "c", "d", "g", "h", "+", "a", "b", "e", "f")),
        ((1, 2, "+", "001", "-", "rc1", "+", "linux-x86", "-", 2), (1, 2, "-", "rc1", 2, "+", "001", "linux-x86")),
        ([1, "-", "a.b", "+", "a+b"], (1, "-", "a.b", "+", "a+b")),
    ]:
        asserts.equals(env, expected, versions.normalize_tuple(value), repr(value))
        asserts.equals(env, expected, versions.normalize_tuple(expected))
    value = "123+a.b-c.d+e.f-g.h"
    for sep, expected in [
        ("", "123-cdgh+abef"),
        (".", "123-c.d.g.h+a.b.e.f"),
        (None, "123-c-d-g-h+a+b+e+f"),
        ("/", "123-c/d/g/h+a/b/e/f"),
        ("auto", "123-cautodautogautoh+aautobautoeautof"),
        ("+-", "123-c+-d+-g+-h+a+-b+-e+-f"),
    ]:
        asserts.equals(env, expected, versions.normalize_string(value, sep = sep))
        asserts.equals(env, expected, versions.normalize_string(versions.normalize_tuple(value), sep = sep))
    for value, expected in [
        ("", ""),
        ([], ""),
        ("001.02+001", "001.02+001"),
        ((1, 2, 3, "-", "rc1", "+", "linux-x86", "001"), "1.2.3-rc1+linux-x86.001"),
        ("1.2+meta", "1.2+meta"),
        ("1.2-rc", "1.2-rc"),
    ]:
        asserts.equals(env, expected, versions.normalize_string(value))
    asserts.equals(env, "1.2.3-rc1+001", versions.normalize_string((1, 2, 3, "-", "rc", 1, "+", "001"), sep = ""))
    for sep in ["", None, "/"]:
        asserts.equals(env, "1.2.3", versions.normalize_string((1, 2, 3), sep = sep))
    for sep, expected in [
        ({"+": ".", "-": None}, "123-c-d-g-h+a.b.e.f"),
        ({"+": "/", "-": ""}, "123-cdgh+a/b/e/f"),
        ({"+": None, "-": "."}, "123-c.d.g.h+a+b+e+f"),
    ]:
        asserts.equals(env, expected, versions.normalize_string("123+a.b-c.d+e.f-g.h", sep = sep))
    for prefix, sep, expected in [
        ("#", ".", "123#a.b.c.d.e.f.g.h"),
        ("#", None, "123#a#b#c#d#e#f#g#h"),
        ("#", "", "123#abcdefgh"),
        ("", ".", "123a.b.c.d.e.f.g.h"),
        ("", None, "123abcdefgh"),
        ("+", ".", "123+a.b.c.d.e.f.g.h"),
        ("-", ".", "123-a.b.c.d.e.f.g.h"),
        ("suffix:", "/", "123suffix:a/b/c/d/e/f/g/h"),
    ]:
        asserts.equals(env, expected, versions.normalize_string("123+a.b-c.d+e.f-g.h", prefix = prefix, sep = sep))
        asserts.equals(env, expected, versions.normalize_string((123, "+", "a", "b", "-", "c", "d", "+", "e", "f", "-", "g", "h"), prefix = prefix, sep = sep))
    asserts.equals(env, "1.2", versions.normalize_string((1, 2), prefix = "#"))
    asserts.equals(env, "", versions.normalize_string([], prefix = "#"))
    asserts.equals(env, "1#rc1.rc1.001", versions.normalize_string((1, "-", "rc1", "rc1", "+", "001"), prefix = "#"))
    separators = {"+": ".", "-": None}
    versions.normalize_string("1-a.b+c.d", sep = separators)
    asserts.equals(env, {"+": ".", "-": None}, separators)
    original = [1, "+", "001", "-", "rc"]
    versions.normalize_tuple(original)
    versions.normalize_string(original)
    asserts.equals(env, [1, "+", "001", "-", "rc"], original)
    for mode in ["legacy", "semver", "pep440"]:
        api = versions.with_mode(mode)
        asserts.equals(env, versions.normalize_tuple(original), api.normalize_tuple(original))
        asserts.equals(env, "123-b.d+a.c", api.normalize_string("123+a-b+c-d"))
    semver = versions.with_mode("semver")
    asserts.equals(env, "23.1.0-rc1+linux", semver.normalize_string(tuple(semver.parse("23.1.0-rc1+linux"))))
    return unittest.end(env)

_normalize_test = unittest.make(_normalize_test_impl)

def _invalid_impl(ctx):
    case = ctx.attr.case
    if case == "input":
        versions.normalize_tuple(123)
    elif case == "component":
        versions.normalize_tuple([1, True])
    elif case == "nested":
        versions.normalize_tuple([1, [2]])
    elif case == "sep":
        versions.normalize_string("1", sep = False)
    elif case == "prefix":
        versions.normalize_string("1", prefix = False)
    elif case == "shared_mapping":
        versions.normalize_string("1-a+b", prefix = "#", sep = {"+": ".", "-": "."})
    elif case == "missing_key":
        versions.normalize_string("1", sep = {"-": "."})
    elif case == "extra_key":
        versions.normalize_string("1", sep = {"#": ".", "+": ".", "-": "."})
    elif case == "mapping_value":
        versions.normalize_string("1", sep = {"+": ".", "-": 1})
    elif case == "empty_component":
        versions.normalize_tuple([1, ""])
    elif case == "empty_group":
        versions.normalize_tuple([1, "+", "-", "rc"])
    elif case == "trailing_group":
        versions.normalize_tuple([1, "+"])
    else:
        versions.normalize_string(ctx.attr.value)
    return []

_invalid = rule(implementation = _invalid_impl, attrs = {"case": attr.string(), "value": attr.string()})

def _failure_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, ctx.attr.error)
    return analysistest.end(env)

_failure_test = analysistest.make(_failure_test_impl, expect_failure = True, attrs = {"error": attr.string()})

def normalize_test_suite(name = "normalize"):
    """Instantiates grouping/rendering and invalid-input tests.

    Args:
        name: Prefix for test targets.
    """
    _normalize_test(name = name + "_test")
    for case, value, error in [
        ("input", "", "requires a string, list, or tuple"),
        ("component", "", "must be strings or integers"),
        ("nested", "", "must be strings or integers"),
        ("sep", "", "sep must be a string, None, or dict"),
        ("prefix", "", "prefix must be a string or None"),
        ("shared_mapping", "", "cannot combine a shared prefix with a sep dict"),
        ("missing_key", "", "requires exactly '-' and '+' keys"),
        ("extra_key", "", "requires exactly '-' and '+' keys"),
        ("mapping_value", "", "sep values must be strings or None"),
        ("empty_component", "", "non-empty components"),
        ("empty_group", "", "non-empty components/groups"),
        ("trailing_group", "", "non-empty components/groups"),
        ("empty_dot", "1..2", "non-empty components"),
        ("leading_marker", "+a", "non-empty components"),
        ("trailing_marker", "1+", "non-empty components"),
        ("repeated_marker", "1--rc", "non-empty components"),
    ]:
        fixture = name + "_invalid_" + case
        _invalid(name = fixture, case = case, value = value, tags = ["manual"])
        _failure_test(name = fixture + "_test", target_under_test = ":" + fixture, error = error)
