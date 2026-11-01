# Translation tools quick start

The maintained command reference is [tools/README.md](../README.md).
Translation decisions and review requirements are in
[TERMINOLOGY.md](../../TERMINOLOGY.md). This page is only a quick start.

From the repository root:

```sh
# Read-only coverage report
bash dots/.config/quickshell/ii/translations/tools/manage-translations.sh status

# Read-only structural validation
bash dots/.config/quickshell/ii/translations/tools/manage-translations.sh check --json

# Preview missing-key additions for one existing locale
bash dots/.config/quickshell/ii/translations/tools/manage-translations.sh sync -l zh_CN

# Apply only those additions, after reviewing the preview
bash dots/.config/quickshell/ii/translations/tools/manage-translations.sh sync -l zh_CN --apply
```

Default paths are script-relative, not relative to the current working directory.
Only `sync --apply` (or its `update` alias) writes. Existing translations and extra
keys are preserved; changed files receive exact-byte backups. New English fallback
values still need translation. `clean` only reports coverage and never deletes.
Static extraction can miss dynamic callers, so unobserved keys are not assumed
unused. Do not reuse retired locale build scripts or rejected translation drafts.
