#!/usr/bin/env bash
# refresh.sh — short-lived. Report the jj workspace/change/status/description tokens
# workspaces, then exit. herdr invokes this from [[events]] hooks and the
# [[actions]] entry; there is no long-lived process and nothing persists here.
#
# Scope is decided by HERDR_PLUGIN_EVENT, *not* by whether context is present:
# herdr populates HERDR_PLUGIN_CONTEXT_JSON with the focused workspace for every
# invocation, including [[startup]] and [[actions]], so "no context" never happens.
#
# workspace.* / worktree.* event: refresh just the workspace named in the context.
# Anything else (startup, action, manual run): sweep via `herdr api snapshot`.

set -u

SOURCE="mroth.jj-status"
HERDR="${HERDR_BIN_PATH:-herdr}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPUTE="$HERE/../lib/compute.sh"

# report <workspace_id> <cwd>
report() {
  local wsid="$1" cwd="$2" line bookmark workspace change status description
  [ -n "$wsid" ] || return 0
  # No cwd yet (panes still spawning during the startup sweep): leave whatever
  # tokens are there rather than clearing them on a race.
  [ -n "$cwd" ] || return 0

  if ! line="$(bash "$COMPUTE" "$cwd")"; then
    # Not a jj repo: clear tokens so nothing stale lingers.
    "$HERDR" workspace report-metadata "$wsid" --source "$SOURCE" \
      --clear-token jj_bookmark --clear-token jj_workspace \
      --clear-token jj_change --clear-token jj_status \
      --clear-token jj_description >/dev/null 2>&1
    return 0
  fi

  IFS='|' read -r bookmark workspace change status description <<<"$line"

  # Clear the old token so existing configs cannot keep showing the bookmark row.
  "$HERDR" workspace report-metadata "$wsid" --source "$SOURCE" \
    --clear-token jj_bookmark \
    --token "jj_workspace=$workspace" --token "jj_change=$change" \
    --token "jj_status=$status" --token "jj_description=$description" >/dev/null 2>&1
}

# --- single workspace, for a per-workspace event hook ---
# Allowlist rather than "startup is the exception": anything we don't recognise as
# scoped to one workspace (startup, the action, a manual run) sweeps instead.
event="${HERDR_PLUGIN_EVENT:-}"
ctx="${HERDR_PLUGIN_CONTEXT_JSON:-}"
case "$event" in
  workspace.*|worktree.*) scoped=1 ;;
  *)                      scoped=0 ;;
esac
if [ "$scoped" -eq 1 ] && [ -n "$ctx" ]; then
  wsid="$(printf '%s' "$ctx" | jq -r '.workspace_id // empty' 2>/dev/null)"
  if [ -n "$wsid" ]; then
    cwd="$(printf '%s' "$ctx" | jq -r '.workspace_cwd // .focused_pane_cwd // empty' 2>/dev/null)"
    report "$wsid" "$cwd"
    exit 0
  fi
fi

# --- sweep all workspaces (startup / action / manual run) ---
# Map each workspace to its focused pane's cwd (else its first pane's cwd).
snap="$("$HERDR" api snapshot 2>/dev/null)" || exit 0
printf '%s' "$snap" | jq -r '
  .result.snapshot as $s
  | ($s.panes // []) as $panes
  | ($s.workspaces // [])[]
  | .workspace_id as $w
  | ( [ $panes[] | select(.workspace_id == $w and .focused) ][0]
      // [ $panes[] | select(.workspace_id == $w) ][0] ) as $p
  | "\($w)\t\($p.cwd // "")"
' 2>/dev/null | while IFS=$'\t' read -r wsid cwd; do
  report "$wsid" "$cwd"
done
