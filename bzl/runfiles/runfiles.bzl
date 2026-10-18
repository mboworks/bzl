# SPDX-FileCopyrightText: Copyright (c) M. Boerger, the MBO Works authors
# SPDX-License-Identifier: Apache-2.0
"""Construction of default runfiles lookup keys for Bazel File objects."""

def _key(ctx, file):
    """Returns the repository-qualified key accepted by runtime runfiles libraries.

    Args:
        ctx: The calling rule or aspect context.
        file: A Bazel File, including source, generated, or executable files.

    Returns:
        A slash-separated lookup key, not a filesystem or execution-root path.
        The file must separately be included in the executable's runfiles.
        Custom symlink names are not inferred from the file.
    """
    if file.short_path.startswith("../"):
        return file.short_path[3:]
    return ctx.workspace_name + "/" + file.short_path

runfiles = struct(key = _key)
