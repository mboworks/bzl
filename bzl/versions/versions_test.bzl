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

"""Unit tests for versions.bzl."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts", "unittest")
load("//bzl/versions:versions.bzl", "versions")

def _assert_eq(env, result, expected, msg = None):
    asserts.equals(env, expected, result, msg)

def _versions_parse_test(ctx):
    """Unit tests for `versions.parse`."""
    env = unittest.begin(ctx)

    _assert_eq(env, versions.parse("25"), [25])
    _assert_eq(env, versions.parse("25.33.42.bla"), [25, 33, 42, "bla"])
    _assert_eq(env, versions.parse(""), [])
    # Parsing '25.33.bla' does not work because 'bla' is not a number.
    # _assert_eq(env, versions.parse("25.33.bla"), [25, 33, 42, "bla"])

    _assert_eq(env, versions.parse(25), [25])
    _assert_eq(env, versions.parse("26"), [26])
    _assert_eq(env, versions.parse([27]), [27])
    _assert_eq(env, versions.parse((28)), [28])

    _assert_eq(env, versions.parse(("25", "33")), [25, 33])
    _assert_eq(env, versions.parse(("25", "33", "42", "bla")), [25, 33, 42, "bla"])

    _assert_eq(env, versions.parse("25.30.42-pre.release+build.fun"), [25, 30, 42, "-", "pre", "release", "+", "build", "fun"])
    _assert_eq(env, versions.parse("25.31.42-pre-release+build+fun"), [25, 31, 42, "-", "pre-release", "+", "build+fun"])
    _assert_eq(env, versions.parse("25.32.42-pre-release+build-fun"), [25, 32, 42, "-", "pre-release", "+", "build-fun"])
    _assert_eq(env, versions.parse("25.33.42+build.fun-foo.bar+baz"), [25, 33, 42, "+", "build", "fun-foo", "bar+baz"])
    _assert_eq(env, versions.parse("25.34.42+build-fun-foo.bar+baz"), [25, 34, 42, "+", "build-fun-foo", "bar+baz"])
    _assert_eq(env, versions.parse("25.35.42+build+fun-foo.bar+baz"), [25, 35, 42, "+", "build+fun-foo", "bar+baz"])

    _assert_eq(env, versions.parse("25.35.42-rc1.beta-11.alpha--111+rc1"), [25, 35, 42, "-", "rc", 1, "beta", 11, "alpha-", 111, "+", "rc1"])

    _assert_eq(env, versions.parse("25.30.42-pre+build"), [25, 30, 42, "-", "pre", "+", "build"])
    _assert_eq(env, versions.parse("25.30.42-pre+build", skip_build = False), [25, 30, 42, "-", "pre", "+", "build"])
    _assert_eq(env, versions.parse("25.30.42-pre+build", skip_build = True), [25, 30, 42, "-", "pre"])
    _assert_eq(env, versions.parse("25.30.42+build"), [25, 30, 42, "+", "build"])
    _assert_eq(env, versions.parse("25.30.42+build", skip_build = False), [25, 30, 42, "+", "build"])
    _assert_eq(env, versions.parse("25.30.42+build", skip_build = True), [25, 30, 42])

    return unittest.end(env)

def _test_cmp(env, lhs, rhs, expected, **kwargs):
    _assert_eq(env, versions.cmp(lhs, rhs, **kwargs), expected, "{lhs} <=> {rhs}".format(
        lhs = lhs,
        rhs = rhs,
    ))

def _test_op(env, lhs, op, rhs, expected, **kwargs):
    _assert_eq(env, versions.compare(lhs, op, rhs, **kwargs), expected, "{lhs} {op} {rhs}".format(
        lhs = lhs,
        op = op,
        rhs = rhs,
    ))

def _test_op_eq_cmp(env, lhs, op, rhs, **kwargs):
    cmp_result = versions.cmp(lhs, rhs, **kwargs)
    if op == ">=":
        expected = cmp_result >= 0
    elif op == "<=":
        expected = cmp_result <= 0
    elif op == ">":
        expected = cmp_result == 1
    elif op == "<":
        expected = cmp_result == -1
    elif op == "==":
        expected = cmp_result == 0
    elif op == "!=":
        expected = cmp_result != 0
    else:
        fail("Bad op '{op}'.".format(op = op))
    _assert_eq(env, versions.compare(lhs, op, rhs, **kwargs), expected, "{lhs} {op} {rhs}".format(
        lhs = lhs,
        op = op,
        rhs = rhs,
    ))

def _versions_cmp_test(ctx):
    """Unit tests for `versions.ge`."""
    env = unittest.begin(ctx)

    _test_cmp(env, 25, 25, 0)
    _test_cmp(env, 25, 42, -1)
    _test_cmp(env, 42, 25, 1)

    _test_cmp(env, "25.1", "25.1", 0)
    _test_cmp(env, "25.2", "25.1", 1)
    _test_cmp(env, "25.3", "25.4", -1)

    _test_cmp(env, "25", "25", 0)
    _test_cmp(env, "25", "25.0", -1)
    _test_cmp(env, "25.0", "25.0", 0)
    _test_cmp(env, "25.1", "25", 1)

    _test_cmp(env, "26.0", "26.0-rc1", 1)
    _test_cmp(env, "27.0-rc2", "27.0-rc1", 1)
    _test_cmp(env, "28.0-rc3", "28.0-rc4", -1)
    _test_cmp(env, "29.0-rc5", "29.0", -1)
    _test_cmp(env, "30.0-rc1", "30.0-rc1", 0)

    _test_cmp(env, "31.0-alpha", "31.0-alpha", 0)
    _test_cmp(env, "32.0-alpha", "32.0-beta", -1)
    _test_cmp(env, "33.0-alpha", "33.0-rc", -1)
    _test_cmp(env, "34.0-beta", "34.0-alpha", 1)
    _test_cmp(env, "35.0-beta", "35.0-beta", 0)
    _test_cmp(env, "36.0-beta", "36.0-rc", -1)
    _test_cmp(env, "37.0-rc", "37.0-alpha", 1)
    _test_cmp(env, "38.0-rc", "38.0-beta", 1)
    _test_cmp(env, "39.0-rc", "39.0-rc", 0)

    _test_cmp(env, "40.0-rc", "40.0-0", 1)  # Number before Text
    _test_cmp(env, "41.0-0", "41.0-rc", -1)
    _test_cmp(env, "42.0-1", "42.0-2", -1)
    _test_cmp(env, "43.0-3", "43.0-3", 0)
    _test_cmp(env, "44.0-5", "44.0-4", 1)

    _test_cmp(env, "50.0-pre+build1", "50.0-pre+build0", 0)
    _test_cmp(env, "51.0-pre+build1", "51.0-pre+build0", 0, skip_build = True)
    _test_cmp(env, "52.0-pre+build1", "52.0-pre+build0", 1, skip_build = False)
    _test_cmp(env, "53.0-pre+build2", "53.0-pre+build2", 0, skip_build = False)
    _test_cmp(env, "54.0-pre+build3", "54.0-pre+build4", -1, skip_build = False)

    _test_cmp(env, "55.0+build1", "55.0+build0", 0)
    _test_cmp(env, "56.0+build1", "56.0+build0", 0, skip_build = True)
    _test_cmp(env, "57.0+build1", "57.0+build0", 1, skip_build = False)
    _test_cmp(env, "58.0+build2", "58.0+build2", 0, skip_build = False)
    _test_cmp(env, "59.0+build3", "59.0+build4", -1, skip_build = False)

    return unittest.end(env)

def _versions_ge_test(ctx):
    """Unit tests for `versions.ge`."""
    env = unittest.begin(ctx)

    _test_op(env, 25, ">=", 25, True)
    _test_op(env, 25, ">=", 42, False)
    _test_op(env, 42, ">=", 25, True)

    _test_op(env, "25.1", ">=", "25.1", True)
    _test_op(env, "25.2", ">=", "25.1", True)
    _test_op(env, "25.3", ">=", "25.4", False)

    _test_op(env, "25", ">=", "25", True)
    _test_op(env, "25", ">=", "25.0", False)
    _test_op(env, "25.0", ">=", "25.0", True)
    _test_op(env, "25.1", ">=", "25", True)

    _test_op(env, "26.0", ">=", "26.0-rc1", True)
    _test_op(env, "27.0-rc2", ">=", "27.0-rc1", True)
    _test_op(env, "28.0-rc3", ">=", "28.0-rc4", False)
    _test_op(env, "29.0-rc5", ">=", "29.0", False)
    _test_op(env, "30.0-rc1", ">=", "30.0-rc1", True)

    _test_op(env, "31.0-alpha", ">=", "31.0-alpha", True)
    _test_op(env, "32.0-alpha", ">=", "32.0-beta", False)
    _test_op(env, "33.0-alpha", ">=", "33.0-rc", False)
    _test_op(env, "34.0-beta", ">=", "34.0-alpha", True)
    _test_op(env, "35.0-beta", ">=", "35.0-beta", True)
    _test_op(env, "36.0-beta", ">=", "36.0-rc", False)
    _test_op(env, "37.0-rc", ">=", "37.0-alpha", True)
    _test_op(env, "38.0-rc", ">=", "38.0-beta", True)
    _test_op(env, "39.0-rc", ">=", "39.0-rc", True)

    _test_op_eq_cmp(env, "55.0+build1", ">=", "55.0+build0")
    _test_op_eq_cmp(env, "56.0+build1", ">=", "56.0+build0", skip_build = True)
    _test_op_eq_cmp(env, "57.0+build1", ">=", "57.0+build0", skip_build = False)

    return unittest.end(env)

def _versions_gt_test(ctx):
    """Unit tests for `versions.gt`."""
    env = unittest.begin(ctx)

    _test_op(env, 25, ">", 25, False)
    _test_op(env, 25, ">", 42, False)
    _test_op(env, 42, ">", 25, True)

    _test_op(env, "25.1", ">", "25.1", False)
    _test_op(env, "25.2", ">", "25.1", True)
    _test_op(env, "25.3", ">", "25.4", False)

    _test_op(env, "25", ">", "25", False)
    _test_op(env, "25", ">", "25.0", False)
    _test_op(env, "25.0", ">", "25.0", False)
    _test_op(env, "25.1", ">", "25", True)

    _test_op(env, "26.0", ">", "26.0-rc1", True)
    _test_op(env, "27.0-rc2", ">", "27.0-rc1", True)
    _test_op(env, "28.0-rc3", ">", "28.0-rc4", False)
    _test_op(env, "29.0-rc5", ">", "29.0", False)
    _test_op(env, "30.0-rc1", ">", "30.0-rc1", False)

    _test_op(env, "31.0-alpha", ">", "31.0-alpha", False)
    _test_op(env, "32.0-alpha", ">", "32.0-beta", False)
    _test_op(env, "33.0-alpha", ">", "33.0-rc", False)
    _test_op(env, "34.0-beta", ">", "34.0-alpha", True)
    _test_op(env, "35.0-beta", ">", "35.0-beta", False)
    _test_op(env, "36.0-beta", ">", "36.0-rc", False)
    _test_op(env, "37.0-rc", ">", "37.0-alpha", True)
    _test_op(env, "38.0-rc", ">", "38.0-beta", True)
    _test_op(env, "39.0-rc", ">", "39.0-rc", False)

    _test_op_eq_cmp(env, "55.0+build1", ">", "55.0+build0")
    _test_op_eq_cmp(env, "56.0+build1", ">", "56.0+build0", skip_build = True)
    _test_op_eq_cmp(env, "57.0+build1", ">", "57.0+build0", skip_build = False)

    return unittest.end(env)

def _versions_le_test(ctx):
    """Unit tests for `versions.le`."""
    env = unittest.begin(ctx)

    _test_op(env, 25, "<=", 25, True)
    _test_op(env, 25, "<=", 42, True)
    _test_op(env, 42, "<=", 25, False)

    _test_op(env, "25.1", "<=", "25.1", True)
    _test_op(env, "25.2", "<=", "25.1", False)
    _test_op(env, "25.3", "<=", "25.4", True)

    _test_op(env, "25", "<=", "25", True)
    _test_op(env, "25", "<=", "25.0", True)
    _test_op(env, "25.0", "<=", "25.0", True)
    _test_op(env, "25.1", "<=", "25", False)

    _test_op(env, "26.0", "<=", "26.0-rc1", False)
    _test_op(env, "27.0-rc2", "<=", "27.0-rc1", False)
    _test_op(env, "28.0-rc3", "<=", "28.0-rc4", True)
    _test_op(env, "29.0-rc5", "<=", "29.0", True)
    _test_op(env, "30.0-rc1", "<=", "30.0-rc1", True)

    _test_op(env, "31.0-alpha", "<=", "31.0-alpha", True)
    _test_op(env, "32.0-alpha", "<=", "32.0-beta", True)
    _test_op(env, "33.0-alpha", "<=", "33.0-rc", True)
    _test_op(env, "34.0-beta", "<=", "34.0-alpha", False)
    _test_op(env, "35.0-beta", "<=", "35.0-beta", True)
    _test_op(env, "36.0-beta", "<=", "36.0-rc", True)
    _test_op(env, "37.0-rc", "<=", "37.0-alpha", False)
    _test_op(env, "38.0-rc", "<=", "38.0-beta", False)
    _test_op(env, "39.0-rc", "<=", "39.0-rc", True)

    _test_op_eq_cmp(env, "55.0+build1", "<=", "55.0+build0")
    _test_op_eq_cmp(env, "56.0+build1", "<=", "56.0+build0", skip_build = True)
    _test_op_eq_cmp(env, "57.0+build1", "<=", "57.0+build0", skip_build = False)

    return unittest.end(env)

def _versions_lt_test(ctx):
    """Unit tests for `versions.lt`."""
    env = unittest.begin(ctx)

    _test_op(env, 25, "<", 25, False)
    _test_op(env, 25, "<", 42, True)
    _test_op(env, 42, "<", 25, False)

    _test_op(env, "25.1", "<", "25.1", False)
    _test_op(env, "25.2", "<", "25.1", False)
    _test_op(env, "25.3", "<", "25.4", True)

    _test_op(env, "25", "<", "25", False)
    _test_op(env, "25", "<", "25.0", True)
    _test_op(env, "25.0", "<", "25.0", False)
    _test_op(env, "25.1", "<", "25", False)

    _test_op(env, "26.0", "<", "26.0-rc1", False)
    _test_op(env, "27.0-rc2", "<", "27.0-rc1", False)
    _test_op(env, "28.0-rc3", "<", "28.0-rc4", True)
    _test_op(env, "29.0-rc5", "<", "29.0", True)
    _test_op(env, "30.0-rc1", "<", "30.0-rc1", False)

    _test_op(env, "31.0-alpha", "<", "31.0-alpha", False)
    _test_op(env, "32.0-alpha", "<", "32.0-beta", True)
    _test_op(env, "33.0-alpha", "<", "33.0-rc", True)
    _test_op(env, "34.0-beta", "<", "34.0-alpha", False)
    _test_op(env, "35.0-beta", "<", "35.0-beta", False)
    _test_op(env, "36.0-beta", "<", "36.0-rc", True)
    _test_op(env, "37.0-rc", "<", "37.0-alpha", False)
    _test_op(env, "38.0-rc", "<", "38.0-beta", False)
    _test_op(env, "39.0-rc", "<", "39.0-rc", False)

    _test_op_eq_cmp(env, "55.0+build1", "<", "55.0+build0")
    _test_op_eq_cmp(env, "56.0+build1", "<", "56.0+build0", skip_build = True)
    _test_op_eq_cmp(env, "57.0+build1", "<", "57.0+build0", skip_build = False)

    return unittest.end(env)

def _versions_eq_test(ctx):
    """Unit tests for `versions.eq`."""
    env = unittest.begin(ctx)

    _test_op(env, 25, "==", 25, True)
    _test_op(env, 25, "==", 42, False)
    _test_op(env, 42, "==", 25, False)

    _test_op(env, "25.1", "==", "25.1", True)
    _test_op(env, "25.2", "==", "25.1", False)
    _test_op(env, "25.3", "==", "25.4", False)

    _test_op(env, "25", "==", "25", True)
    _test_op(env, "25", "==", "25.0", False)
    _test_op(env, "25.0", "==", "25.0", True)
    _test_op(env, "25.1", "==", "25", False)

    _test_op(env, "26.0", "==", "26.0-rc1", False)
    _test_op(env, "27.0-rc2", "==", "27.0-rc1", False)
    _test_op(env, "28.0-rc3", "==", "28.0-rc4", False)
    _test_op(env, "29.0-rc5", "==", "29.0", False)
    _test_op(env, "30.0-rc1", "==", "30.0-rc1", True)

    _test_op(env, "31.0-alpha", "==", "31.0-alpha", True)
    _test_op(env, "32.0-alpha", "==", "32.0-beta", False)
    _test_op(env, "33.0-alpha", "==", "33.0-rc", False)
    _test_op(env, "34.0-beta", "==", "34.0-alpha", False)
    _test_op(env, "35.0-beta", "==", "35.0-beta", True)
    _test_op(env, "36.0-beta", "==", "36.0-rc", False)
    _test_op(env, "37.0-rc", "==", "37.0-alpha", False)
    _test_op(env, "38.0-rc", "==", "38.0-beta", False)
    _test_op(env, "39.0-rc", "==", "39.0-rc", True)

    _test_op_eq_cmp(env, "55.0+build1", "==", "55.0+build0")
    _test_op_eq_cmp(env, "56.0+build1", "==", "56.0+build0", skip_build = True)
    _test_op_eq_cmp(env, "57.0+build1", "==", "57.0+build0", skip_build = False)

    return unittest.end(env)

def _versions_ne_test(ctx):
    """Unit tests for `versions.ne`."""
    env = unittest.begin(ctx)

    _test_op(env, 25, "!=", 25, False)
    _test_op(env, 25, "!=", 42, True)
    _test_op(env, 42, "!=", 25, True)

    _test_op(env, "25.1", "!=", "25.1", False)
    _test_op(env, "25.2", "!=", "25.1", True)
    _test_op(env, "25.3", "!=", "25.4", True)

    _test_op(env, "25", "!=", "25", False)
    _test_op(env, "25", "!=", "25.0", True)
    _test_op(env, "25.0", "!=", "25.0", False)
    _test_op(env, "25.1", "!=", "25", True)

    _test_op(env, "26.0", "!=", "26.0-rc1", True)
    _test_op(env, "27.0-rc2", "!=", "27.0-rc1", True)
    _test_op(env, "28.0-rc3", "!=", "28.0-rc4", True)
    _test_op(env, "29.0-rc5", "!=", "29.0", True)
    _test_op(env, "30.0-rc1", "!=", "30.0-rc1", False)

    _test_op(env, "31.0-alpha", "!=", "31.0-alpha", False)
    _test_op(env, "32.0-alpha", "!=", "32.0-beta", True)
    _test_op(env, "33.0-alpha", "!=", "33.0-rc", True)
    _test_op(env, "34.0-beta", "!=", "34.0-alpha", True)
    _test_op(env, "35.0-beta", "!=", "35.0-beta", False)
    _test_op(env, "36.0-beta", "!=", "36.0-rc", True)
    _test_op(env, "37.0-rc", "!=", "37.0-alpha", True)
    _test_op(env, "38.0-rc", "!=", "38.0-beta", True)
    _test_op(env, "39.0-rc", "!=", "39.0-rc", False)

    _test_op_eq_cmp(env, "55.0+build1", "!=", "55.0+build0")
    _test_op_eq_cmp(env, "56.0+build1", "!=", "56.0+build0", skip_build = True)
    _test_op_eq_cmp(env, "57.0+build1", "!=", "57.0+build0", skip_build = False)

    return unittest.end(env)

def _versions_parse_requirements_test(ctx):
    """Unit tests for `versions.parse_requirements`."""
    env = unittest.begin(ctx)

    _assert_eq(env, versions.parse_requirements("25"), [struct(op = "==", version = [25])])
    _assert_eq(env, versions.parse_requirements("<=26"), [struct(op = "<=", version = [26])])
    _assert_eq(env, versions.parse_requirements(">=27.1,<=28.1.2"), [
        struct(op = ">=", version = [27, 1]),
        struct(op = "<=", version = [28, 1, 2]),
    ])
    _assert_eq(env, versions.parse_requirements(" >= 29.1 , <= 29.1.2.bla "), [
        struct(op = ">=", version = [29, 1]),
        struct(op = "<=", version = [29, 1, 2, "bla"]),
    ])

    return unittest.end(env)

def _versions_check_one_requirement_test(ctx):
    """Unit tests for `versions.check_one_requirement`."""
    env = unittest.begin(ctx)

    _assert_eq(env, versions.check_one_requirement("25", "25"), True)
    _assert_eq(env, versions.check_one_requirement([26], "42"), False)
    _assert_eq(env, versions.check_one_requirement(27, ">=26"), True)
    _assert_eq(env, versions.check_one_requirement(28, "<=26"), False)
    _assert_eq(env, versions.check_one_requirement([29, 0], "<=29"), False)
    _assert_eq(env, versions.check_one_requirement([30, 0, 0], "<30"), False)
    _assert_eq(env, versions.check_one_requirement([31, 0], ">31"), True)
    _assert_eq(env, versions.check_one_requirement([31, 0], ">31"), True)
    _assert_eq(env, versions.check_one_requirement([32, 0], ">=32.0-rc1"), True)
    return unittest.end(env)

def _versions_check_all_requirements_test(ctx):
    """Unit tests for `versions.check_all_requirements`."""
    env = unittest.begin(ctx)

    _assert_eq(env, versions.check_all_requirements("25", ["25"]), True)
    _assert_eq(env, versions.check_all_requirements("33", ["25", "33", "42"]), False)
    _assert_eq(env, versions.check_all_requirements("42", ["42", "42", "42"]), True)

    _assert_eq(env, versions.check_all_requirements("34", [">=25", "!=34", "<42"]), False)
    _assert_eq(env, versions.check_all_requirements("35", [">=25", "!=34", "<42"]), True)

    _assert_eq(env, versions.check_all_requirements("36", [
        struct(op = ">=", version = 25),
        struct(op = "!=", version = 34),
        struct(op = "<", version = 42),
    ]), True)

    _assert_eq(env, versions.check_all_requirements("37", [
        struct(op = ">=", version = 25),
        struct(op = "!=", version = 37),
        struct(op = "<", version = 42),
    ]), False)

    return unittest.end(env)

def _versions_semver_precedence_test(ctx):
    env = unittest.begin(ctx)

    # The complete ascending example from SemVer 2.0.0, section 11.
    ordered = [
        "1.0.0-alpha",
        "1.0.0-alpha.1",
        "1.0.0-alpha.beta",
        "1.0.0-beta",
        "1.0.0-beta.2",
        "1.0.0-beta.11",
        "1.0.0-rc.1",
        "1.0.0",
    ]
    for left_index, left in enumerate(ordered):
        for right_index, right in enumerate(ordered):
            expected = int(left_index > right_index) - int(left_index < right_index)
            _test_cmp(env, left, right, expected, mode = "semver")
            for op, result in [("==", expected == 0), ("!=", expected != 0), ("<", expected < 0), ("<=", expected <= 0), (">", expected > 0), (">=", expected >= 0)]:
                _test_op(env, left, op, right, result, mode = "semver")
    for left, right, expected in [
        ("1.2", "1.2.0", 0),
        ("1.2", "1.2.0.0", 0),
        ("1.2-rc.1", "1.2.0-rc.1", 0),
        ("1.2-rc1", "1.2.0-rc.1", 1),
        ("1.2-rc10", "1.2-rc2", -1),
        ("1.2-A", "1.2-a", -1),
        ("1.2--", "1.2-0", 1),
        ("1.2-0", "1.2", -1),
        ("1.2+build.1", "1.2.0+build.2", 0),
    ]:
        _test_cmp(env, left, right, expected, mode = "semver")
        _test_cmp(env, right, left, -expected, mode = "semver")
        _assert_eq(env, versions.check_one_requirement(left, "==" + right, mode = "semver"), expected == 0)
        _assert_eq(env, versions.check_all_requirements(left, versions.parse_requirements("==" + right, mode = "semver"), mode = "semver"), expected == 0)
    _assert_eq(env, versions.parse("1-rc.1+build.2", mode = "semver"), [1, "-", "rc", 1, "+", "build", 2])
    return unittest.end(env)

def _versions_modes_test(ctx):
    env = unittest.begin(ctx)
    for mode, equal, parsed, lexical in [
        ("legacy", False, [1, 2, 3, "-", "rc", 1], False),
        ("semver", True, [1, 2, 3, "-", "rc1"], True),
    ]:
        _assert_eq(env, versions.eq("1.2", "1.2.0", mode = mode), equal)
        _assert_eq(env, versions.ne("1.2", "1.2.0", mode = mode), not equal)
        _assert_eq(env, versions.parse("1.2.3-rc1", mode = mode), parsed)
        _assert_eq(env, versions.lt("1.2.3-rc10", "1.2.3-rc2", mode = mode), lexical)
        _assert_eq(env, versions.matches("1.2", "1.2.0", mode = mode), equal)
        _assert_eq(env, versions.compatible("1.2", "1.2.0", mode = mode), equal)
        _assert_eq(env, versions.check_one_requirement("1.2", "==1.2.0", mode = mode), equal)
        _assert_eq(env, versions.check_all_requirements("1.2", "==1.2.0", mode = mode), equal)
        _assert_eq(env, versions.check_all_requirements("1.2", ["==1.2.0"], mode = mode), equal)
        _assert_eq(env, versions.check_all_requirements("1.2", versions.parse_requirements("==1.2.0", mode = mode), mode = mode), equal)
        _assert_eq(env, versions.parse_requirements("~=1.2.3-rc1", mode = mode), [struct(op = "~=", version = parsed)])
    _assert_eq(env, versions.check_all_requirements("1.2.3", versions.parse_requirements("==1.2.*,!=1.2.4", mode = "semver"), mode = "semver"), True)
    _assert_eq(env, versions.parse_requirements(" ~= 1.4.5-rc1 , != 1.4.6 ", mode = "semver"), [
        struct(op = "~=", version = [1, 4, 5, "-", "rc1"]),
        struct(op = "!=", version = [1, 4, 6]),
    ])
    return unittest.end(env)

def _versions_components_test(ctx):
    env = unittest.begin(ctx)
    for version, count, expected in [
        ("1.2.3.4", 2, "1.2"),
        ("1.2", 4, "1.2"),
        ("1.2.3-rc.1+build.7", 2, "1.2"),
        ("1.2.3-rc.1+build.7", 5, "1.2.3"),
        ("1.2.3", 0, ""),
        ("", 2, ""),
        (1, 3, "1"),
        ([1, 2, 3], 2, "1.2"),
        ((1, 2, 3), 2, "1.2"),
    ]:
        _assert_eq(env, versions.prefix(version, count), expected, "prefix({}, {})".format(version, count))
    for version, start, end, pad, expected in [
        ("1.2.3.4", 0, 2, False, "1.2"),
        ("1.2.3.4", 1, 3, False, "2.3"),
        ("1.2", 0, 4, False, "1.2"),
        ("1.2", 0, 4, True, "1.2.0.0"),
        ("1.2.3", 1, 4, True, "2.3.0"),
        ("1.2", 3, 5, True, "0.0"),
        ("1.2", 3, 5, False, ""),
        ("1.2.3", 0, None, True, "1.2.3"),
        ("1.2.3", -2, None, False, "2.3"),
        ("1.2.3", 0, -1, False, "1.2"),
        ("1.2", -1, 4, True, "2.0.0"),
        ("1.2", -9, 1, False, "1"),
        ("1.2", 2, 1, True, ""),
        ("1.2.3-rc.1+build.7", 1, 4, True, "2.3.0"),
    ]:
        _assert_eq(
            env,
            versions.components(version, start = start, end = end, pad = pad),
            expected,
            "components({}, start={}, end={}, pad={})".format(version, start, end, pad),
        )
    return unittest.end(env)

def _versions_compatible_test(ctx):
    env = unittest.begin(ctx)
    for candidate, required, expected in [
        ("1.4.5", "1.4.0", True),
        ("1.5.0", "1.4.0", False),
        ("1.9.0", "1.4", True),
        ("2.0.0", "1.4", False),
        ("1.4.4", "1.4.5", False),
        ("1.4.5", "1.4.5", True),
        ("1.4.99", "1.4.5", True),
        ("1.4.5.9", "1.4.5.0", True),
        ("1.4.6", "1.4.5.0", False),
        ("1.4.6-rc.1", "1.4.5.0", False),
        ("0.9.0", "0.4", True),
        ("1.0.0", "0.4", False),
        ("0.5.0", "0.4.0", False),
        ("1.4", "1.4.0", True),
        ("1.4.0", "1.4", True),
        (1, "1.0", True),
        ("1.4.0.0", "1.4.0", True),
        ("1.4.5+candidate", "1.4.5+required", True),
        ("1.4.5-rc.1", "1.4.5", False),
        ("1.4.5", "1.4.5-rc.1", True),
        ("1.4.5-rc.2", "1.4.5-rc.1", True),
        ("1.4.5-rc.0", "1.4.5-rc.1", False),
        ("1.4.6-rc.1", "1.4.5", True),
        ("1.5.0-rc.1", "1.4.5", False),
        # SemVer compares alphanumeric identifiers lexically, not by suffix number.
        ("1.4.5-rc1", "1.4.5-rc.1", True),
        ("1.4.5-rc.1", "1.4.5-rc1", False),
        ("1.4.5-rc10", "1.4.5-rc2", False),
        ("1.4.5-alpha", "1.4.5-0", True),
        ("1.4.5--", "1.4.5-0", True),
        ("1.4.5-0", "1.4.5--", False),
        ("1.4.5-alpha.1", "1.4.5-alpha", True),
        ("1.4.5-alpha", "1.4.5-alpha.1", False),
        ([1, 4, 5], [1, 4, 0], True),
        ((1, 5, 0), (1, 4, 0), False),
    ]:
        _assert_eq(env, versions.compatible(candidate, required), expected, "{} ~= {}".format(candidate, required))
        _test_op(env, candidate, "~=", required, expected, mode = "semver")
    _assert_eq(env, versions.compatible("1.4.5+build1", "1.4.5+build2", skip_build = False), False)
    _assert_eq(env, versions.check_one_requirement("1.4.5-rc.1", "~=1.4.5-rc1", mode = "semver"), False)
    _assert_eq(env, versions.check_all_requirements("1.4.5", "~=1.4,!=1.4.6"), True)
    _assert_eq(env, versions.check_all_requirements("1.4.6", "~=1.4,!=1.4.6"), False)
    _assert_eq(env, versions.check_all_requirements("1.4.5", versions.parse_requirements("~=1.4,!=1.4.6")), True)
    _assert_eq(env, versions.check_all_requirements("1.4.5-rc.1", versions.parse_requirements("~=1.4.5-rc1", mode = "semver"), mode = "semver"), False)
    return unittest.end(env)

def _versions_matches_test(ctx):
    env = unittest.begin(ctx)
    for candidate, pattern, expected in [
        ("1.2.3", "1.2.*", True),
        ("1.20.3", "1.2.*", False),
        ("1.3.0", "1.2.*", False),
        ("1.2", "1.2.*", True),
        ("1.2.0.0", "1.2.*", True),
        ("1.2.3.4", "1.2.3.*", True),
        ("1.2.4", "1.2.3.*", False),
        ("1", "1.0.*", True),
        ("1", "1.0.0.*", True),
        ("1", "1.1.*", False),
        ("0.9.0", "0.*", True),
        ("1.2.3-rc.1", "1.2.*", True),
        ("1.2.3-rc1+build.4", "1.2.*", True),
        ("1.2.3+build.4", "1.2.3.*", True),
        ([1, 2, 3], [1, 2, "*"], True),
        ((1, 2, 3), (1, 2, "*"), True),
    ]:
        _assert_eq(env, versions.matches(candidate, pattern), expected, "matches({}, {})".format(candidate, pattern))
        _assert_eq(env, versions.compare(candidate, "==", pattern), expected)
        _assert_eq(env, versions.compare(candidate, "!=", pattern), not expected)
        for requirement in ["==1.2.*", "!=1.2.*", "1.2.*"]:
            _assert_eq(
                env,
                versions.check_all_requirements(candidate, versions.parse_requirements(requirement)),
                versions.check_one_requirement(candidate, requirement),
            )
    for candidate, pattern, expected in [
        ("1.2", "1.2.0", True),
        ("1.2.0.0", "1.2", True),
        ("1.2.1", "1.2", False),
        ("1.2.0-rc.1", "1.2-rc.1", True),
        ("1.2.0-rc1", "1.2.0-rc.1", False),
        ("1.2.0-rc.1", "1.2.0", False),
        ("1.2.0", "1.2.0-rc.1", False),
        ("1.2.0+build.1", "1.2+build.2", True),
        ("1.2.0--", "1.2.0--", True),
        (1, "1.0", True),
    ]:
        _assert_eq(env, versions.matches(candidate, pattern), expected, "matches({}, {})".format(candidate, pattern))
    _assert_eq(env, versions.matches("1.2+one", "1.2+two", skip_build = False), False)
    _assert_eq(env, versions.matches("1.2+one", "1.2.*", skip_build = False), True)
    _assert_eq(env, versions.check_one_requirement("1.2.3", " == 1.2.* "), True)
    _assert_eq(env, versions.check_all_requirements("1.2.3", "==1.2.*,!=1.2.4"), True)
    _assert_eq(env, versions.check_all_requirements("1.2.3", "==1.2.*,!=1.2.3.*"), False)
    _assert_eq(env, versions.parse_requirements("==1.2.*,!=1.3.*"), [
        struct(op = "==", version = [1, 2, "*"]),
        struct(op = "!=", version = [1, 3, "*"]),
    ])
    return unittest.end(env)

def _versions_compatible_operators_test(ctx):
    env = unittest.begin(ctx)
    for candidate, required, expected in [
        ("1.2", "1.2", True),
        ("1.2.0", "1.2", True),
        ("1.1.9", "1.2", False),
        ("1.9.0", "1.2", True),
        ("2.0.0", "1.2", False),
        ("1.2-rc.1", "1.2", False),
        ("1.3-rc.1", "1.2", True),
        ("2.0-rc.1", "1.2", False),
        ("1.2.3-rc.1", "1.2.3-rc.1", True),
        ("1.2.3+build", "1.2.3", True),
        ("1.3.0", "1.2.3", False),
    ]:
        for op, result in [("~=", expected), ("!~=", not expected)]:
            _assert_eq(env, versions.compare(candidate, op, required, mode = "semver"), result)
            requirement = " {} {} ".format(op, required)
            _assert_eq(env, versions.check_one_requirement(candidate, requirement, mode = "semver"), result)
            _assert_eq(env, versions.check_all_requirements(candidate, versions.parse_requirements(requirement, mode = "semver"), mode = "semver"), result)
    for candidate, pattern, expected in [
        ("1.2", "1.2.*", True),
        ("1.2.0", "1.2.*", True),
        ("1.2.99", "1.2.*", True),
        ("1.1.99", "1.2.*", False),
        ("1.3", "1.2.*", False),
        ("1.20.0", "1.2.*", False),
        ("1.2-rc.1", "1.2.*", False),
        ("1.2.0-rc.1", "1.2.*", False),
        ("1.2.1-rc.1", "1.2.*", True),
        ("1.3-rc.1", "1.2.*", False),
        ("1.2+build", "1.2.*", True),
        ("1", "1.0.*", True),
        ("1.0", "1.*", True),
        ("2.0", "1.*", False),
        ("0.0", "0.*", True),
        ("0.0-rc.1", "0.*", False),
        ("1.2.3.0", "1.2.3.*", True),
        ("1.2.4", "1.2.3.*", False),
        ("1.2.3.4", "1.2.3.4.*", True),
        ("1.2.3.5", "1.2.3.4.*", False),
    ]:
        for op, result in [("~~=", expected), ("!~~=", not expected)]:
            _assert_eq(env, versions.compare(candidate, op, pattern, mode = "semver"), result)
            requirement = " {} {} ".format(op, pattern)
            _assert_eq(env, versions.check_one_requirement(candidate, requirement, mode = "semver"), result)
            parsed = versions.parse_requirements(requirement, mode = "semver")
            _assert_eq(env, versions.check_all_requirements(candidate, parsed, mode = "semver"), result)
    _assert_eq(env, versions.compare([1, 2, 3], "~~=", [1, 2, "*"], mode = "semver"), True)
    _assert_eq(env, versions.compare((1, 3), "!~~=", (1, 2, "*"), mode = "semver"), True)
    _assert_eq(env, versions.check_one_requirement("1.2-rc.1", "==1.2.*", mode = "semver"), True)
    _assert_eq(env, versions.check_all_requirements("1.2.4", "~~=1.2.*,!~=1.2.5", mode = "semver"), True)
    _assert_eq(env, versions.check_all_requirements("1.2.5", "~~=1.2.*,!~=1.2.5", mode = "semver"), False)
    _assert_eq(env, versions.parse_requirements("!~~=1.2.*,~~=2.3.*,!~=3.4,~=4.5", mode = "semver"), [
        struct(op = "!~~=", version = [1, 2, "*"]),
        struct(op = "~~=", version = [2, 3, "*"]),
        struct(op = "!~=", version = [3, 4]),
        struct(op = "~=", version = [4, 5]),
    ])
    for mode in ["legacy", "semver"]:
        _assert_eq(env, versions.check_one_requirement("1.2.3", "~~=1.2.*", mode = mode), True)
        _assert_eq(env, versions.check_one_requirement("1.2.3", "!~~=1.2.*", mode = mode), False)
        _assert_eq(env, versions.check_one_requirement("1.2.3", "!~=1.2", mode = mode), False)
    return unittest.end(env)

def _versions_named_components_test(ctx):
    env = unittest.begin(ctx)
    for mode in ["legacy", "semver"]:
        for candidate, requirement, expected in [
            ("23.2.1", "major==23,minor>=2", True),
            ("23.1.9", "major==23,minor>=2", False),
            ("24.2.1", "major==23,minor>=2", False),
            ("23.2.1", "major!=24,minor<3,patch<=1", True),
            ("23.2.1", "patch>1", False),
            ("23.2.1.9", "patch==1", True),
            ("23", "minor==0,patch==0", True),
            ("23.2", "patch==0", True),
            ("23.2.1-rc1+build", " major == 23 , minor >= 2 , patch == 1 ", True),
            ([23, 2, 1], "major==23,minor>=2", True),
            ((23, 2, 1), "patch==1", True),
        ]:
            _assert_eq(env, versions.check_all_requirements(candidate, requirement, mode = mode), expected, "{}: {} {}".format(mode, candidate, requirement))
            parsed = versions.parse_requirements(requirement, mode = mode)
            _assert_eq(env, versions.check_all_requirements(candidate, parsed, mode = mode), expected)
        _assert_eq(env, versions.check_one_requirement("23.2.1", "minor>=2", mode = mode), True)
        _assert_eq(env, versions.check_all_requirements("23.2.1", ["major==23", "minor>=2", ">=23.2.0"], mode = mode), True)
        _assert_eq(env, versions.parse_requirements("major==23,minor>=2,patch!=1,>=23.2", mode = mode), [
            struct(component = "major", op = "==", version = [23]),
            struct(component = "minor", op = ">=", version = [2]),
            struct(component = "patch", op = "!=", version = [1]),
            struct(op = ">=", version = [23, 2]),
        ])
    return unittest.end(env)

def _versions_functions_test(ctx):
    env = unittest.begin(ctx)
    for version, expected in [("23.2.1", [23, 2, 1]), ("23", [23, 0, 0]), ("23.2", [23, 2, 0]), ("23.2.1.9-rc1+build", [23, 2, 1]), ([23, 2, 1], [23, 2, 1])]:
        _assert_eq(env, [versions.major(version), versions.minor(version), versions.patch(version)], expected)
    for candidate, clause, expected in [
        ("23.2.1", "major()==23,minor()>=2", True),
        ("23.1.9", "major()==23,minor()>=2", False),
        ("23.2.1", "prefix(2)==23.2", True),
        ("23.2.1", "prefix(count=2)==23.2", True),
        ("23.2.1", 'prefix("24.3.2", 2)==24.3', True),
        ("23.2.1", "prefix('24.3.2', count=2)==24.3", True),
        ("23.2.1", 'prefix(version="24.3.2", count=2)==24.3', True),
        ("23.2.1", "components(start=1,end=3)==2.1", True),
        ("23.2.1", "components(start=-2,end=-1)==2", True),
        ("23.2", "components(end=3,pad=True)==23.2.0", True),
        ("23.2.1", "components()==23.2.1", True),
        ("23.2.1", 'components("24.3.2", start=1, end=3)==3.2', True),
        ("23.2.1", "major(prefix(2))==23", True),
        ("23.2.1", "prefix(components(start=1,end=3),1)==2", True),
        ("23.2.1", 'major(version="24.3")==24', True),
        ("23.2.1", 'minor("24.3")==3', True),
        ("23.2.1", "prefix(2)~=23.1", True),
        ("23.2.1", "prefix(2)~~=23.*", True),
        ("23.2.1", "components(start=1,end=None)==2.1", True),
    ]:
        for mode in ["legacy", "semver"]:
            _assert_eq(env, versions.check_all_requirements(candidate, clause, mode = mode), expected, "{}: {} {}".format(mode, candidate, clause))
            _assert_eq(env, versions.check_all_requirements(candidate, versions.parse_requirements(clause, mode = mode), mode = mode), expected)
    _assert_eq(env, versions.parse_requirements("major()==23"), versions.parse_requirements("major==23"))
    return unittest.end(env)

def _invalid_version_operation_impl(ctx):
    if ctx.attr.operation == "compatible":
        versions.compatible("1.4.5", ctx.attr.required)
    elif ctx.attr.operation == "extended":
        versions.check_one_requirement("1.2.3", ctx.attr.required, mode = "semver")
    elif ctx.attr.operation == "extended_parsed":
        versions.parse_requirements(ctx.attr.required, mode = "semver")
    elif ctx.attr.operation == "mode":
        versions.parse("1.2.3", mode = "unknown")
    elif ctx.attr.operation == "matches":
        versions.matches("1.2.3", ctx.attr.required)
    elif ctx.attr.operation == "compare":
        versions.compare("1.2.3", ">=", ctx.attr.required)
    elif ctx.attr.operation == "prefix":
        versions.prefix("1.2", -1)
    else:
        versions.components("1.2", start = "1")
    return []

_invalid_version_operation = rule(
    implementation = _invalid_version_operation_impl,
    attrs = {
        "operation": attr.string(),
        "required": attr.string(),
    },
)

def _invalid_version_operation_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, ctx.attr.expected_error)
    return analysistest.end(env)

_invalid_version_operation_test = analysistest.make(
    _invalid_version_operation_test_impl,
    expect_failure = True,
    attrs = {"expected_error": attr.string()},
)

versions_parse_test = unittest.make(_versions_parse_test)
versions_components_test = unittest.make(_versions_components_test)
versions_compatible_test = unittest.make(_versions_compatible_test)
versions_matches_test = unittest.make(_versions_matches_test)
versions_semver_precedence_test = unittest.make(_versions_semver_precedence_test)
versions_modes_test = unittest.make(_versions_modes_test)
versions_compatible_operators_test = unittest.make(_versions_compatible_operators_test)
versions_named_components_test = unittest.make(_versions_named_components_test)
versions_functions_test = unittest.make(_versions_functions_test)
versions_ge_test = unittest.make(_versions_ge_test)
versions_gt_test = unittest.make(_versions_gt_test)
versions_le_test = unittest.make(_versions_le_test)
versions_lt_test = unittest.make(_versions_lt_test)
versions_eq_test = unittest.make(_versions_eq_test)
versions_ne_test = unittest.make(_versions_ne_test)
versions_cmp_test = unittest.make(_versions_cmp_test)
versions_parse_requirements_test = unittest.make(_versions_parse_requirements_test)
versions_check_one_requirement_test = unittest.make(_versions_check_one_requirement_test)
versions_check_all_requirements_test = unittest.make(_versions_check_all_requirements_test)

def versions_test_suite(name = "versions_tests"):
    """Creates version test targets, including invalid-input analysis tests.

    Args:
        name: Name of the unit test suite and prefix for invalid-input fixtures.
    """
    unittest.suite(
        name,
        versions_parse_test,
        versions_components_test,
        versions_compatible_test,
        versions_matches_test,
        versions_semver_precedence_test,
        versions_modes_test,
        versions_compatible_operators_test,
        versions_named_components_test,
        versions_functions_test,
        versions_ge_test,
        versions_gt_test,
        versions_le_test,
        versions_lt_test,
        versions_eq_test,
        versions_ne_test,
        versions_cmp_test,
        versions_parse_requirements_test,
        versions_check_one_requirement_test,
        versions_check_all_requirements_test,
    )
    for case, operation, required, expected_error in [
        ("single_component", "compatible", "1", "at least two release components"),
        ("empty_requirement", "compatible", "", "non-negative numeric release components"),
        ("nonnumeric_requirement", "compatible", "1.a", "non-negative numeric release components"),
        ("wildcard_only", "matches", "*", "single trailing '.*'"),
        ("embedded_wildcard", "matches", "1.*.3", "single trailing '.*'"),
        ("partial_wildcard", "matches", "1.2*", "single trailing '.*'"),
        ("multiple_wildcards", "matches", "1.*.*", "single trailing '.*'"),
        ("prerelease_wildcard", "matches", "1.2-rc.*", "single trailing '.*'"),
        ("build_wildcard", "matches", "1.2+build.*", "single trailing '.*'"),
        ("wildcard_build", "matches", "1.2.*+build", "single trailing '.*'"),
        ("ordered_wildcard", "compare", "1.2.*", "only support"),
        ("compatible_wildcard", "compatible", "1.2.*", "non-negative numeric release components"),
        ("empty_prerelease", "matches", "1.2.3-", "non-empty SemVer identifiers"),
        ("empty_build", "matches", "1.2.3+", "non-empty SemVer identifiers"),
        ("invalid_prerelease", "matches", "1.2.3-rc_1", "non-empty SemVer identifiers"),
        ("prerelease_leading_zero", "matches", "1.2.3-01", "must not have leading zeros"),
        ("release_leading_zero", "matches", "01.2.3", "must not have leading zeros"),
        ("extended_exact", "extended", "~~=1.2", "single trailing '.*'"),
        ("extended_negated_exact", "extended", "!~~=1.2", "single trailing '.*'"),
        ("extended_parsed_exact", "extended_parsed", "~~=1.2", "single trailing '.*'"),
        ("extended_parsed_negated_exact", "extended_parsed", "!~~=1.2", "single trailing '.*'"),
        ("extended_interior", "extended", "~~=1.*.2", "single trailing '.*'"),
        ("extended_partial", "extended", "!~~=1.2*", "single trailing '.*'"),
        ("extended_empty", "extended", "~~=", "single trailing '.*'"),
        ("extended_bare", "extended", "!~~=*", "single trailing '.*'"),
        ("compatible_negated_single", "extended", "!~=1", "at least two release components"),
        ("compatible_negated_wildcard", "extended", "!~=1.2.*", "only support"),
        ("compatible_negated_parsed_wildcard", "extended_parsed", "!~=1.2.*", "only support"),
        ("named_missing_operator", "extended_parsed", "major23", "requires =="),
        ("named_single_equals", "extended_parsed", "major=23", "requires =="),
        ("named_compatible", "extended_parsed", "minor~=2.1", "requires =="),
        ("named_extended", "extended_parsed", "patch~~=2.*", "requires =="),
        ("named_wildcard", "extended_parsed", "major==23.*", "non-negative integer operand"),
        ("named_multiple_parts", "extended_parsed", "minor>=23.2", "non-negative integer operand"),
        ("named_suffix", "extended_parsed", "patch==1-rc1", "non-negative integer operand"),
        ("named_negative", "extended_parsed", "minor>=-1", "non-negative integer operand"),
        ("named_empty", "extended_parsed", "major==", "non-negative integer operand"),
        ("function_unknown", "extended", "unknown()==23", "Unknown version function"),
        ("function_unbalanced", "extended", "prefix(2==23", "Unbalanced version expression"),
        ("function_duplicate_keyword", "extended", "prefix(count=2,count=3)==23", "duplicate version function keyword"),
        ("function_positional_after_keyword", "extended", "prefix(count=2,3)==23", "must precede"),
        ("function_empty_argument", "extended", "prefix(,2)==23", "Invalid version function argument"),
        ("function_mode_override", "extended", "major(mode='legacy')==23", "version function keyword"),
        ("function_expression", "extended", "prefix(1+1)==23", "arguments must be"),
        ("function_string_unclosed", "extended", "major('23)==23", "Unbalanced version expression"),
        ("function_bad_count", "extended", "prefix(-1)==23", "non-negative integer"),
        ("function_nonliteral", "extended", "prefix(variable)==23", "arguments must be"),
        ("unknown_mode", "mode", "", "Version mode must be"),
        ("negative_prefix", "prefix", "", "non-negative integer"),
        ("invalid_index", "components", "", "Component indices must be integers"),
    ]:
        fixture = name + "_" + case
        _invalid_version_operation(
            name = fixture,
            operation = operation,
            required = required,
            tags = ["manual"],
        )
        _invalid_version_operation_test(
            name = fixture + "_test",
            target_under_test = ":" + fixture,
            expected_error = expected_error,
        )
