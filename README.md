# SayIt words

Word packs for the SayIt app. One folder per language pair, one file per topic.

## Format

UTF-8 without BOM, LF, one word per line:

`id|foreign|translation[|grammar|example]`

No `|` inside fields.

## Id ranges (never renumber or reuse ids)

| Pack | Range | Used |
|---|---|---|
| en-ru/it-interview | 1 - 99999 | 1 - 459 |
| de-ru/a1-exam | 100001 - 109999 | 100001 - 101000 |
| en-ru/travel | 110001 - 119999 | 110001 - 110080 |

Ids must be below 1000000 (user words start there).

A fixed typo keeps its id. A deleted word's id is retired and never reused.
New packs get their own block, for example `de-ru/a2-exam` gets 110001 - 119999.

## Catalog `index.json`

The app downloads `index.json` first and then only the packs the user picks. Each pack entry has:

| Field | Source |
|---|---|
| `name`, `level`, `tags`, `idFrom`, `idTo` | edited by hand |
| `id`, `pair`, `file`, `words`, `sha256` | computed from the pack file |
| `version` | raised by 1 whenever `sha256` changes |

`sha256` is the hash of the file with LF line endings, as served by GitHub.
`tools/build-index.ps1` regenerates the file; never edit the computed fields by hand. A new pack file
gets an entry with the next free id block; then set its `name`, `level` and `tags`.

## Checks and publishing

- `tools/build-index.ps1` regenerates `index.json`. `-Check` only reports whether it is up to date.
- `tools/validate.ps1` checks format, BOM, ids inside the `index.json` ranges and unique ids.
  GitHub Actions runs it and `build-index.ps1 -Check` on every push.
- `tools/add-topic.ps1` adds a new topic from a list of `foreign|translation[|grammar|example]` lines without
  ids: skips words already in the pair, assigns the next free id block, updates `index.json` and the table
  above, validates, and with `-Publish` commits and pushes. `-DryRun` only lists the duplicates.
- `tools/publish.ps1` rebuilds the index, validates, commits, pushes and waits for the pipeline
  (`tools/watch-pipeline.ps1`). Add `-FromSayIt` to copy the bundled seed files from `..\SayIt\Resources\Raw` first.

The id ranges above come from `index.json`. Keep this table in sync when adding a pack.

## License

The word lists are licensed under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). See `LICENSE`.
