# Translation maintenance tools

Reusable tools for contributors. Python 3 and Bash are the only requirements.
Translation decisions belong in [TERMINOLOGY.md](../TERMINOLOGY.md);
these tools validate structure and coverage, not linguistic quality.

## Safe defaults

Every command is read-only unless **`sync --apply`** or **`update --apply`** is
explicitly requested. Sync only appends keys missing from an existing locale,
using `en_US.json` as the reference. It never removes keys, overwrites translated
values, reorders existing keys, or creates a new locale. Review and translate the
new English fallback values before committing them.

Static extraction cannot prove that an unobserved key is unused. Legacy,
script-only, and dynamic keys must remain unless a contributor has independently
confirmed their removal. `clean` is a coverage report, not a deletion command.
The former `--yes` and `--no-backup` shortcuts now fail instead of approving writes.

## Commands

Run these examples from the repository root. Default paths are relative to the
tool itself, so invoking the script by its absolute path works from any directory.

```sh
# Coverage across QML/JS, Files extensions, updater scripts, and locale catalogs
bash dots/.config/quickshell/ii/translations/tools/manage-translations.sh status

# Structural validation of all locales, with machine-readable output
bash dots/.config/quickshell/ii/translations/tools/manage-translations.sh check --json

# Extract literal source keys to stdout; creates no temporary catalog
bash dots/.config/quickshell/ii/translations/tools/manage-translations.sh extract

# Preview additions to one existing locale; no files are modified
bash dots/.config/quickshell/ii/translations/tools/manage-translations.sh sync -l ko_KR

# Explicitly append missing en_US keys after reviewing the preview
bash dots/.config/quickshell/ii/translations/tools/manage-translations.sh sync -l ko_KR --apply
```

| Command | Behavior |
| --- | --- |
| No command / `status` | Report source coverage and missing/extra catalog keys. |
| `check` | Run `catalog-qa.py`; accepts locale and catalog-directory options. |
| `extract` | Print extracted keys as a JSON object. |
| `sync` / `update` | Preview missing-key additions; only `--apply` writes. |
| `clean` | Same read-only coverage report as `status`. |

Use `--json` for machine-readable reports. `-l` / `--lang` selects one existing
locale; `-t` / `--trans-dir` overrides the catalog directory. Source operations
also accept `-s` / `--source-dir`, repeated `--scripts-dir` roots, and
`--extensions-dir`. Always quote paths that contain spaces. Source-directory
options and `--apply` are not accepted by `check`.

Reports and checks return **0** on success, **1** for coverage or validation
failures, and **2** for invalid arguments or a fatal input error. A sync preview
returns 0 when it can produce a valid plan, even if that plan includes additions.
Runtime input failures with `--json` are JSON; invalid CLI arguments are reported
by the argument parser on stderr.

## Direct entry points

- `translation-manager.py`: default coverage report, `--extract-only`,
  `--check-qml`, `--check-extensions`, `--check-scripts`, and `--sync [--apply]`.
- `translation-cleaner.py`: compatibility entry point. `--clean` is read-only;
  `--sync [--apply]` uses the same add-only synchronization. Only `en_US` is a
  supported reference language.
- `catalog-qa.py [LOCALE ...]`: placeholders, printf argument order, markup,
  Markdown, URLs, paths, command flags, filenames, shortcuts, numbers, joining
  whitespace, and protected literal names. Also accepts `--language LOCALE`,
  `--translations-dir DIR`, and `--json`.

QA allows Qt placeholders to move while preserving printf argument order.
English-identical counts are review aids, not automatic translation failures.
A successful check does not establish accuracy, natural wording, accessibility,
or visual fit. Review source context and the terminology guidance as well.

## Extraction and write guarantees

The manager scans literal `Translation.tr(...)` calls in QML/JS, including calls
inside template expressions; it skips comments, string examples, and dynamic
arguments. It reads literal `tr(...)` calls and module-level `*_TEXT` values in
Files extensions, plus static shell `t`/`tf` calls. Repo defaults include `sdata`
and the shell scripts under `ii/scripts`. A custom source tree does not borrow
extensions from the running desktop. Extraction is conservative and is not a
full QML, JavaScript, or shell interpreter; review dynamic keys separately.

Before applying synchronization, all selected catalogs must parse successfully,
have unique keys and nonempty string values, and pass path checks. A changed
catalog gets an adjacent, uniquely named `.bak` containing its exact original
bytes and is replaced atomically. No-op catalogs retain their bytes and mtime.
Keep or remove backups yourself after reviewing the result; they are not shipped.

The five one-off `build_<locale>.py` scripts have been retired. Rejected archived
drafts and converted Simplified Chinese are not translation sources. Write new
locale values directly from English using the canonical guidance.

## Tests

Tests run only against temporary fixtures and never modify shipped catalogs:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover \
  -s dots/.config/quickshell/ii/translations/tools -p 'test_*.py'
bash -n dots/.config/quickshell/ii/translations/tools/manage-translations.sh
```

`test_catalog_qa.py` covers structural validation; `test_translation_tools.py`
covers extraction, read-only defaults, explicit additions, backups, malformed
input, paths with spaces, and rejected destructive legacy options.
