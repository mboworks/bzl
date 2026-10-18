# Infrastructure and publishing

Adapted from [proto PR 100](https://github.com/mboworks/proto/pull/100) and xff PRs 835–848,
excluding 841. This repository keeps its Starlark/shell test pipeline and native setup-bazel
cache support. C++ clang-tidy orchestration, sanitizer caches, and coverage history ordering do
not apply to its current jobs.

## CI and caching

Main and numeric release tags run push validation; branches run in pull-request context,
including forks, without duplicating the complete matrix on each push. Only superseded PR runs
are cancelled. The final gate retains release-site tests, pre-commit, and every test-matrix cell.

The pinned setup-bazel action retains native platform-specific cache paths, including Windows
where supported. In the Test workflow, PRs and release tags restore caches; only main saves them.
The separate upstream Release build disables cache mounting because it cannot restrict writes
to main. Bazelisk and
repository downloads remain cached because these small projects do not download the C++ LLVM
payload that motivated compiled-output-only caching in proto and xff. The action's existing
OS/architecture and build/dependency-hash keys remain intact. Exact cache hits are immutable;
source-only edits need not refresh these small build-configuration caches.

The final main job reports compressed repository cache usage and the ten largest entries.
Use these measurements before introducing stricter budgets or custom eviction. A missing
inventory is reported without replacing test failures. This inventory includes all refs and
may briefly lag post-job cache uploads; verify later runs before claiming savings.

## Publishing

The release publisher uses trusted main tooling and the tagged documentation snapshot.
The shared 64-pixel README logo and favicons match MBO Works' other repositories.
Favicons are inserted after staging the complete deployment copy; retained release snapshots
stay unchanged. Decoration is idempotent and resolves links from nested pages.

The shared release workflow is pinned to the same v7.7.0 commit as proto. Standard releases
are staged as drafts until archives and attestations are uploaded, then published once. Published
immutable prereleases cannot later be promoted. BCR publication follows release success and can
be retried independently; its failure does not require recreating a release or moving its tag.
Release helpers, numeric tags, and version agreement keep their existing contracts. No module
dependency versions change in this rollout.

### Registry validation

BCR builds the public `paths`, `runfiles`, and `versions` library targets from an
anonymous consumer module. It separately runs `bazel test //...` from the release
root through `bcr_test_module`, preserving development-only repositories such as
`runfiles_fixture`. Both tasks cover Bazel 7, 8, and 9 on Linux, macOS, and Windows.
Do not recursively build the development tests from a dependency context: Bazel
intentionally omits that dependency's development-only repositories.

### Published-site budget

Each publisher fetches only the latest `coverage-pages` snapshot with `--depth=1` and no tags.
`storage-report.json` measures the complete retained tree before committing and the staged tree
again after deployment-only artwork. It records file counts and bytes by top-level directory,
excluding Git metadata and the report itself. Release pages and assets are not changed.

Publication warns at **250 MB**. An emergency **9 GB** payload guard leaves TAR packaging headroom;
GitHub's [supported published-site limit](https://docs.github.com/en/pages/getting-started-with-github-pages/github-pages-limits)
remains **1 GB**, so the emergency guard is not an operating target. Review growth before reaching
that limit. This repository does not currently publish coverage, so no coverage retention or
browser loader is introduced. Git history, build caches, and Actions artifacts are separate budgets.
The change follows [mbo PR #549](https://github.com/mboworks/mbo/pull/549).

## Contributor rules and verification

`AGENTS.md`, `GIT_RULES.md`, and `STYLE_SH.md` synchronize applicable shared rules. `RULES.md`
retains this repository's layout and API promises. Beautysh remains the shell formatter; no C++
style guide or competing shell formatter is introduced.

Run `bazel test //...`, `python3 -m unittest discover -s tools -p '*_test.py'`, and
`pre-commit run --all-files`. CI also builds the configured release documentation to validate
links and mappings before publication.

## Version consistency

`MODULE.bazel` and the first `CHANGELOG.md` heading identify the development version.
The README installation example stays at the latest published release during development.
Historical changelog entries and illustrative version strings retain their original values.

Before a release, run `python3 tools/prepare_release.py X.Y.Z`. It verifies the module and
changelog versions and updates the README dependency automatically. Review and merge that
change before tagging; preparation does not commit, tag, or publish anything. The README may
name the upcoming release during this preparation stage.

Both `tools/trigger_release.sh` (including dry runs) and the archive workflow require
`prepare_release.py --check` to pass, keeping the tag, archive README, module, and release notes
consistent. BCR metadata and release assets derive their versions from the release tag.

The `compare-versions` pre-commit hook accepts either the latest numeric release tag or the
current development version for the README. As in bashtest, local validation uses Git tags
as release evidence, not a live GitHub Releases query; fetch tags before checking. Without tags,
it can only validate the example's format and upper bound. CI fetches all tags. The released
commit may keep its release version; the first subsequent commit must advance the development
version. Regression tests in `tools/version_test.py` exercise validation and release preparation
in temporary Git repositories, including the packaged archive. They run in pre-commit and CI.
