# Runfiles keys

Load the library with:

```starlark
load("@mboworks_bzl//bzl/runfiles:runfiles.bzl", "runfiles")
```

`runfiles.key(ctx, file)` returns the repository-qualified lookup key for a Bazel `File`.
It produces the same key as Bazel's `$(rlocationpath label)` expansion, but accepts an
existing file object inside a rule or aspect. This is useful for generated files,
aspect outputs and executable attributes, where the caller already has a `File`.

## Contract

- `ctx` is the calling rule or aspect context; `file` is a Bazel `File`.
- Main-repository files use `ctx.workspace_name` followed by their `short_path`.
- External files retain the repository name supplied by Bazel in `short_path`, with
  its leading `../` removed. Repository names are not guessed from apparent labels.
- Source files, generated files and executable files use the same API.
- The result uses `/` separators on every platform. It is a lookup key, not an
  absolute filesystem path or a build-action execution path.

The helper does not add the file to runfiles or perform runtime lookup. Resolve the
key using the runfiles library for your executable's language. It describes the
file's default runfiles entry; custom `symlinks` or `root_symlinks` names must be
supplied explicitly by the caller. A `File` alone cannot identify those aliases.

## Generated launchers and tools

A rule can substitute the key into a launcher template:

```starlark
load("@bazel_skylib//lib:shell.bzl", "shell")

tool = ctx.executable.tool
ctx.actions.expand_template(
    template = ctx.file._launcher,
    output = launcher,
    is_executable = True,
    substitutions = {"@@TOOL_KEY@@": shell.quote(runfiles.key(ctx, tool))},
)
launcher_runfiles = ctx.runfiles(files=[tool]).merge(
    ctx.attr.tool[DefaultInfo].default_runfiles,
)
```

Return `launcher_runfiles` through the launcher's `DefaultInfo`. Merge the runtime
runfiles library's dependencies too. After initializing that library, a Bash
launcher can use `"$(rlocation @@TOOL_KEY@@)"` to invoke the tool. The substitution
is shell-quoted so spaces and quotes in keys remain part of the same argument.

For a collection, use `[runfiles.key(ctx, file) for file in files]`. Keep each key
separate when passing arguments or writing structured data; do not split paths on
spaces.

For a **build action**, pass the tool's `FilesToRunProvider` instead:

```starlark
ctx.actions.run(
    executable=ctx.attr.tool[DefaultInfo].files_to_run,
    inputs=inputs,
    outputs=outputs,
    arguments=arguments,
)
```

Bazel supplies the executable and its runfiles to the action. A runfiles key is not
an executable path for `ctx.actions.run`.

## Relationship to Bazel

Prefer `$(rlocationpath label)` where a rule attribute already supports that
expansion. This library provides the corresponding operation for `File` objects;
it introduces no alternative lookup or repository-mapping policy. See Bazel's
[predefined path variables](https://bazel.build/reference/be/make-variables#predefined_label_variables).

Contract tests compare real source, generated and executable files with Bazel's
expansion, including external repositories and aliases. Bash integration tests
read the files and execute a tool through directory and manifest-only lookup on
Unix. The key contract tests also run on Windows.
