---
name: create-seed-topic
description: Create a new seed topic (word pack) in the sayit-words repo from the prompt "create seed topic:<topic>" - generate the words in the style of the existing packs, drop words already in any pack of the same pair, give the pack its own id block, update index.json and README, commit, push and report the pipeline result. TRIGGER on "create seed topic:...", "new seed topic", "new word pack", or "add words to topic <x>". DO NOT TRIGGER for editing single words in an existing pack (edit the file and use publish-word-packs).
---

# Create a seed topic

Prompt form: `create seed topic:<topic>`, optionally with pair, level, count, for example
`create seed topic: de-ru kitchen A2 80`.

## Inputs

- **Pair**: `en-ru` or `de-ru` (folder name). If the prompt does not say and the topic does not make it
  obvious (German words, "A1"/"A2" levels mean `de-ru`), ask one question with `ask_user`.
- **Topic**: display name in `index.json` (`Kitchen`, `IT Interview`). The file name (slug) is derived
  from it: lowercase words joined by `-` (`kitchen.data`). Pass `-Slug` for a different file name.
- **Level** (`A1`, `A2`, ...) and **tags** (lowercase, for example `food,home`): optional.
- **Count**: default 50.

## Steps

1. **Study the reference packs of the pair** to copy their style exactly:
   - `en-ru/*.data`: `foreign|translation` only. English in dictionary form, lowercase; Russian lowercase,
     several senses separated by `, `.
   - `de-ru/*.data`: `foreign|translation|grammar|example`. Nouns with article and capital letter
     (`die Birne`), grammar `Pl.: die Birnen` / `nur Singular` / `nur Plural`; verbs
     `ich ..., du ..., er ...; Prät.: ...; Perf.: hat/ist ...`; adjectives `Komp.: ...` when irregular, else
     empty. A short, simple German example sentence. Real umlauts and ß.
   - No `|` inside any field.
2. **Generate the candidates** for the topic: about 20% more than the count, because duplicates are
   dropped. Write them **without ids**, one per line, UTF-8, into a file in the session scratch directory
   (never inside the repo, `publish.ps1` commits everything there).
3. **Dry run** to see duplicates:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\tools\add-topic.ps1 -Pair de-ru -Topic "Kitchen" -Level A2 -Tags "food,home" -InputFile <scratch>\kitchen.txt -DryRun
   ```
   Duplicates are matched case-insensitively against every pack of the pair and inside the input, ignoring a
   leading `der/die/das/the/a/an/to`. If fewer than the requested count are new, generate replacements on
   the same topic and repeat until the count is reached (or the topic is exhausted - say so).
4. **Add and publish**:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\tools\add-topic.ps1 -Pair de-ru -Topic "Kitchen" -Level A2 -Tags "food,home" -InputFile <scratch>\kitchen.txt -Publish
   ```
   The script writes `<pair>/<slug>.data` (LF, no BOM) with ids from the next free block of 10000, adds the
   `index.json` entry (`name`, `level`, `tags`, `idFrom`, `idTo`) and runs `build-index.ps1`, adds the README
   id table row, runs `validate.ps1`, then `publish.ps1` commits, pushes and waits for the pipeline.
   If the pack already exists, the new words are appended with the next free ids of its block.
   Exit code 3 means nothing new was left to add.
5. **Report**: pair, file, id range, number of words added, the skipped duplicates, and the pipeline
   output with the final `RESULT` line (see `publish-word-packs`).

## Rules

- Never renumber or reuse ids; never edit or delete existing lines (deleting needs the user's approval).
- Commits use the user's git identity, with no AI co-author trailer (`git-commit-authorship`).
- Tags (`v1`, ...) are created only when the user asks.
- The SayIt app does not show the new pack yet: it bundles only `seed.data` and `seed_de_a1.data`
  until downloading packs is built.
