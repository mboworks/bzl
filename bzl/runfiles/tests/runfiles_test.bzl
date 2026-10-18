# SPDX-FileCopyrightText: Copyright (c) M. Boerger, the MBO Works authors
# SPDX-License-Identifier: Apache-2.0
"""Real-file tests against Bazel's own rlocationpath expansion."""

load("@bazel_skylib//lib:shell.bzl", "shell")
load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//bzl/runfiles:runfiles.bzl", "runfiles")

def _generated_impl(ctx):
    output = ctx.actions.declare_file(ctx.label.name + ".txt")
    ctx.actions.write(output, "runfiles fixture\n")
    return [DefaultInfo(files = depset([output]))]

generated = rule(implementation = _generated_impl)

def _tool_impl(ctx):
    output = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.write(output, "#!/usr/bin/env bash\nprintf 'runfiles tool\n'\n", is_executable = True)
    return [DefaultInfo(executable = output, runfiles = ctx.runfiles(files = [output]))]

tool = rule(implementation = _tool_impl, executable = True)

def _keys_test_impl(ctx):
    env = unittest.begin(ctx)
    for target in ctx.attr.data + [ctx.attr.tool]:
        file = target[DefaultInfo].files.to_list()[0]
        expected = ctx.expand_location("$(rlocationpath %s)" % target.label, targets = [target])
        asserts.equals(env, expected, runfiles.key(ctx, file), str(target.label))
    asserts.equals(env, runfiles.key(ctx, ctx.file.original), runfiles.key(ctx, ctx.file.alias))
    asserts.equals(env, runfiles.key(ctx, ctx.executable.tool), runfiles.key(ctx, ctx.attr.tool[DefaultInfo].files_to_run.executable))
    return unittest.end(env)

keys_test = unittest.make(_keys_test_impl, attrs = {
    "alias": attr.label(default = Label(":aliased_source"), allow_single_file = True),
    "data": attr.label_list(allow_files = True),
    "original": attr.label(default = Label("@runfiles_fixture//:source.txt"), allow_single_file = True),
    "tool": attr.label(executable = True, cfg = "exec", mandatory = True),
})

def _lookup_test_impl(ctx):
    output = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.expand_template(
        template = ctx.file._template,
        output = output,
        is_executable = True,
        substitutions = {
            "__KEYS__": " ".join([shell.quote(runfiles.key(ctx, file)) for file in ctx.files.data]),
            "__TOOL__": shell.quote(runfiles.key(ctx, ctx.executable.tool)),
        },
    )
    files = ctx.runfiles(files = ctx.files.data + [ctx.executable.tool])
    files = files.merge_all([
        ctx.attr.tool[DefaultInfo].default_runfiles,
        ctx.attr._bash_runfiles[DefaultInfo].default_runfiles,
    ])
    return [DefaultInfo(executable = output, runfiles = files)]

lookup_test = rule(
    implementation = _lookup_test_impl,
    test = True,
    attrs = {
        "data": attr.label_list(allow_files = True),
        "tool": attr.label(executable = True, cfg = "exec", mandatory = True),
        "_bash_runfiles": attr.label(default = Label("@bazel_tools//tools/bash/runfiles")),
        "_template": attr.label(default = Label(":lookup_test.tpl.sh"), allow_single_file = True),
    },
)
