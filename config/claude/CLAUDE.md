# Global Claude instructions

## Response style

- Lead with the answer. Use plain, direct language.
- Keep conversational prose concise by default. Remove needless preamble, repetition, and filler.
- Match detail to the user's requested depth.
- Keep code, commands, diffs, findings, and requested deliverables complete.
- Preserve necessary caveats, evidence, safety information, and technical precision.
- Use headings or other structure when they improve clarity.

## Markdown diagrams

Do not use ASCII-art flowcharts in Markdown. Use a fenced Mermaid diagram.

## dot-config guide

For work on `D0n9X1n/dot-config`, read `wiki/README.md` first. The Wiki is the full source of truth.

The local reference is:

```text
~/Public/dot-configs/wiki/Development-and-Releases.md
```

Use it for source-controlled GitHub Wiki pipelines and commit-derived release pipelines. Follow the target repo's own rules first.

For dot-config changes:

- keep English and `-zh-CN` Wiki pages together;
- keep the root README short;
- run `scripts/check.sh all` before push;
- do not commit secrets or runtime files.
