---
name: generate-words-for-database
description: Generate vocabulary word lists (English or German to Russian) for the SayIt database - build the list, check it for duplicates against the existing sayit.db3 and within the list, and add the approved words through the app's data layer. TRIGGER when the user asks to generate, collect, make or add words, a word list, or translations for the SayIt database, EN-RU or DE-RU, or asks to check words for duplicates. DO NOT TRIGGER for editing UI, feature code, or unrelated lists (interview questions, general knowledge, glossaries that are not for the app).
---

# Generate words for the SayIt database

Produce vocabulary entries for SayIt (`Word` table, `Words`) in the form
`ForeignWord` + `Translation` (Russian), with no duplicates in the list and none already
stored for the same `LanguagePair`.

## Inputs

Confirm these before generating. If something is missing or ambiguous, ask one focused
question with `ask_user`.

- **Language pair**: `EN-RU` or `DE-RU`. Pairs are stored separately and never mixed.
- **Topic or source** (for example, "most common 50 English words", "IT interview terms").
- **Count**: default 50 when the user does not say otherwise.

## Steps

1. **Generate the list.** Use the topic to build the words, one translation per row.
   - `ForeignWord`: the word or phrase in the foreign language, trimmed, in dictionary form
     (lowercase for English common words; keep German nouns capitalised).
   - `Translation`: Russian, lowercase, with a comma-separated list when there are several
     common senses (`способ, путь`).
   - Remove duplicates inside the list first, ignoring case and surrounding spaces.
2. **Check the database (read-only).** Compare every candidate against the stored words of
   the same `LanguagePair`. Match `ForeignWord` case-insensitively after trimming.
   - Copy the database to the scratch directory and inspect the copy. Never query or modify
     the device database directly.
   - On the emulator or a debuggable build, the file is `sayit.db3` in the app's data
     directory (`FileSystem.AppDataDirectory`), for example via
     `adb exec-out run-as com.sayit.app cat files/sayit.db3` written to the scratch folder.
   - Use the `sqlite3` CLI if it is available. Otherwise match whole words in the extracted
     text, and say in the answer that the check was textual.
3. **Resolve duplicates.** Drop candidates already stored and replace them with new words
   on the same topic, so the list still reaches the requested count.
   - If the database already contains duplicate rows, report them. Removing them is a
     deletion and needs explicit approval (see `global-rules`).
4. **Show the result for approval** as a table:

   | # | English | Russian |
   |---|---------|---------|
   | 1 | interview | собеседование |

   Then state how many were checked, how many were already in the database, and which
   were replaced.
5. **Add the approved words** only after the user confirms. Insert through the app's data
   layer, not raw SQL:
   - `new Word { ForeignWord = ..., Translation = ..., LanguagePair = ... }` with
     `Id == 0`, then the save method in `Data/DatabaseService.cs`. It assigns the next user id
     (`Word.UserIdStart` = 1000000 and up).
   - Defaults already give `Status = "InProgress"`, zero statistics, `Interval = 0`,
     `EaseFactor = 2.5`, `Repetitions = 0` and `DueDate = today`. Do not set them manually.
   - Adding words is additive and does not need deletion approval.
   - **Seed data (preferred for bundled lists).** Words live in a data file, never in C#.
     Put them in `Resources/Raw/<file>.data` (for example `seed.data`, `seed_de_a1.data`),
     one `id|foreign|translation` line per word (invalid lines are skipped).
   - **Ids are stable and permanent.** Seed ids are 1..999999 and must be unique across all
     seed files. IT Interview uses 1.., German A1 Exam uses 100001..; give a new topic its own
     range (for example 200001..). Append new words with the next free id in the topic's range.
     Never renumber or reuse ids: statistics and PL-7 progress are bound to them.
     `SayIt.Tests/SeedFilesTests.cs` checks format, range and uniqueness.
   - Each list is a topic: add a `SeedTopic(Name, LanguagePair, FileName)` to `SeedData.Topics`
     in `Data/SeedData.cs`. `SeedData.LoadAsync(topic)` reads the file with
     `FileSystem.OpenAppPackageFileAsync` and sets `Word.Topic`. The main page Topic picker
     lists topics from `SeedData.Topics` for the selected pair automatically.
   - Data files need no csproj entry: `SayIt.csproj` packages `Resources\Raw\**` as a
     `MauiAsset`. (`MauiRawAsset` does not package them.)
   - `DatabaseService.SeedAsync()` runs from `InitAsync()`. Whenever the seed files' hash
     (`SeedData.HashKey`) changes, it syncs seed words by id: it inserts new ids, updates the
     text or topic of changed ones (keeping their stats), and deletes seed rows (id < 1000000)
     whose id left the files. User words (id >= 1000000) are never touched. A one-time migration
     (`SeedData.IdMigrationKey`) moves old auto-increment databases to these ids by matching
     pair + foreign word.
   - Check the topic by pair when de-duplicating. German seed words use real umlauts and ß; seed files are UTF-8 (no BOM). Never blind-replace ae/oe/ue (Feuerwehr, teuer, zuerst, bequem stay as is).
   - To add words to an existing topic, append lines to its data file (IT Interview now has 459
     words; German A1 Exam has 1,000). An update install (`adb install -r`, same signing key)
     adds them and keeps existing progress. Rebuild the APK to ship them:
     `dotnet publish SayIt.csproj -f net10.0-android -c Release -p:AndroidPackageFormat=apk -o artifacts_apk`.
6. **Verify.** Re-run the duplicate check on the new database copy and confirm that every
   added word appears once for its pair. If code was changed to insert the words, run
   `dotnet build SayIt.csproj`.
7. **Publish.** After any seed change, follow `publish-word-packs/SKILL.md`: it commits,
   pushes to GitHub and reports the pipeline result automatically. For a whole new topic pack
   ("create seed topic:<topic>") use `create-seed-topic/SKILL.md` and `tools/add-topic.ps1`.

## Rules

- Never delete or overwrite existing words without explicit approval.
- Never mix pairs: an `EN-RU` word must not be stored as `DE-RU` and the reverse.
- Keep `LanguagePair` exactly `EN-RU` or `DE-RU`.
- Russian translations are data, so Cyrillic is expected here. The plain-ASCII rule
  applies to UI text only (see `AGENTS.md`).
- Do not commit unless the user asks.
- Do not store a snapshot of the database in this skill. Always check the current state.

## Output

- The word table, the count of checked and duplicate candidates, and the pair used.
- A short note on how the database was checked (copy plus `sqlite3` or textual match).
- Whether anything was added, and whether any duplicate rows remain pending approval.
