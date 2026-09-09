# simple-claude-switch (scs)

Switch between multiple [Claude Code](https://claude.com/claude-code) accounts
without keeping separate `CLAUDE_CONFIG_DIR`s around.

## Why

Claude Code ties a login to `~/.claude/.credentials.json` and
`~/.claude.json`. If you use multiple accounts (e.g. personal + work), the
usual workaround is a full second config directory per account — which means
duplicating MCP servers, plugins, settings, and project history for every
account.

`scs` takes a different approach: there is only **one** config directory.
Switching accounts only swaps the account-specific fields:

- `claudeAiOauth` in `$CLAUDE_CONFIG_DIR/.credentials.json` (the OAuth token)
- `oauthAccount` in `~/.claude.json` (the account identity)

Everything else — MCP servers, project history, settings, plugins — stays
shared and is never duplicated.

## Requirements

- `jq`
- bash or zsh

## Install

```bash
curl -o ~/.scs.sh https://raw.githubusercontent.com/felix-berlin/simple-claude-switch/main/scs.sh
echo 'source ~/.scs.sh' >> ~/.zshrc   # or ~/.bashrc
source ~/.zshrc
```

## Usage

```bash
claude                 # log in (account A)
scs save work          # save the current login as profile "work"

claude /logout && claude   # log in (account B)
scs save personal

scs use work           # switch back any time, no login needed
scs use personal

scs list               # show saved profiles
scs current            # show the currently active account/profile
scs remove <name>       # delete a saved profile
```

When switching, `scs` offers to kill running `claude` CLI sessions so they
restart under the new account. It does not reconnect the VS Code extension —
reload the window manually (`Developer: Reload Window`) after switching.

## How it works

`scs save <name>` snapshots the relevant fields of your current login into
`~/.scs-profiles/<name>/`. `scs use <name>` merges those fields back into
`~/.claude/.credentials.json` and `~/.claude.json`, backing up the previous
state as `.bak` files first.

## License

MIT
