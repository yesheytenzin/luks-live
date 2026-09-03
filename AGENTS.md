# luks-live — Agent Guidelines

## Tool Preference — File Creation / Editing

**ALWAYS prefer `default.write` / `default.edit` over `default.bash` heredocs.**

- **New file** (including python scripts like `/tmp/sim_plymouth.py`) → `default.write({ path, content })`
  - Do NOT use `bash` with `cat > file <<'PY'`, `echo >`, or `printf >`
  - `write` auto-creates parent dirs and is not truncated

- **Modify existing file** → `default.edit({ path, edits: [{ oldText, newText }] })`
  - `oldText` must be exact, unique, minimal context (2-5 lines)
  - Use multiple entries in `edits[]` for disjoint changes — do not overlap
  - For nearby changes, merge into one edit

- **Run code** → `default.bash` ONLY to execute (`python /tmp/foo.py`, `npm test`, `ls`)
  - Never to create/overwrite files

This matches `opencode`'s `edit` tool — in `pi` it's split into `write` (create) + `edit` (patch).

## Project Context

- Omarchy Quattro shell plugin (QML) — see `manifest.json`, `Panel.qml`, `BarWidget.qml`
- Do not use `rm -rf` with force — guarded by `destructive-guard`
