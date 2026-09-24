# Services and automation

English | [简体中文](Services-and-Automation-zh-CN.md)

`install.sh` sets up tools, local services, shared MCP data, WakaTime, and cleanup jobs.

Copilot uses its built-in GitHub integration; Claude uses authenticated `gh`. No extra GitHub MCP entry or PAT is needed. See [Repository operations](Repository-Operations.md) for shared MCP data and local-secret boundaries.

## New Mac setup

On macOS, the installer can add:

- Homebrew
- native tmux and RMUX
- Claude Code from the Homebrew cask
- Copilot CLI and copilot-relay from npm
- oh-my-zsh
- shell tools such as `eza`, `jq`, `neovim`, and autojump
- Recursive and Nerd fonts
- RecMono Baker and St.Helens fonts from the MOSconfig release
- pinned Apollo theme releases for SonicTerm, RMUX, native tmux, and eza
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

## Multiplexer lifetime

Native tmux and RMUX use separate servers, helpers, and state. They share the Apollo theme and status style, not live sessions.

`tt`/`tr` start a new native tmux server through a detached bootstrap and verify parent PID 1 before attaching. Existing servers are reused, not restarted or forcibly reparented. SonicTerm owns only the attached client. Closing its tab or quitting SonicTerm leaves the server and panes running; `ts` is not needed. `td` deliberately deletes a session. A server crash or reboot still loses live processes.

Native tmux uses `~/.local/state/tmux-store/<socket-hash>/`. Helpers use the default socket outside tmux and the current native socket inside. RMUX keeps its existing state and retained client/daemon pair. Native `tmux-store` references a compatible Homebrew executable; it does not relocate binaries or guarantee that arbitrary Homebrew cleanup preserves all dependencies.

`ts` saves every session on the selected native socket, including detached sessions. It refuses unknown or mismatched binaries, unstable or invalid snapshots, and failed preflight. An explicit interactive `yes` is required before stopping the server. Restore opens fresh shells with saved names, directories, layouts, dimensions, and active selections. It never replays processes, restores history, or autosaves.

Installation does not reload or stop live tmux or RMUX servers. Never run `ts` or `rs` automatically. See [Tmux](Tmux.md) and [RMUX](RMUX.md) for manual upgrade and reload steps.

## copilot-relay

The relay listens on:

```text
http://127.0.0.1:4142
```

The tracked config is `config/copilot-relay/config.yaml`. It installs as `~/.copilot-relay/config.yaml`.

Important values:

```yaml
claudeSetup: false
thinkEffort: xhigh
upstreamTimeoutSeconds: 600
gptModel: gpt-6-astra
opusModel: claude-opus-5.5
```

`opusModel` uses the canonical upstream ID without `[1m]`. Claude starts with native `claude-opus-5-5[1m]` and routes to Opus 5.5. Sonnet/Haiku requests and the blank WebSearch backend still use Astra. See [Claude Code](Claude-Code.md) for the Opus tool-selection limit.

`claudeSetup: false` stops the relay from rewriting the linked Claude settings. The relay's `thinkEffort` fallback and Claude's saved Opus preference, launchers, and status-line fallback use `xhigh`. Explicit client effort still takes precedence. Copilot CLI and `gg` retain their separate Astra/`high` defaults. Model routes and relay effort hot-reload without a restart; existing shells need their Claude launchers reloaded or a new shell. `upstreamTimeoutSeconds: 600` allows up to ten minutes for a single Claude request's upstream Copilot calls.

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

### Friendly startup names

The launchers use descriptive names for macOS Background Items attribution; they do not rename running processes or change job labels, schedules, arguments, or recovery behavior:

| Job label | Launcher name |
|---|---|
| `com.d0n9x1n.copilot-relay` | Copilot Relay |
| `com.d0n9x1n.copilot-relay-healthcheck` | Copilot Relay Health Check |
| `com.d0n9x1n.npm-cache-clean` | Weekly npm Cache Cleanup |

All three names have been verified in Background Task Management (BTM). BTM can refresh a name from a changed file while launchd retains the running job's old definition; these are separate states. The loaded relay definition updates on later re-registration, without requiring an immediate restart for naming. Verify attribution with `sfltool dumpbtm`, not the filename alone, and never reset BTM to refresh names. These launcher links require the checkout to stay at its installed path; rerun the installer after moving it.

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

Its executable entry point is `~/.local/libexec/Copilot Relay Health Check`, linked to the tracked launcher in `scripts/launchd/`. The launcher replaces itself with `/bin/bash` running the existing health-check script; the job label, schedule, arguments, and recovery policy stay unchanged. The descriptive filename targets macOS Background Items attribution, not the running process name, which remains Bash. Check `sfltool dumpbtm` after installing to verify the name on the current macOS version; do not reset the background-item database to refresh it.

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

## Vendor startup-item names

`startup-item-names` is a one-shot review tool, not a service. Its default is a read-only preview; only an explicit user-scope apply or rollback writes an overlay:

```sh
startup-item-names
startup-item-names --apply
startup-item-names --rollback
```

Apply and rollback are user-only; the tool refuses to run them as root. The reviewed V2rayU mappings are:

| Job label | Friendly name |
|---|---|
| `yanue.v2rayu.v2ray-core` | V2rayU V2Ray Proxy Core (Legacy) |
| `yanue.v2rayu.xray-core` | V2rayU Xray Proxy Core |
| `yanue.v2rayu.sing-box` | V2rayU sing-box Proxy Core |
| `yanue.v2rayu.tun-helper` (system) | V2rayU TUN Network Helper — separate administrator setup |

The three user cores retain their `~/.V2rayU` working directory. The system TUN name was verified after a separately authorized, root-owned fixed-target launcher was installed under `/Library/PrivilegedHelperTools/`; the user overlay tool does not manage it. Validation used the binary's `version` command, not TUN startup. Its configuration remains absent and full TUN operation is untested; naming must not enable or start it. The loaded definition can retain the old executable until re-registration, and V2rayU updates may restore it.

Signed app associations cover Adobe, Charles, AutoUpdate, the iStat installer, and Steam only when the legitimate app and helper TeamIDs match. System-scope changes require separate administrator review and application with macOS built-in tools, not elevated execution of this user-managed tool.

Apply and rollback preserve blocked/allowed state. The tool does not reload services, reset the background-item database, or edit signed app bundles. Backups stay local under `~/.local/state/dot-configs/startup-names/`, never in the repository. Vendor updates may restore old names; review again before reapplying. Conflicting changes are refused, not silently overwritten. Verify actual attribution with `sfltool dumpbtm`; an overlay does not guarantee an immediate display change.

Not every detail name should change: the iStat daemon and TeamViewer helpers already have meaningful grouped app associations. The Teams agent, CleanerOne `TCLoginItemHelper`, and Quick Look/Spotlight extensions use vendor-internal signed names. Map those names to their purpose rather than overwriting them.

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
