# Services and automation

English | [简体中文](Services-and-Automation-zh-CN.md)

`install.sh` sets up tools, local services, shared MCP data, WakaTime, and cleanup jobs.

Copilot uses its built-in GitHub integration; Claude uses authenticated `gh`. No extra GitHub MCP entry or PAT is needed. See [Repository operations](Repository-Operations.md) for shared MCP data and local-secret boundaries.

## New Mac setup

On macOS, the installer can add:

- Homebrew
- RMUX
- Claude Code from the Homebrew cask
- Copilot CLI and copilot-relay from npm
- oh-my-zsh
- shell tools such as `eza`, `jq`, `neovim`, and autojump
- Recursive and Nerd fonts
- RecMono Baker and St.Helens fonts from the MOSconfig release
- pinned Apollo theme releases for SonicTerm, RMUX, and eza
- local Apollo adapters for Claude, both status lines, and the shell prompt

The required Claude Code version is v2.1.217 or later. eza v0.23.5 or later is required for `theme.yml`.

Use these switches to skip slow setup work:

```sh
SKIP_BREW=1 ./install.sh
SKIP_NPM_GLOBALS=1 ./install.sh
SKIP_OH_MY_ZSH=1 ./install.sh
```

The install log is `~/Library/Logs/dot-configs-install.log`.

## Apollo release bundle

`scripts/apollo-releases.tsv` pins exact upstream tags and SHA-256 values. The installer reuses verified local blobs, builds all files under one bundle hash derived from the release lock and adapter code, and changes the `current` symlink only after the complete set validates. A second install uses the existing bundle without downloading or rewriting it.

A first install needs network access. Later installs work offline while the pinned blobs remain under `~/.local/share/dot-configs/apollo/`. A failed download or checksum keeps the previous bundle active. See [Apollo theme](Apollo-Theme.md).

## copilot-relay

The relay listens on:

```text
http://127.0.0.1:4142
```

The tracked config is `config/copilot-relay/config.yaml`. It installs as `~/.copilot-relay/config.yaml`.

Important values:

```yaml
claudeSetup: false
thinkEffort: medium
upstreamTimeoutSeconds: 600
gptModel: gpt-6-astra
opusModel: claude-opus-5
```

`claudeSetup: false` stops the relay from rewriting the linked Claude settings. The relay fallback remains `medium` for requests that omit effort. Claude's saved Sonnet preference and launchers use `high`, as do Copilot CLI's settings and `gg` launcher; explicit client effort takes precedence over the relay fallback. `upstreamTimeoutSeconds: 600` allows up to ten minutes for a single Claude request's upstream Copilot calls.

Login once:

```sh
npx copilot-relay auth
./install.sh
```

Auth and logs stay local under `~/.copilot-relay/`.

## launchd files

Files under `config/launchd/` are templates. They are not symlinks.

The installer replaces:

```text
__HOME__      with the home path
__REPO_ROOT__ with the repo path
```

It writes the result under `~/Library/LaunchAgents/`, then runs `bootout` and `bootstrap` for `gui/<uid>`.

Do not edit the rendered files. The next install will replace them.

## Relay service

`com.d0n9x1n.copilot-relay` starts the relay at login. It starts again after a crash, with a ten-second throttle.

Check it:

```sh
launchctl print "gui/$(id -u)/com.d0n9x1n.copilot-relay"
launchctl kickstart -k "gui/$(id -u)/com.d0n9x1n.copilot-relay"
```

Logs:

```text
~/Library/Logs/copilot-relay.out.log
~/Library/Logs/copilot-relay.err.log
~/.copilot-relay/logs/copilot-relay.log
```

## Relay health check

`com.d0n9x1n.copilot-relay-healthcheck` runs at load and every 60 seconds.

It has two checks:

1. `GET /healthz` on every run. A non-200 result restarts the relay.
2. `copilot-relay status --deep --json` every 900 seconds, with a 45-second timeout. This sends a real request through Copilot.

A 200 from `/healthz` only means a socket is listening. The deep check also tests auth and upstream access.

Deep result:

| Exit | Meaning | Action |
|---|---|---|
| `0` | Relay works | Do nothing |
| `1` | Probe reports relay not running | Recheck local health; leave it running if HTTP 200 |
| `2` | Health or upstream probe failed | Recheck local health; leave it running if HTTP 200 |
| `124` | Diagnostic timed out | Stop only the diagnostic; recheck local health |
| Other nonzero | Diagnostic failed | Recheck local health; leave it running if HTTP 200 |

A failed deep check never restarts a locally healthy relay, even after repeated failures. Recovery runs only when the fresh local check is also unhealthy. The interval timestamp is written before the probe, so failure does not trigger paid requests every minute. Recovery checks local health only; the next deep probe waits for the normal interval.

Failure logs keep the exit code, fresh local status, and allowlisted booleans, bounded timings, and HTTP codes from the same JSON probe. Raw details, credentials, paths, prompts, and stderr are never copied into the watchdog log. Invalid or missing JSON is logged as `diagnostic=unavailable` and does not change the recovery decision. Exit `2` is not assumed to be expired auth; check upstream availability and run auth again only when needed.

Tune the deep check with:

```text
COPILOT_RELAY_DEEP_INTERVAL
COPILOT_RELAY_DEEP_MAX_TIME
```

Set the interval to 0 to turn off the deep check.

Health logs and state:

```text
~/Library/Logs/copilot-relay-healthcheck.log
~/Library/Caches/copilot-relay-healthcheck.deep
```

## npm cache cleanup

`com.d0n9x1n.npm-cache-clean` runs each Sunday at 03:17. It does not run at install time.

It:

- runs `npm cache clean --force`;
- removes `~/.npm/_npx` copies older than 14 days by folder change time;
- keeps Playwright browsers in `~/Library/Caches/ms-playwright`.

Run it now:

```sh
launchctl kickstart -k "gui/$(id -u)/com.d0n9x1n.npm-cache-clean"
```

Its main log is `~/Library/Logs/npm-cache-clean.log`. The script keeps at most 500 lines.

## MCP merge

`config/mcp/mcp-shared.json` contains only safe shared entries.

The installer merges them into local Copilot MCP data and then imports the server map into `~/.claude.json`.

Keys and tokens for optional MCP servers stay in local `~/.config/github-copilot/mcp.json`. Never put them in the shared file.

## WakaTime

Copilot uses the official `wakatime/copilot-cli-wakatime` plugin. Claude uses the official `wakatime/claude-code-wakatime` plugin.

The installer reads the key from `~/.wakatime.cfg`. If no key exists and the install is interactive, it asks for the key twice without printing it.

The installer also removes old WakaTime paths:

- the old local WakaTime MCP runtime and entries;
- Homebrew `wakatime-cli`;
- the old `@geeknees/copilot-cli-wakatime` npm package.

## Verify

```sh
curl -fsS http://127.0.0.1:4142/healthz
copilot-relay status --deep; echo "exit=$?"
launchctl print "gui/$(id -u)/com.d0n9x1n.copilot-relay"
launchctl print "gui/$(id -u)/com.d0n9x1n.copilot-relay-healthcheck"
launchctl print "gui/$(id -u)/com.d0n9x1n.npm-cache-clean"
scripts/check.sh all
```

See [Repository operations](Repository-Operations.md) for the manifest and safe links.
