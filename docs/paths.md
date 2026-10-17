# Paths

```starlark
load("@mboworks_bzl//bzl/paths:paths.bzl", "paths")
```

The module performs lexical path-string operations. It does not read the filesystem, resolve
symlinks, inspect the current directory, expand environment variables or `~`, or check existence.
Choose Unix or Windows behavior explicitly; it does not depend on the host running Bazel.

## Functions and signatures

| Function                                                                             | Result                                                           |
| ------------------------------------------------------------------------------------ | ---------------------------------------------------------------- |
| `normalize(path, collapse=False, is_windows=False)`                                  | Standardized separators, no redundant separators or `.` segments |
| `normalize_windows(path, collapse=False)`                                            | Windows normalization                                            |
| `collapse(path, is_windows=False)`                                                   | Lexically remove `.` and collapse `..` where possible            |
| `collapse_windows(path)`                                                             | Windows lexical collapse                                         |
| `is_absolute(path, is_windows=False)`                                                | Boolean structural absolute-path test                            |
| `is_absolute_windows(path)`                                                          | Windows structural absolute-path test                            |
| `join(*parts, collapse=False, is_windows=False)`                                     | Concatenate nonempty parts, then normalize                       |
| `join_windows(*parts, collapse=False)`                                               | Windows concatenating join                                       |
| `join_respect_absolute(*parts, collapse=False, is_windows=False)`                    | Join starting at the last absolute part                          |
| `join_respect_absolute_windows(*parts, collapse=False)`                              | Windows resetting join                                           |
| `ensure_trailing_slash(path, collapse=False, default_if_empty="", is_windows=False)` | Normalize and ensure exactly one trailing separator              |
| `ensure_trailing_slash_windows(path, collapse=False, default_if_empty="")`           | Windows trailing-separator helper                                |

All results are strings except the absolute-path tests. Path values are strings; joining skips empty
strings and `None` parts. Generic functions accept `is_windows=True`; the `_windows` wrappers force
Windows behavior even if an `is_windows` keyword is forwarded to them.

## Separator and root rules

Both slash styles are recognized as separators in both modes. Unix output uses `/`; Windows output
uses `\`. Repeated separators, `.` components, and trailing separators are removed by normalization,
except where the separator forms a root.

| Input                | Unix normalization  | Windows normalization |
| -------------------- | ------------------- | --------------------- |
| Empty string         | Empty string        | Empty string          |
| `/`                  | `/`                 | `\`                   |
| `//`                 | `/`                 | `\`                   |
| `a//b/./c/`          | `a/b/c`             | `a\b\c`               |
| `C:/foo/bar`         | `C:/foo/bar`        | `C:\foo\bar`          |
| `C:relative/path`    | `C:relative/path`   | `C:\relative\path`    |
| `//server/share/dir` | `/server/share/dir` | `\server\share\dir`   |

Windows mode recognizes a drive-like prefix by a colon in the second character and treats it as
an absolute root. Therefore `C:` becomes `C:\`, and `C:foo` becomes `C:\foo`. Windows drive-relative
semantics are not supported. A single leading slash is a local root; two leading slashes preserve
the UNC form. These are structural string rules rather than validation of drive/share names.

`is_absolute` standardizes slash direction but does not otherwise normalize. Unix absolute paths
start with a separator; Windows mode also recognizes drive-like prefixes. A drive-prefixed path
is relative under Unix rules. The empty string is never absolute.

```starlark
paths.is_absolute("C:/foo")          # False
paths.is_absolute_windows("C:foo")  # True
paths.is_absolute_windows("/foo")   # True
paths.normalize_windows("C:foo")    # "C:\\foo"
```

## Normalization and collapse

`normalize` preserves `..` by default. `collapse=True` additionally applies lexical parent collapse:

```starlark
paths.normalize("a/./b/../c")                 # "a/b/../c"
paths.normalize("a/./b/../c", collapse=True)  # "a/c"
paths.collapse("a/b/../c")                    # "a/c"
paths.collapse("../../a")                     # "../../a"
paths.collapse("/../../a")                    # "/a"
paths.collapse("a/..")                        # ""
paths.collapse_windows("C:/a/../../b")         # "C:\\b"
```

A relative path retains leading `..` when there is no preceding component to remove. An absolute
root discards attempts to move above it. UNC collapse preserves its leading double separator;
server/share names participate in lexical component collapse rather than receiving filesystem
share-boundary semantics. A path that collapses away completely is empty, not `.`.

Collapsing does not account for symlinks: `foo/bar/..` becomes `foo` regardless of what `bar` denotes
on a real filesystem. Use these helpers for lexical paths, not filesystem resolution or containment.

## Joining

`join` concatenates all nonempty parts and normalizes the result. A later absolute-looking part
does not discard earlier parts. A drive prefix becomes a Windows root only when it starts the
joined value; in a later part it remains a literal directory component.

```starlark
paths.join("a/b", "/c/d")                 # "a/b/c/d"
paths.join("a", "", None, "b")            # "a/b"
paths.join("a/b", "../c", collapse=True)   # "a/c"
paths.join_windows("a/b", "C:/foo")        # "a\\b\\C:\\foo"
paths.join()                               # ""
```

`join_respect_absolute` finds the last structurally absolute part and discards earlier parts before
joining. Its absolute-path test uses the selected platform rules:

```starlark
paths.join_respect_absolute("a/b", "/c/d")   # "/c/d"
paths.join_respect_absolute("a/b", "C:/foo") # "a/b/C:/foo"
paths.join_respect_absolute_windows("a/b", "C:/foo", "bar")  # "C:\\foo\\bar"
paths.join_respect_absolute_windows("C:/foo", "/bar")        # "\\bar"
```

Neither join inserts a current directory, evaluates a drive's current directory, or queries the host.

## Trailing separators

`ensure_trailing_slash` normalizes first, optionally collapses parents, then adds exactly one trailing
separator unless the result is already a root. If normalization produces an empty value,
`default_if_empty` is normalized in the same way and used as the fallback. Its default is empty,
so an empty relative path is not implicitly turned into an absolute root.

```starlark
paths.ensure_trailing_slash("a//b///")          # "a/b/"
paths.ensure_trailing_slash("/")                # "/"
paths.ensure_trailing_slash("")                 # ""
paths.ensure_trailing_slash("", default_if_empty="/")  # "/"
paths.ensure_trailing_slash("a/..", collapse=True, default_if_empty="root")  # "root/"
paths.ensure_trailing_slash_windows("C:")        # "C:\\"
paths.ensure_trailing_slash_windows("//server/share")  # "\\\\server\\share\\"
paths.ensure_trailing_slash_windows("", default_if_empty="/")  # "\\"
```

A fallback that also normalizes to empty still returns empty. Existing trailing separators never
double; Unix roots, Windows drive/local roots and the UNC double-separator root retain their form.
