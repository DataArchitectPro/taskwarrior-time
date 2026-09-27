# Taskwarrior Time

**English** · [Русский](README.ru.md)

**Taskwarrior Time** is an [Omarchy](https://omarchy.org/) bar widget that brings **Taskwarrior** and **Timewarrior** into the shell panel. Create, edit, filter, and time-track tasks without leaving the desktop.

Marketplace: [plugins.omarchy.org/plugin.html?id=taskwarrior-time](https://plugins.omarchy.org/plugin.html?id=taskwarrior-time)

![Taskwarrior Time panel](docs/screenshots/en/00-hero.png)

## What this is

**Taskwarrior Time** (plugin id `taskwarrior-time`) is a **GUI companion** for the classic CLI task stack — not a separate task database.

| Component | Role |
| --- | --- |
| [Taskwarrior](https://taskwarrior.org/) (`task`) | Source of truth for tasks, projects, priorities, dates, dependencies, and status |
| [Timewarrior](https://timewarrior.net/) (`timew`) | Time tracking: start/stop timers and today totals (optional but recommended) |
| Omarchy shell | Host panel: this plugin talks to `task` / `timew` through a small local helper |

Anything you do here is stored in your normal Taskwarrior / Timewarrior data. You can still use the same tasks from the terminal (`task`, `timew`) — the panel is an add-on UI on top of those tools.

## Features

- **Task list** with grouping (project, priority, due, status) and a collapsible advanced filter
- **Create & edit** in place: title, details, status (Waiting / In progress / Done), waiting-for, outcome, priority, project
- **Schedule** fields (scheduled / due), **dependencies** (depends / blocks), and **Timewarrior** timers with manual time adjust
- Progressive **list meta**: project · priority · due (Today / Tomorrow / Overdue) · blocked — colors follow the Omarchy theme
- **Projects** view: browse projects, rename, clear project from tasks
- **Unsaved changes** dialog when closing a dirty editor (Save / Keep editing / Discard)
- Uniform **hotkeys**: `Ctrl+Enter` commit, `Esc` cancel, `Ctrl+Delete` destroy
- **i18n**: English and Russian UI (system language, or pick one in About)
- **About** tab with version, developer info, GitHub link, language switch, and debug logging toggle

### Task list

![Task list](docs/screenshots/en/01-panel-list.png)

### Grouping

Group the list by project, priority, due, or status from the toolbar.

![Grouping by project](docs/screenshots/en/07-grouping.png)

### Filter & search

Expand **Filter** to narrow by status, project, priority, due, timer, and dependencies, plus a free-text search over descriptions.

![Advanced filter](docs/screenshots/en/04-filter.png)

### New task composer

The sticky composer at the bottom expands into the same field layout as the editor: details, status, waiting-for, priority, project, and optional schedule / deps / time under a spoiler.

![New task form](docs/screenshots/en/05-new-task.png)

![New task — schedule, links, time](docs/screenshots/en/08-new-task-advanced.png)

### Task editor

Click a task to edit it in place. Save when dirty (`Ctrl+Enter`), Cancel (`Esc`) to collapse, or Delete (`Ctrl+Delete`).

![Task editor](docs/screenshots/en/02-panel-edit.png)

![Task editor — advanced fields](docs/screenshots/en/09-edit-advanced.png)

### Projects

Switch to **Projects** to list projects, rename them, clear a project from all tasks, or add a new one.

![Projects view](docs/screenshots/en/06-projects.png)

## Requirements

- [Omarchy](https://omarchy.org/) Linux (Quickshell bar / plugin system)
- [Taskwarrior](https://taskwarrior.org/) (`task`) — install the `task` package from your distro
- [Timewarrior](https://timewarrior.net/) (`timew`) — optional but recommended for timers; install the `timew` package from your distro

The plugin does not install system packages itself. On Arch Linux the package names are `task` and `timew`.

## Install (Linux / Omarchy)

Preferred — Omarchy clones and enables the plugin for you:

```bash
omarchy plugin add https://github.com/DataArchitectPro/taskwarrior-time.git --enable --yes
```

Then place the widget on the bar if it is not already there (the installer may ask for a section), or add it manually:

```bash
omarchy bar move taskwarrior-time --section right
```

Reload the shell if the icon does not appear:

```bash
omarchy restart shell
```

### Developer checkout

For local development, place or clone this repository at `~/.config/omarchy/plugins/taskwarrior-time`, then:

```bash
omarchy plugin enable taskwarrior-time --section right
omarchy restart shell
```

The plugin id is `taskwarrior-time` (folder name under `~/.config/omarchy/plugins/`). The marketplace display name is **Taskwarrior Time**.

## Update

If the plugin was installed with `omarchy plugin add` (git remote present):

```bash
omarchy plugin update taskwarrior-time --yes
```

Or manually:

```bash
git -C ~/.config/omarchy/plugins/taskwarrior-time pull --ff-only
omarchy restart shell
```

Saved files under `~/.config/omarchy/plugins/` are hot-reloaded by the shell; a full restart is only needed if something fails to apply.

## Uninstall

```bash
omarchy plugin remove taskwarrior-time
```

This disables the widget and deletes the git checkout under `~/.config/omarchy/plugins/taskwarrior-time`. Your Taskwarrior / Timewarrior data is not removed.

## Usage

1. Left-click the Taskwarrior Time icon on the bar to open the panel.
2. Use **Tasks** / **Projects** in the header to switch views.
3. Expand **Filter** when you need status / project / priority / due / timer / deps or search.
4. Click a task to expand the editor; **Save**, **Cancel**, or **Delete** at the bottom of the card.
5. Focus the composer at the bottom to add a new task with the full form.
6. Open **About** in the header tabs for version info, GitHub, and debug logging.

![About & debug](docs/screenshots/en/03-about.png)

## Debug logging

When something misbehaves, turn on debug logging from the **About** tab.

1. Open **About** → enable **Debug log**.
2. Reproduce the bug once (a fresh session banner is written when logging starts).
3. Use **Open log folder**, attach `~/.local/share/taskwarrior-time/debug.log` to your issue.
4. Optionally **Clear logs** before a clean capture, then toggle logging again.

Each session file starts with a short human-readable banner plus environment facts:

- plugin id / version
- Taskwarrior, Timewarrior, and Omarchy versions (when available)
- OS / desktop / locale / UI language
- data and log paths

Then events are appended as **NDJSON** (one JSON object per line) with `level` (`info` / `warn` / `error`), `component` (`ui` / `helper` / `system`), `event`, and `detail`. Long free-text is truncated so logs stay safe to share — still avoid pasting secrets or private task content.

The log is local only (it is not uploaded). Toggle logging **OFF** when you are done.

## Reporting issues

If you hit a bug, a crash, wrong Taskwarrior/Timewarrior behavior, or a missing feature:

1. Check [existing issues](https://github.com/DataArchitectPro/taskwarrior-time/issues).
2. Open a [new issue](https://github.com/DataArchitectPro/taskwarrior-time/issues/new) with:
   - Omarchy / Taskwarrior Time version (see About)
   - Steps to reproduce
   - Expected vs actual behavior
   - The full `~/.local/share/taskwarrior-time/debug.log` from a session with Debug logging ON (banner includes dependency versions)

Please do **not** paste secrets, tokens, or private task content.

## Development checks

From a clone of this repository:

```bash
./scripts/enable-git-hooks   # once per clone — enables pre-push checks
./scripts/check           # manifest validate + qmllint
```

`git push` runs the same checks via `.githooks/pre-push` and aborts if they fail. GitHub Actions runs `./scripts/check` on push and pull requests.

## License

[MIT](LICENSE) — free to use, copy, modify, merge, publish, distribute, sublicense, and sell. Keep the copyright notice.

## Author

**DataArchitectPro** — [GitHub repository](https://github.com/DataArchitectPro/taskwarrior-time) · [Omarchy marketplace](https://plugins.omarchy.org/plugin.html?id=taskwarrior-time)
