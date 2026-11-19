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

Ids must be below 1000000 (user words start there).

A fixed typo keeps its id. A deleted word's id is retired and never reused.
New packs get their own block, for example `de-ru/a2-exam` gets 110001 - 119999.

## Checks and publishing

- `tools/validate.ps1` checks format, BOM, id ranges and unique ids. GitHub Actions runs it on every push.
- `tools/publish.ps1` validates, commits, pushes and waits for the pipeline (`tools/watch-pipeline.ps1`).
  Add `-FromSayIt` to copy the bundled seed files from `..\SayIt\Resources\Raw` first.

The id ranges above are also listed in `tools/validate.ps1`. Update both when adding a pack.

## License

The word lists are licensed under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). See `LICENSE`.
