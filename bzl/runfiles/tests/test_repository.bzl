# SPDX-FileCopyrightText: Copyright (c) M. Boerger, the MBO Works authors
# SPDX-License-Identifier: Apache-2.0
"""An external repository with a different apparent and canonical name."""

def _fixture_impl(ctx):
    ctx.file("MODULE.bazel", "module(name = 'runfiles_fixture')\n")
    ctx.file("source.txt", "runfiles fixture\n")
    ctx.file("BUILD.bazel", """
load(%r, "generated", "keys_test", "tool")
package(default_visibility = ["//visibility:public"])
exports_files(["source.txt"])
generated(name = "generated")
tool(name = "tool")
keys_test(
    name = "external_context_test",
    data = [":source.txt", ":generated", %r],
    tool = ":tool",
)
""" % (str(ctx.attr._rules), str(ctx.attr._main_source)))

fixture_repository = repository_rule(
    implementation = _fixture_impl,
    attrs = {
        "_main_source": attr.label(default = Label(":source.txt")),
        "_rules": attr.label(default = Label(":runfiles_test.bzl")),
    },
)
