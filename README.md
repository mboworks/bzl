# MBO Works bzl, a Bazel support library

[Release website](https://mboworks.github.io/bzl/)

This library provides [Bazel](http://bazel.build) [Starlark](https://bazel.build/rules/language) functionality meant to help in maintaining other libraries.

[![Test](https://github.com/mboworks/bzl/actions/workflows/main.yml/badge.svg)](https://github.com/mboworks/bzl/actions/workflows/main.yml)

The following libraries are implemented:

- [Versions](#versions)
- [Paths](#paths)

## Versions

Implements versioning functions that mostly follow [Semver](https://semver.org/).

Comparators correctly respect major, minor and patch components, as well as
Semver compliant 'pre-release' and 'build' components. The pre-release and build
components are split at ".". Comparing pre-release parts works for alphabetical
prefixes and numeric suffixes, so 'alpha', 'beta' and 'rc' as well as numbered
versions of those (e.g. 'alpha1' or 'rc-1') are supported. For pre-release
pieces a single '-' in front of the numeric parts is dropped (e.g. 'rc-1'
becomes 'rc' + '1' while 'alpha--2' becomes 'alpha-' + '2'). Build components
are split only at dots; their prefixes and numeric suffixes are not separated.

The full functionality is exposed as a single struct containing all functions.

The version parameters support:

- a string that can be parsed according to:
  `major`['.' `minor` [ '.' `patch` [ '.' `digits`]\*]] ['-' [^+]+] ['+' .\*]
- a `list` or `tuple` where each component is a version part. If present, then:
  - a pre-release component must be separated by a single "-" and split by ".".
  - a build component must be separated by a single "+" and split by "."
- a single `int` which will be the major version.
- anything else is an error and the functions will `fail`.
- unlike Semver, the function allows any number of numeric version components.

Note: Most functions support a `skip_build` parameter. If `True`, then any
present build component will be dropped. The parameter defaults to `False`
for parsing and `True` for comparisons since Semver dictates that
the build component must be ignored for precedence (see
[Semver-10](https://semver.org/#spec-item-10)).

The functionality has exhaustive tests. If something still works wrong please,
file a bug report or propose a fix.

Example:

```starlark
load("@mboworks_bzl//bzl/versions:versions.bzl", _versions = "versions")

my_version = "25.33.42"
min_version = (10, 11, 12)
if _versions.lt(my_version, min_version):
  fail("My version {my_version} is earlier than {min_version}.".format(
    my_version = my_version,
    min_version = min_version,
  ))
```

Provides:

- `load("@mboworks_bzl//bzl/versions:versions.bzl", _versions = "versions")`
  - `versions` is a single import structure:
    - `parse`: Parses a version.
    - `ge`: Implements `L >= R`.
    - `gt`: Implements `L > R`.
    - `le`: Implements `L <= R`.
    - `lt`: Implements `L < R`.
    - `eq`: Implements `L == R`.
    - `ne`: Implements `L != R`.
    - `cmp`: Returns -1 if `L < R`, 0 if `L == R`, and 1 if `L > R`.
    - `compare`: Implements `L OP R`.
    - `check_one_requirement`: Checks a version adheres to a single requirement.
    - `check_all_requirements`: Checks a version adheres to a requirements list.
    - `parse_requirements`: Parses a requirements specification.

## Paths

Implements file path manipulation functions.

NOTE: These functions do not support Windows drive letter relative paths.

Provides:

- `load("@mboworks_bzl//bzl/paths:paths.bzl", _paths = "paths")`
  - `paths` is a single import structure:
    - `collapse`: Collapse '.' and '..' path segments for normalized Unix paths.
    - `collapse_windows`: Collapse '.' and '..' path segments for normalized Windows paths.
    - `ensure_trailing_slash`: Ensure a Unix path ends with a single trailing slash.
    - `ensure_trailing_slash_windows`: Ensure a Windows path ends with a single trailing backslash.
    - `is_absolute`: Returns `True` if a Unix path is absolute.
    - `is_absolute_windows`: Returns `True` if a Windows path is absolute.
    - `join`: Join path elements and return as normalized Unix paths.
    - `join_windows`: Join path elements and return as normalized Windows paths.
    - `join_respect_absolute`: Join path elements (respecting absolute paths) and return as normalized Unix paths.
    - `join_respect_absolute_windows`: Join path elements (respecting absolute paths) and return as normalized Windows paths.
    - `normalize`: Normalize a Unix file path.
    - `normalize_windows`: Normalize a Windows file path.

## Installation

The library is available as a Bazel module (bzlmod) and supports macOS, Ubuntu
and Windows with Bazel versions 7.x, 8.x and 9.x (other systems are not tested).
However, future versions may drop Windows support.

### For MODULE.bazel

See [mboworks/bzl releases](https://github.com/mboworks/bzl/releases) to replace the version number.

```starlark
bazel_dep(name = "mboworks_bzl", version = "0.5.1")
```

### Dependencies

- `bazel_skylib`.

## Release website

Release notes use `.github/release-notes.md.template`, rendered by
`tools/release_notes.sh TAG`, to link to that tag's versioned website and related
release resources. The existing changelog and installation notes remain included.

The [website](https://mboworks.github.io/bzl/) forwards to the latest published
stable release at `site/tag/<tag>/`, preserving the exact Git tag name.
Each release keeps its converted HTML, images, and configured files. Retrying
publication leaves an existing snapshot unchanged; a different commit cannot
replace it. Older versions remain directly accessible.

[`release-site.json`](release-site.json) defines the layout. Source names are
relative to the repository root; destinations are relative to that release's
site directory. For example:

```json
{
  "pages": {
    "README.md": "index.html",
    "docs/guide.md": "guide/index.html"
  },
  "files": {
    "schema/example.json": "schema/v1.json"
  },
  "links": [
    {
      "label": "Release",
      "href": "https://github.com/{owner}/{repo}/releases/tag/{tag}"
    }
  ]
}
```

Use existing source files in the actual configuration. `pages` converts Markdown;
optional `files` copies other files unchanged. `README.md` must map to `index.html`.
The generated `documents.html`, `release.json`, `release-site.json`, and `assets/`
paths are reserved. Destination paths cannot have hidden components (names starting
with a dot), because the Pages artifact uploader excludes them. Hidden source
paths remain valid; for example, `.github/workflows/README.md` maps to
`workflows/index.html`.
Navigation links support `{owner}`, `{repo}`, `{tag}`, `{version}`, and `{commit}`.
`{version}` omits a leading `v` for compatibility with coverage report paths.
By default, the configuration and content come from the release tag. Every linked
local Markdown page (including directory README links) must have a `pages` mapping.
Publication fails for an omitted mapping, a missing generated file, or a broken
anchor within the snapshot. Links to configured pages follow their destination
mappings; other local source links use the exact release commit. Embedded images are copied, including remote badges. Markdown
conversion uses the [GitHub Markdown API](https://docs.github.com/en/rest/markdown/markdown)
at publication time; browsing the result requires no Markdown renderer or CDN.

After the Release workflow succeeds, `Publish release site` retains the snapshot
on `coverage-pages` and deploys the complete Pages tree. Coverage and site
publication share a concurrency group to preserve both trees. GitHub's latest
stable release selects the root redirect; backfilling an older release does not
make it latest. The workflow can also be dispatched with a published tag to retry
publication. Enable GitHub Pages with
**GitHub Actions** as its source, and set the repository's About website to
`https://mboworks.github.io/bzl/`.

### Backfill a historical release

No new release or tag change is needed. Manually dispatch `Publish release site`
with `tag` set to the historical release and `config_path` set to a tracked JSON
file on `main`. Leave `config_path` empty to use a configuration already in the tag.
For example, after selecting a compatible configuration and an existing tag:

```sh
gh workflow run pages.yml --repo mboworks/bzl --ref main \
  -f tag="$RELEASE_TAG" -f config_path=release-site.json
```

The override controls only publication layout; all Markdown and copied files come
from the selected tag. Each new snapshot retains the exact configuration as
`release-site.json`, with its SHA-256, origin, and source commit in `release.json`.
A configuration can serve several historical tags when its sources exist in each.
For another layout, commit another configuration and select its path. Missing
sources or links fail publication instead of using newer content. Retrying a
published tag preserves its original HTML and configuration.

Local regression tests: `python3 -m unittest discover -s tools -p release_site_test.py`.
CI also converts the configured documentation and checks the generated links in
a disposable runner directory. It never commits, retains, or deploys that preview.
