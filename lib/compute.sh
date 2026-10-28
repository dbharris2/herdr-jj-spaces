#!/usr/bin/env bash
# compute.sh <dir>
#
# Pure, side-effect-free read of a Jujutsu repo. Prints
# "<bookmark>|<workspace>|<change>|<status>|<description>" and exits 0 when <dir>
# is inside a jj repo. Exits 3 (no output) when <dir> is not a jj repo.
#
# Displayed tokens:
#   $jj_workspace    : current jj workspace name
#   $jj_change       : current change ID, prefixed with @
#   $jj_status       : ! ↑A↓D *N — conflict, remote ahead/behind, changed-file count
#   $jj_description  : first line of the current commit description
#
# Bookmark information is still used internally to calculate remote ahead/behind.

# All jj calls use --ignore-working-copy so reading never snapshots/mutates the
# working copy (this may run often), and --no-pager so nothing blocks.

set -o pipefail

dir="${1:?usage: compute.sh <dir>}"
remote="${JJ_STATUS_REMOTE:-origin}"
jj=(jj --no-pager --ignore-working-copy -R "$dir")

# Bare bookmark name(s), with "??" appended for a conflicted bookmark. jj's own
# "*" out-of-sync marker is intentionally dropped — we compute precise ↑↓ instead.
BM_T='local_bookmarks.map(|b| b.name() ++ if(b.conflict(), "??", "")).join(" ")'

tmpl() { "${jj[@]}" log -r "$1" --no-graph -T "$2" 2>/dev/null; }

# Every fact about @ in one read (pipe-delimited so empty fields survive parsing;
# a tab IFS would collapse them). Includes the dirty file count. A failure here
# also means "not a jj repo".
at="$(tmpl '@' 'if(conflict,"1","") ++ "|" ++ if(empty,"1","") ++ "|" ++ if(divergent,"1","") ++ "|" ++ change_id.shortest() ++ "|" ++ self.diff().files().len() ++ "|" ++ '"$BM_T")" || exit 3
IFS='|' read -r is_conflict is_empty is_divergent changeid files bookmark <<<"$at"

# Herdr workspace title is separate; use jj's actual workspace name here.
workspace="$("${jj[@]}" workspace list -T 'if(self.target().current_working_copy(), self.name(), "")' 2>/dev/null)" || exit 3
[ -n "$workspace" ] || workspace="$(basename "$dir")"
description="$(tmpl '@' 'description.first_line().replace("|", " ")')" || exit 3

# --- Resolve bookmark context for remote status --------------------------
# bmname = the single bookmark used for remote comparison ("" if none).
bmname=""
if [ -n "$bookmark" ]; then
  # On one or more local bookmarks -> just the name(s), no change id.
  bmname="${bookmark%% *}"; bmname="${bmname%'??'}"
else
  # Off any bookmark: anchor on the current change id.
  nearest="$(tmpl 'heads(::@ & bookmarks())' "${BM_T} ++ \"\\n\"" | grep -v '^$' | head -1)"
  if [ -n "$nearest" ]; then
    # Descendant of an ancestor bookmark: "<nearest>:: @id" (no depth count).
    bmname="${nearest%% *}"; bmname="${bmname%'??'}"
    bookmark="${nearest}:: @${changeid}"
  else
    # No bookmark anywhere: just the change id ("??" if divergent).
    bookmark="@${changeid}"
    [ -n "$is_divergent" ] && bookmark="${bookmark}??"
  fi
fi

# --- Build $jj_status: "! ↑A↓D *N" -------------------------------------
conflict=""; [ -n "$is_conflict" ] && conflict="!"

# Remote ahead/behind in a single call: over the union of both ranges, tag each
# commit by which side it's on. A failing call means the bookmark has no remote.
remote_group=""
if [ -n "$bmname" ]; then
  ahead_rs="${bmname}@${remote}..${bmname}"
  behind_rs="${bmname}..${bmname}@${remote}"
  if sides="$("${jj[@]}" log -r "${ahead_rs} | ${behind_rs}" --no-graph \
       -T 'if(self.contained_in("'"$ahead_rs"'"), "a\n", "b\n")' 2>/dev/null)"; then
    ahead=$(grep -c a <<<"$sides"); behind=$(grep -c b <<<"$sides")
    [ "$ahead" -gt 0 ] && remote_group+="↑${ahead}"
    [ "$behind" -gt 0 ] && remote_group+="↓${behind}"
  fi
fi

dirty=""; [ -z "$is_empty" ] && dirty="*${files}"

# Assemble: conflict+remote joined tight; a space before dirty only when a remote
# group is present (e.g. "↓1 *1", but "!*2" and "*2").
sep=""; [ -n "$remote_group" ] && [ -n "$dirty" ] && sep=" "
status="${conflict}${remote_group}${sep}${dirty}"
printf '%s|%s|@%s|%s|%s\n' "$bookmark" "$workspace" "$changeid" "$status" "$description"
