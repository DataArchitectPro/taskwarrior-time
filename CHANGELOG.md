# Changelog

**English** · [Русский](#журнал-изменений)

All notable changes to **Taskwarrior Time** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.2] - 2026-09-29

### Fixed

- Data directory and plugin files (`debug.log`, `ui-settings.json`, `extra-projects.json`) are created/repaired as `0700` / `0600` so other local users cannot read task text from debug logs
- Debug `cmd.*` events no longer log free-text task descriptions (flags/UUIDs/verbs only)

## [1.0.1] - 2026-09-26

### Added

- About: **What's new**, **Report a problem**, **Open on GitHub**, and **Omarchy Marketplace** actions
- About: **Open log folder** and **Clear logs** for bug-report workflows
- Root `CHANGELOG.md` (EN/RU) and marketplace listing link in README (EN/RU)
- Debug sessions now write a human-readable banner plus an environment fingerprint (plugin, Taskwarrior, Timewarrior, Omarchy, OS/desktop/locale)

### Changed

- About tab redesigned with PanelHero, section headers, and bordered action buttons
- Debug log format upgraded to schema v1 NDJSON with `level` and `component`
- README (EN/RU) documents how to capture and attach a full debug log

### Fixed

- “Waiting for” text could fail to appear in the editor

### Screenshots

- Refreshed EN/RU About screenshots (`docs/screenshots/*/03-about.png`)

## [1.0.0] - 2026-09-23

### Added

- First public release: Omarchy bar widget over Taskwarrior + Timewarrior
- Task list with grouping, filters, in-place editor, projects tab
- Timers, dependencies, schedule fields, EN/RU UI
- Marketplace listing and signed GitHub release assets

[1.0.2]: https://github.com/DataArchitectPro/taskwarrior-time/releases/tag/v1.0.2
[1.0.1]: https://github.com/DataArchitectPro/taskwarrior-time/releases/tag/v1.0.1
[1.0.0]: https://github.com/DataArchitectPro/taskwarrior-time/releases/tag/v1.0.0

---

# Журнал изменений

[English](#changelog) · **Русский**

Здесь фиксируются заметные изменения **Taskwarrior Time**.

Формат основан на [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/),
версии следуют [Semantic Versioning](https://semver.org/lang/ru/).

## [1.0.2] - 2026-09-29

### Исправлено

- Каталог данных и файлы плагина (`debug.log`, `ui-settings.json`, `extra-projects.json`) создаются/чинятся как `0700` / `0600`, чтобы другие локальные пользователи не читали текст задач из debug-логов
- События debug `cmd.*` больше не пишут свободный текст описаний задач (только флаги/UUID/команды)

## [1.0.1] - 2026-09-26

### Добавлено

- Вкладка «О плагине»: **Что нового**, **Сообщить о проблеме**, **Открыть на GitHub**, **Маркетплейс Omarchy**
- **Открыть папку с логами** и **Очистить логи** для удобной отправки багрепортов
- Корневой `CHANGELOG.md` (EN/RU) и ссылка на маркетплейс в README (EN/RU)
- При включении отладки пишется человекочитаемый баннер и отпечаток окружения (плагин, Taskwarrior, Timewarrior, Omarchy, ОС/рабочий стол/locale)

### Изменено

- Вкладка «О плагине» переработана: PanelHero, секции, кнопки со рамкой
- Формат отладочного лога: schema v1 NDJSON с полями `level` и `component`
- README (EN/RU) описывает, как снять и приложить полный debug-лог

### Исправлено

- Текст «Чего ждём» мог не отображаться в редакторе

### Скриншоты

- Обновлены EN/RU скрины вкладки «О плагине» (`docs/screenshots/*/03-about.png`)

## [1.0.0] - 2026-09-23

### Добавлено

- Первый публичный релиз: виджет панели Omarchy поверх Taskwarrior + Timewarrior
- Список задач с группировкой, фильтрами, редактором на месте, вкладкой проектов
- Таймеры, зависимости, поля сроков, UI на EN/RU
- Листинг в marketplace и подписанные артефакты GitHub Release
