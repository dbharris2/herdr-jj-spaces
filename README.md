# herdr-jj-status

A [herdr](https://herdr.dev) plugin that shows the current Jujutsu (jj)
workspace, change ID, status, and commit description in the spaces sidebar.

For plain-git workspaces it does nothing: the built-in git row is left untouched.

## How it works

The plugin reports four custom sidebar tokens:

| token | contents |
| ----- | -------- |
| $jj_workspace | Current jj workspace name |
| $jj_change | Current change ID, prefixed with @ |
| $jj_status | ! ↑A↓D *N — conflict, remote ahead/behind, changed-file count |
| $jj_description | First line of the current commit description |

The status markers mean: ! is a conflict, ↑A / ↓D are remote ahead / behind
counts, and *N means the current change contains N changed files. Set
JJ_STATUS_REMOTE to compare against a remote other than origin.

Rows refresh when you switch into a space or run the refresh action (and once at
herdr startup). Herdr has no event for commands run inside a pane, so a row will
not update live while you stay put — switch away and back, or trigger the action.

## Requirements

- herdr ≥ 0.7.5
- `jj` and `jq` on `PATH`

## Install

```sh
# From GitHub:
herdr plugin install mroth/herdr-jj-status

# …or from a local checkout (for development):
herdr plugin link /path/to/herdr-jj-status
```

Confirm it linked:

```sh
herdr plugin list
```

## Configure the sidebar

Add a jj row to `ui.sidebar.spaces.rows` in `~/.config/herdr/config.toml`. The
default is:

```toml
[ui.sidebar.spaces]
rows = [["state_icon", "workspace"], ["branch", "git_status"]]
```

Put the jj workspace, change ID, and status alongside the space name, with the commit description on the second row:

```toml
[ui.sidebar.spaces]
rows = [["state_icon", "workspace", "$jj_workspace", "$jj_change", "$jj_status"], ["$jj_description"]]
```

Then reload:

```sh
herdr server reload-config
```

The description row is empty for non-jj workspaces and collapses automatically.

### Optional: bind a refresh key

To refresh all rows on demand, invoke the action:

```sh
herdr plugin action invoke refresh --plugin mroth.jj-status
```

Bind that to a key via your herdr keybinding config if you want instant refresh
after running `jj` commands without switching spaces.

## Uninstall

```sh
herdr plugin uninstall mroth.jj-status   # installed from GitHub
# …or, if you linked a local checkout:
herdr plugin unlink mroth.jj-status
```

Remove the `$jj_workspace`, `$jj_change`, `$jj_status`, and
`$jj_description` tokens from `ui.sidebar.spaces.rows` and
`herdr server reload-config`.
