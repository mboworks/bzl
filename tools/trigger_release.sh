#!/usr/bin/env bash

# SPDX-FileCopyrightText: Copyright (c) M. Boerger and the MBO Works authors
# SPDX-License-Identifier: Apache-2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -euo pipefail

function die() {
    echo "ERROR: ${*}" 1>&2
    exit 1
}

REPO="mboworks/bzl"

# Release approval is performed by a dedicated GitHub App (permissions:
# "Pull requests: Read & write" and "Metadata: Read-only", installed on this
# repo). The App ONLY approves the version-bump PR -- it cannot bypass branch
# protection, merge, or write contents. This satisfies the ruleset's
# "1 approval from someone other than the last pusher" without granting any
# human or token a standing override of `main`. The human running this script
# must be a repository admin (checked below); they author and push the PR, and
# the App provides the approval. The non-secret RELEASE_APP_ID,
# RELEASE_APP_INSTALLATION_ID and RELEASE_APP_KEY_SERVICE are loaded from this
# repo's Actions variables below (after the admin check, before anything
# irreversible); the secret PEM key stays in the macOS Keychain, stored raw via
# `-w "$(cat app.pem)"` (release_app_token tolerates security's hex re-encoding).

for tool in gh git openssl curl jq security xxd; do
    # trunk-ignore(shellcheck/SC2310)
    command -v "${tool}" >/dev/null 2>&1 || die "Required tool '${tool}' is not installed."
done

# Prints a short-lived GitHub App installation access token to stdout. Used to
# authenticate ONLY the approval step, so the approver differs from the human
# who pushed the branch (required by the ruleset's require_last_push_approval).
function release_app_token() {
    local raw pem now iat exp header payload unsigned signature jwt
    raw="$(security find-generic-password -s "${RELEASE_APP_KEY_SERVICE}" -w 2>/dev/null)" || die "Cannot read the App key from Keychain service '${RELEASE_APP_KEY_SERVICE}'."
    # `security -w` returns the value verbatim EXCEPT it hex-encodes any secret
    # containing newlines, so a raw multi-line PEM reads back as hex. Use it as
    # is when it is already a PEM, otherwise hex-decode it.
    if printf '%s' "${raw}" | openssl pkey -noout >/dev/null 2>&1; then
        pem="${raw}"
    else
        pem="$(printf '%s' "${raw}" | xxd -r -p 2>/dev/null)"
    fi
    printf '%s' "${pem}" | openssl pkey -noout >/dev/null 2>&1 || die "Keychain service '${RELEASE_APP_KEY_SERVICE}' does not contain a valid PEM key. Store the raw key with: security add-generic-password -U -s '${RELEASE_APP_KEY_SERVICE}' -a \"\${USER}\" -w \"\$(cat app.pem)\""

    now="$(date +%s)"
    iat="$((now - 60))"  # Backdate slightly to tolerate clock skew.
    exp="$((now + 540))" # 9 minutes (GitHub allows at most 10).

    function _b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '=\n'; }
    header="$(printf '%s' '{"alg":"RS256","typ":"JWT"}' | _b64url)"
    payload="$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' "${iat}" "${exp}" "${RELEASE_APP_ID}" | _b64url)"
    unsigned="${header}.${payload}"
    signature="$(printf '%s' "${unsigned}" | openssl dgst -sha256 -sign <(printf '%s' "${pem}") | _b64url)"
    jwt="${unsigned}.${signature}"

    curl -fsS -X POST \
        -H "Authorization: Bearer ${jwt}" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/app/installations/${RELEASE_APP_INSTALLATION_ID}/access_tokens" | jq -r '.token'
}

# Usage: tools/trigger_release.sh [--dry] <version>
#   --dry / --dry-run: run every check (tools, admin, App credential preflight,
#   clean tree, version match) and print the plan, but change nothing.
DRY_RUN=false
VERSION=""
for arg in "${@}"; do
    if [[ "${arg}" == "--dry" || "${arg}" == "--dry-run" ]]; then
        DRY_RUN=true
    elif [[ "${arg}" == -* ]]; then
        die "Unknown option '${arg}'. Usage: ${0} [--dry] <version>"
    elif [[ -z "${VERSION}" ]]; then
        VERSION="${arg}"
    else
        die "Too many arguments. Usage: ${0} [--dry] <version>"
    fi
done
[[ -n "${VERSION}" ]] || die "Usage: ${0} [--dry] <version>"

# Only repository admins may cut a release. This runs as your default `gh` auth
# (which must therefore be an admin). The App token is used later, solely for
# the approval; everything else here acts as you.
RELEASE_ACTOR="$(gh api user --jq '.login')" || die "Could not resolve the current GitHub user; is 'gh' authenticated?"
RELEASE_ACTOR_PERMISSION="$(gh api "repos/${REPO}/collaborators/${RELEASE_ACTOR}/permission" --jq '.permission' 2>/dev/null || echo "none")"
[[ "${RELEASE_ACTOR_PERMISSION}" == "admin" ]] || die "Only repository admins may run a release (user '${RELEASE_ACTOR}' has permission '${RELEASE_ACTOR_PERMISSION}')."

# Load all release config BEFORE anything irreversible. The non-secret ids come
# from this repo's Actions variables (a same-named env var overrides); the
# secret PEM stays in the Keychain under RELEASE_APP_KEY_SERVICE.
function repo_variable() { gh api "repos/${REPO}/actions/variables/${1}" --jq '.value' 2>/dev/null; }
# trunk-ignore(shellcheck/SC2310)
RELEASE_APP_ID="${RELEASE_APP_ID:-$(repo_variable RELEASE_APP_ID || true)}"
# trunk-ignore(shellcheck/SC2310)
RELEASE_APP_INSTALLATION_ID="${RELEASE_APP_INSTALLATION_ID:-$(repo_variable RELEASE_APP_INSTALLATION_ID || true)}"
# trunk-ignore(shellcheck/SC2310)
RELEASE_APP_KEY_SERVICE="${RELEASE_APP_KEY_SERVICE:-$(repo_variable RELEASE_APP_KEY_SERVICE || true)}"
[[ -n "${RELEASE_APP_ID}" ]] || die "RELEASE_APP_ID is not set (repo Actions variable or env)."
[[ -n "${RELEASE_APP_INSTALLATION_ID}" ]] || die "RELEASE_APP_INSTALLATION_ID is not set (repo Actions variable or env)."
[[ -n "${RELEASE_APP_KEY_SERVICE}" ]] || die "RELEASE_APP_KEY_SERVICE is not set (repo Actions variable or env)."

# Preflight the App credential BEFORE tagging/pushing: minting an installation
# token reads the Keychain PEM and exercises it end-to-end, so a wrong id, a
# missing/invalid PEM, or an App that is not installed fails HERE -- never after
# the release tag is already pushed. A fresh token is minted again to approve.
# trunk-ignore(shellcheck/SC2310)
release_app_token >/dev/null || die "Release App preflight failed: could not mint an installation token. Verify RELEASE_APP_ID, RELEASE_APP_INSTALLATION_ID, and that the Keychain key ('${RELEASE_APP_KEY_SERVICE}') is valid and belongs to the installed App."
echo "App credential preflight: ok (installation token mints)."

git fetch origin main # Make sure the below is relevant

# trunk-ignore(shellcheck/SC2312)
if [[ -n "$(git status --porcelain)" ]]; then
    # Non empty output means non clean branch.
    die "Must be run from clean 'main' branch."
fi
# trunk-ignore(shellcheck/SC2312)
if [[ -n "$(git diff origin/main --numstat)" ]]; then
    die "Must be run from clean 'main' branch."
fi
# trunk-ignore(shellcheck/SC2312)
if [[ -n "$(git diff origin/main --cached --numstat)" ]]; then
    die "Must be run from clean 'main' branch."
fi

BAZELMOD_VERSION="$(sed -rne 's,.*version = "([0-9]+([.][0-9]+)+.*)".*,\1,p' <MODULE.bazel | head -n1)"
CHANGELOG_VERSION="$(sed -rne 's,^# ([0-9]+([.][0-9]+)+.*)$,\1,p' <CHANGELOG.md | head -n1)"
NEXT_VERSION="$(echo "${VERSION}" | awk -F. '/^(0|[1-9][0-9]*)([.](0|[1-9][0-9]*)){2,}([-+]|$)/{print $1"."$2"."(($3)+1)}')"

if [[ "${BAZELMOD_VERSION}" != "${CHANGELOG_VERSION}" ]]; then
    die "MODULE.bazel (${BAZELMOD_VERSION}) != CHANGELOG.md (${CHANGELOG_VERSION})."
fi

if [[ "${VERSION}" != "${BAZELMOD_VERSION}" ]]; then
    die "Provided version argument (${VERSION}) different from merged version (${BAZELMOD_VERSION})."
fi

if [[ -z "${NEXT_VERSION}" ]]; then
    die "Could not determine next version from input (${VERSION})."
fi

# trunk-ignore(shellcheck/SC2312)
grep -E "^${VERSION}$" < <(git tag -l) && die "Version tag is already in use."

echo "Next version: ${NEXT_VERSION}"

# Dry run stops here: everything above is read-only validation (including the
# App credential preflight); everything below mutates (file edits, tag, push,
# PR), so a dry run leaves the working tree and remote untouched.
if [[ "${DRY_RUN}" == true ]]; then
    echo "[dry-run] All checks passed: tools, admin (${RELEASE_ACTOR}), App credential preflight, clean tree, version match (${VERSION} -> ${NEXT_VERSION})."
    echo "[dry-run] A real run would now:"
    echo "[dry-run]   1. create signed tag '${VERSION}' and push it (triggers the release workflow)"
    echo "[dry-run]   2. bump MODULE.bazel + CHANGELOG.md to '${NEXT_VERSION}' on branch 'chore/bump_version_to_${NEXT_VERSION}'"
    echo "[dry-run]   3. open the bump PR, approve it via the release App, and enable squash auto-merge"
    echo "[dry-run] Nothing was changed."
    exit 0
fi

sed -i '' -f - CHANGELOG.md <<EOF
1i\\
# ${NEXT_VERSION}
1i\\

EOF

sed -i '' "s/version = \"${VERSION}\"/version = \"${NEXT_VERSION}\"/" MODULE.bazel

MESSAGE_BODY="$(awk '/^#/{if(NR>1)exit}/^[^#]/{print}' <CHANGELOG.md)"

git tag -s -a "${VERSION}" \
    -m "New release tag version: '${VERSION}'." \
    -m "${MESSAGE_BODY}"

git push origin --tags

NEXT_BRANCH="chore/bump_version_to_${NEXT_VERSION}"

git checkout -b "${NEXT_BRANCH}"
git add MODULE.bazel
git add CHANGELOG.md
git commit -m "Bump version to ${NEXT_VERSION}"
git push -u origin "${NEXT_BRANCH}"

# Open the version-bump PR as you (the admin), have the release App approve it,
# then let branch protection auto-merge once CI is green. No admin/bypass
# override is used -- the App's approval *satisfies* the review rule, so `main`
# keeps full protection.
BUMP_TEXT="Bump version from ${VERSION} to ${NEXT_VERSION}"
MERGE_BODY="Auto-approved version bump from ${VERSION} to ${NEXT_VERSION} by the release App."

PR_CREATE_OUTPUT="$(gh pr create --title "${BUMP_TEXT}" --body "Created by ${0}." 2>&1)" || die "Could not create PR: ${PR_CREATE_OUTPUT}"
echo "${PR_CREATE_OUTPUT}"

# trunk-ignore(shellcheck/SC2312)
PRNUM="$(printf '%s\n' "${PR_CREATE_OUTPUT}" | sed -E -n 's,.*pull/([0-9]+).*,\1,p' | head -n1)"
[[ "${PRNUM}" =~ ^[0-9]+$ ]] || die "Could not determine the PR number from 'gh pr create'."
PRURL="https://github.com/${REPO}/pull/${PRNUM}"

gh pr ready "${PRNUM}"

# Approve as the release App. Mint the installation token first and refuse to
# proceed if it is empty -- otherwise the inline GH_TOKEN below would be unset
# and `gh` would fall back to YOUR auth, self-approving the PR.
echo "Approving PR #${PRNUM} as the release App ..."
APP_TOKEN="$(release_app_token)" || die "Could not mint a release App installation token."
[[ -n "${APP_TOKEN}" ]] || die "The release App installation token was empty; refusing to fall back to your own auth."

# Set GH_TOKEN ONLY for this one command, so the approver (the App) differs from
# the human who pushed the branch (required by require_last_push_approval).
GH_TOKEN="${APP_TOKEN}" gh pr review "${PRNUM}" --approve --body "${MERGE_BODY}" || die "The release App could not approve PR #${PRNUM}. See ${PRURL}."

# Queue the squash merge; branch protection completes it once the approval and
# all required status checks are satisfied. No override is used or needed.
gh pr merge "${PRNUM}" --auto --squash --delete-branch \
    --subject "${BUMP_TEXT}" --body "${MERGE_BODY}"

git checkout main
echo "PR #${PRNUM} approved by the release App; auto-merge completes when CI passes: ${PRURL}"
