# Repository transfer runbook

This runbook describes how to transfer a public Bazel module repository from a
personal GitHub account to the MBO Works organization. It is based on the
transfer of `helly25/bzl` to `mboworks/bzl` in August 2026.

Use a pull request for repository changes. Do not rewrite published Git tags,
GitHub releases, release archives, or existing Bazel Central Registry (BCR)
versions.

## Choose the identities first

Record these values before making changes:

| Identity | Old value | New value for this repository |
| --- | --- | --- |
| GitHub repository | `helly25/bzl` | `mboworks/bzl` |
| Project name | Helly25 bzl | MBO Works bzl |
| BCR module | `helly25_bzl` | `mboworks_bzl` |
| First version under the new module name | N/A | `0.5.1` |
| BCR publishing fork | `helly25/bazel-central-registry` | unchanged |
| Individual BCR maintainer | `helly25` | unchanged |

A GitHub repository transfer and a Bazel module rename are separate choices.
Normally, keep the existing module name so consumers do not need to migrate. A
new module name is appropriate only when its consumers can be migrated and the
old module will remain available.

For a renamed module:

- Leave every version of the old module untouched in BCR.
- Do not copy historical versions to the new module.
- Publish the next unreleased version as the first version of the new module.
- Update all known consumers to depend on the new module.

## 1. Audit before the transfer

- Confirm the destination organization and repository name.
- Confirm that the destination does not already contain a repository with that
  name.
- Record branch and tag rulesets, Actions variables, Actions secrets,
  environments, deploy keys, webhooks, GitHub Apps, and installed Apps.
- Record external consumers and automation that refer to the old repository or
  module name.
- Record the latest GitHub release and latest BCR version.
- Ensure the default branch and working tree are clean and CI is passing.
- Decide whether the BCR module name will remain stable.

Useful read-only commands:

```sh
git status --short --branch
git remote -v
gh repo view OLD_OWNER/REPO
gh release list --repo OLD_OWNER/REPO
gh api repos/OLD_OWNER/REPO/actions/variables
gh api repos/OLD_OWNER/REPO/actions/secrets
```

Secrets cannot be read back from GitHub. Verify that their source values are
available before relying on them after the transfer.

## 2. Transfer on GitHub

Transfer the repository in **Settings > General > Danger Zone > Transfer**.
Afterward:

- Confirm the repository is available as `NEW_OWNER/REPO`.
- Confirm the default branch, tags, releases, issues, pull requests, and Actions
  history are present.
- Update the local remote explicitly:

  ```sh
  git remote set-url origin https://github.com/NEW_OWNER/REPO
  git fetch origin --prune --tags
  ```

- Inspect rulesets and organization-inherited policies again. Organization
  rules can differ from personal-account rules.
- Inspect Actions permissions, especially **Allow GitHub Actions to create and
  approve pull requests**.

GitHub redirects old repository URLs and Git remotes after a transfer, but do
not depend on redirects in documentation or release automation.

## 3. Reconnect external integrations

Repository transfer does not reliably transfer installation-scoped access.
Check every integration rather than assuming that copied configuration remains
valid:

- GitHub Apps must be installed for the destination organization/repository.
- A GitHub App installation ID is installation-specific. Update any stored ID
  after reinstalling the App.
- Fine-grained personal access tokens must include the destination organization
  and repository.
- Organization SSO may need to be authorized for tokens or SSH keys.
- Webhooks, deploy keys, environments, and external CI installations must be
  verified individually.
- Confirm that Actions secrets and variables still exist and refer to valid
  credentials.

For `bzl`, the `helly25-bzl-release` App variable survived the transfer but its
installation did not. Its stale installation ID returned HTTP 404. This exposed
that the auto-approval release design depended on an integration that was no
longer connected.

## 4. Update repository references

Search tracked and hidden configuration files:

```sh
rg -n 'OLD_OWNER/REPO|github\.com/OLD_OWNER|OLD_MODULE' \
  --hidden -g '!.git/**' .
```

Review and update, as applicable:

- README title, badges, release links, and installation examples.
- `MODULE.bazel` module name.
- Starlark `load()` examples and labels.
- BUILD-file documentation.
- Source-code documentation links.
- `.bcr/metadata.template.json` homepage and repository.
- `.bcr/presubmit.yml` targets.
- Release archive and changelog URLs.
- Release helper repository constants.
- Reusable-workflow examples.
- Issue and pull-request templates.
- Security, contribution, and code-of-conduct contact links.

Do not mechanically replace identities that remain valid:

- Historical copyright attribution.
- Historical changelog entries.
- An individual maintainer's GitHub username.
- A working personal BCR fork used by the publishing token.

## 5. Validate and merge the migration

Run the repository's complete checks before publishing anything:

```sh
git diff --check
pre-commit run --all-files
bazel test //...
```

Open a migration pull request and let required CI complete. Merge the migration
before creating a release tag; otherwise the release archive will contain the
old metadata.

For a repository with one maintainer, do not use a repository-controlled bot to
simulate an independent PR approval. Prefer protected pull requests with
required CI, signed commits, linear history, no force pushes, and zero required
approving reviews. A bot approval adds operational dependencies without adding
an independent trust decision.

## 6. Publish the first release after transfer

Before tagging:

- Confirm `main` contains the migration commit.
- Confirm `MODULE.bazel` and the top `CHANGELOG.md` entry have the same version.
- Confirm the new module name is not already present in BCR.
- Confirm the release tag and GitHub release do not already exist.
- Confirm the release archive template points to the new GitHub owner.
- Confirm the BCR metadata template names the new repository.
- Run the release helper in dry-run mode if supported.

Create the release only from a clean, current `main`. The preferred design is:

1. Merge a human-reviewed release-preparation PR.
2. Create and push a signed version tag from clean `main`.
3. Let the tag workflow build the archive and GitHub release.
4. Let the publish workflow open the BCR pull request.
5. Review the generated BCR module name, version, source URL, integrity, and
   presubmit targets.
6. Wait for BCR CI and review, then verify the module on the public registry.

Do not create an automatic post-release version-bump PR. Leave `main` at the
latest released version until the next release-preparation PR. This removes the
need for automatic PR creation and approval from the release path.

## 7. Migrate consumers

For every known consumer:

- Change `bazel_dep(name = "OLD_MODULE", ...)` to the new module and version.
- Update explicit repository labels such as `@OLD_MODULE//...`.
- Regenerate the Bazel lockfile when one is checked in.
- Run the consumer's full tests on all supported platforms.
- Merge only after the new BCR version is publicly available.

If label migration must be separated from the dependency migration, Bazel's
`repo_name` attribute can temporarily retain the old apparent repository name:

```starlark
bazel_dep(
    name = "NEW_MODULE",
    version = "NEW_VERSION",
    repo_name = "OLD_MODULE",
)
```

Remove that compatibility alias in a later cleanup.

## 8. Post-transfer verification

- Clone the repository using the new URL into a fresh directory.
- Verify the README badge and documentation links.
- Verify CI on `main`.
- Download and inspect the GitHub release archive.
- Verify its root prefix and `MODULE.bazel` name/version.
- Verify the new module and version on <https://registry.bazel.build/>.
- Test a minimal external module using only the public BCR.
- Update and test all known consumers.
- Keep the old repository redirect and old BCR module versions intact.
- Remove obsolete App variables, secrets, and local credentials only after the
  replacement release path has succeeded.

## `bzl` transfer status

- [x] Repository transferred to `mboworks/bzl`.
- [x] Local `origin` updated.
- [x] Project links and release automation references updated.
- [x] Module renamed to `mboworks_bzl`.
- [x] BCR templates updated for `mboworks_bzl` and `mboworks/bzl`.
- [x] Migration validated with pre-commit and all Bazel tests.
- [x] Migration pull request merged.
- [ ] Replace the failed auto-approval release design with the signed-tag flow.
- [ ] Publish `mboworks_bzl` version `0.5.1` to BCR.
- [ ] Update `bazel-contrib/toolchains_llvm`.
- [ ] Verify a clean external BCR-only build.
