#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) M. Boerger, the MBO Works authors
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

# Bootstrap Bazel's Bash runfiles library in tree or manifest-only environments.
runfiles_lib="bazel_tools/tools/bash/runfiles/runfiles.bash"
if [[ -f "${RUNFILES_DIR:-}/$runfiles_lib" ]]; then
    # shellcheck disable=SC1090 # Bazel provides this runtime dependency.
    source "${RUNFILES_DIR}/$runfiles_lib"
else
    # shellcheck disable=SC1090 # Resolve the library from Bazel's manifest.
    source "$(grep -sm1 "^${runfiles_lib} " "${RUNFILES_MANIFEST_FILE}" | cut -d ' ' -f 2-)"
fi

keys=(__KEYS__)

check_keys() {
    local key resolved
    for key in "${keys[@]}"; do
        resolved="$(rlocation "$key")"
        [[ "$(cat "$resolved")" == 'runfiles fixture' ]]
    done
    resolved="$(rlocation __TOOL__)"
    [[ "$("$resolved")" == 'runfiles tool' ]]
}

# Build a manifest from resolved fixture paths: tree-mode sandboxes need not
# include Bazel's manifest. Then exercise the same keys with no tree available.
manifest="${TEST_TMPDIR}/lookup_manifest"
check_keys
for key in "${keys[@]}" __TOOL__; do
    printf '%s %s\n' "$key" "$(rlocation "$key")"
done > "$manifest"
export RUNFILES_MANIFEST_FILE="$manifest"
unset RUNFILES_DIR
check_keys
