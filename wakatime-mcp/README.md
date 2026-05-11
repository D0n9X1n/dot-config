# wakatime-mcp

Local MCP server that exposes WakaTime read-only tools (status bar, daily
summary, top languages/projects, durations, goals) to Claude Code and
Copilot CLI.

Vendored into this repo because there's no PyPI/GitHub upstream — `server.py`
and `wakatime_client.py` are the entire source. install.sh bootstraps a venv
under `~/.local/share/wakatime-mcp/venv/` on first run, then registers the
MCP entry pointing at it.

## API key

The WakaTime API key lives in `~/.wakatime.cfg` (the same file the
wakatime-cli uses):

```ini
[settings]
api_key = waka_xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

Get a key at <https://wakatime.com/settings/account>. The MCP entry that
install.sh writes to `~/.config/github-copilot/mcp.json` references this
key via the `WAKATIME_API_KEY` env var — but that file is gitignored, so
the key never lands in this repo.

## Tools exposed

- `get_coding_stats` — languages, projects, editors over a time range
- `get_summary` — daily breakdown across projects/languages/editors
- `get_status_bar` — current "what you're coding on" (sparse without a
  registered editor plugin like wakatime-vim)
- `get_projects`, `get_durations`, `get_goals`

## Updating

To upgrade the source after upstream changes (you maintain the upstream
copy elsewhere), copy `server.py` and `wakatime_client.py` here and
re-run install.sh — it'll re-pip-install if `requirements.txt` changed.
