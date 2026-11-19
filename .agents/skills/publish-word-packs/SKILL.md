---
name: publish-word-packs
description: Publish changed word packs of the sayit-words repo - validate, commit, push to GitHub and wait for the GitHub Actions result, then report it. TRIGGER automatically after any change to a pack (`<pair>/<topic>.data`), to the bundled SayIt seed files (`SayIt/Resources/Raw/*.data`) that must reach GitHub, or when the user asks to publish, push, sync the packs or check the pipeline. DO NOT TRIGGER for SayIt app code changes that do not touch seed words.
---

# Publish word packs

The GitHub repo `KseniiaSharp/sayit-words` is the master copy of the word lists. Every seed
change is committed and pushed **automatically, without asking**, as the last step of the task
that changed the words. This skill is the user's standing request to commit and push.

## Files

- `tools/validate.ps1` - checks every pack: UTF-8 without BOM, `id|foreign|translation[|grammar|example]`,
  ids inside the pack's block and unique across the repo; duplicate foreign words per pair are warnings.
  Holds the id block table (`$Ranges`), which must match the table in `README.md`.
- `tools/publish.ps1` - validate, `git add -A`, commit, `git push -u origin HEAD`, then watch the pipeline.
  Nothing is committed when validation fails.
- `tools/watch-pipeline.ps1` - polls the GitHub API until all Actions runs of a commit have finished, prints
  runs, jobs, steps and annotations, ends with `RESULT: SUCCESS` or `RESULT: FAILED`.
  Exit code 0 success, 1 failed, 2 timeout. Uses the public API (60 requests/hour); `GITHUB_TOKEN` raises it.
- `.github/workflows/validate.yml` - runs `tools/validate.ps1` on push to `main`, pull requests and manually.

## Steps

1. **Bring the change into this repo.**
   - Pack edited here: nothing to do.
   - Seed file edited in SayIt (`Resources/Raw/seed.data`, `seed_de_a1.data`): use `-FromSayIt`, which
     copies them over `en-ru/it-interview.data` and `de-ru/a1-exam.data`.
   - New pack: add its file, its id block to `$Ranges` in `tools/validate.ps1` (and to `$sayItSeeds` in
     `tools/publish.ps1` if SayIt bundles it), and a row to the README table.
2. **Publish** from the repo root and wait for the result (allow about 5 minutes):
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\tools\publish.ps1 -CoAuthorJunie -Message "<what changed>"
   ```
   Add `-FromSayIt` for step 1 SayIt edits. Without `-Message` the message lists the changed packs.
3. **Report** the printed pipeline output to the user: each run with its conclusion and URL, failed steps
   and annotations, and the final `RESULT` line.
4. **On failure** fix the reported lines, then run the publish script again (it makes a new commit).
   Never force-push, rewrite history or delete tags. To re-check without committing:
   `powershell -ExecutionPolicy Bypass -File .\tools\watch-pipeline.ps1 [-Sha <commit>]`.

## Rules

- Never renumber or reuse ids. A fixed typo keeps its id; a deleted word's id is retired.
- Deleting words is still a deletion: ask the user before removing lines (SayIt `global-rules`).
- Push over HTTPS uses Git Credential Manager. If the push fails for credentials, tell the user to run
  `git push` once in a normal terminal to sign in, then re-run the watch script.
- Tags (`v1`, `v2`, ...) freeze a release for the app; create a new tag only when the user asks.
