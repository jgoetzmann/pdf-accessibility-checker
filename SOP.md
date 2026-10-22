# SOP: checking PDFs with PAC on GitHub Actions

Version 2026-10-22.

**Audience.** This is written for an AI agent working for the owner of a copy of this
repository: Claude Code or similar, with a terminal, `git` and the GitHub CLI (`gh`, logged
in). A person can follow the same steps on github.com, and each section says how.
`README.md` explains what the repository is and why it works the way it does. This file is
the procedure.

In the commands, `OWNER/REPO` is the copy being used. Inside a clone, get it with
`gh repo view --json nameWithOwner -q .nameWithOwner`.

---

## 1. Prompts to type

Type one of these into Claude Code, with `OWNER/REPO` replaced by your copy (for example
`yourname/pac-checks`). Each one points the agent at the section that covers the task.

| To | Type this |
|---|---|
| Check some PDFs | `Check these PDFs with PAC using https://github.com/OWNER/REPO, following its SOP.md section 4, and tell me the results: ~/Downloads/report.pdf ~/Downloads/flyer.pdf` |
| See the results so far | `Summarise the PAC results in https://github.com/OWNER/REPO following its SOP.md section 5.` |
| Re-check a file I changed | `I've updated ~/Downloads/report.pdf. Re-check it with PAC in https://github.com/OWNER/REPO following its SOP.md section 6.` |
| Re-check everything on another PAC build | `Re-check every PDF in https://github.com/OWNER/REPO with PAC 26.0.0.0, following its SOP.md section 6.` |
| Remove a file | `Remove report.pdf and its results from https://github.com/OWNER/REPO following its SOP.md section 6.` |
| Find out why a run failed | `This PAC check run failed: <run URL>. Diagnose it following SOP.md section 7 in that repository and tell me what to do.` |
| Set up a copy | `Make me a private copy of https://github.com/jgoetzmann/pdf-accessibility-checker called pac-checks and set it up following its SOP.md section 3.` |
| Bring my copy up to date | `Update https://github.com/OWNER/REPO from its template, following its SOP.md section 10.` |
| Support a new PAC build | `axes4 has released PAC <version>. Add it to https://github.com/OWNER/REPO following its SOP.md section 8.` |

In a chat that cannot reach your computer or GitHub (a plain Claude or ChatGPT chat), paste
this file in with the same request. You will get the website steps to follow yourself.

---

## 2. Rules for the agent

These rules hold in every section. If one would have to be broken, stop and ask the owner.

1. **PAC's result is not a verdict on accessibility.** PAC checks machine-checkable
   criteria, a subset of WCAG 2.2. Quote its result line word for word and attribute it
   ("PAC reports: …"). Never say a PDF is accessible, conformant or compliant, or "passes
   WCAG", on PAC's evidence; that needs human evaluation. A report with no failures means PAC
   found nothing to flag among the things it can test. PAC checks that a title, a language or
   alt text *exists*, not that it is *right*.
2. **Never invent a value.** Report only what a report or `summary.csv` says. A file without
   a report has no results: say so, never estimate. A blank in `summary.csv` means "not
   listed or not recorded", not zero.
3. **Don't edit generated files.** The workflow writes `reports/*.pdf` and
   `reports/summary.csv`. The one exception is deleting a removed file's row (section 6d).
4. **The owner accepts PAC's licence, not you.** If the repository variable
   `ACCEPT_PAC_EULA` is not `true`, give the owner the licence link
   (https://pac.pdf-accessibility.org/en/resources/general-terms/end-user-license-agreement)
   and wait until they say they accept before you set it.
5. **Check visibility before pushing PDFs:**
   `gh repo view OWNER/REPO --json visibility -q .visibility`. On a `PUBLIC` repository,
   anything pushed is public for good: it stays in the git history even after it is deleted.
   Get the owner's yes for these files, unless they have already told you the repository is
   meant for public files.
6. **The owner's own documents only.** Don't set the repository up to take PDFs from other
   people (issues, pull requests, forms, bots) and check them on their behalf. GitHub's terms
   rule out using Actions as a service for others.
7. **Never store PAC.** Don't commit PAC's installer or program files, and change an
   installer pin only through section 8. PAC's licence forbids offering it for download.
8. **Never make calibration pass by replacing reference reports.** A calibration difference
   means that run's results can't be trusted. Reference reports are added only for a new PAC
   build, after the owner has reviewed them (section 8).
9. **Test changes to the workflow or `tools/` on a throwaway branch,** using
   `gh workflow run pac-check.yml --ref <branch>`, never on `main`. Delete the branch
   afterwards.
10. **Keep the owner posted.** A run takes minutes. Check it every 30 to 60 seconds with a
    short command and say which step it is on, rather than sitting silent on one long wait.

---

## 3. Set up a copy (once)

1. **Create it:**
   `gh repo create OWNER/NAME --private --template jgoetzmann/pdf-accessibility-checker`.
   Use `--public` only if the owner wants the PDFs public (rule 5). A fork also works, but
   GitHub turns Actions off in forks until the owner enables them on the Actions tab, and a
   fork of a public repository can't be private.
2. **Licence (rule 4).** Once the owner accepts:
   `gh variable set ACCEPT_PAC_EULA --body true -R OWNER/NAME`.
3. **Verify:**
   - `gh variable get ACCEPT_PAC_EULA -R OWNER/NAME` prints `true`.
   - `gh workflow list -R OWNER/NAME` shows `PAC check  active`.
   - Creating the copy starts no run. That is expected.

**On the website:** **Use this template → Create a new repository**, then **Settings →
Secrets and variables → Actions → Variables → New repository variable**.

---

## 4. Check PDFs

1. **Get a clone.** Inside a clone of `OWNER/REPO`, run `git pull`. Otherwise run
   `gh repo clone OWNER/REPO <temporary folder>` and work there.
2. **Preflight.** Stop and tell the owner if any of these fails:
   - `gh variable get ACCEPT_PAC_EULA -R OWNER/REPO` is `true` (rule 4).
   - Visibility is acceptable (rule 5).
   - Each file starts with `%PDF-` (`head -c 5 <file>`).
   - Each file is under 100 MB. GitHub refuses larger files without Git LFS.
3. **Copy each file into `pdfs/`**, directly, keeping the owner's file name. Files in
   subfolders are ignored. If `pdfs/<name>` already exists:
   - **Identical** (`cmp` is silent): the file has already been checked. Read its report
     (section 5) and don't push.
   - **Different:** it is a new version. Follow section 6a instead.
4. **Commit and push:**
   `git add pdfs && git commit -m "Add N PDF(s)" && git push`.
   Keep the commit SHA (`git rev-parse HEAD`).
5. **Find the run:**
   `gh run list -R OWNER/REPO --commit <sha> --json databaseId,status,url`. It can take 10
   to 30 seconds to appear. If nothing appears after a minute:
   - check that the push changed something in `pdfs/` other than `pdfs/README.md`, on
     `main`;
   - check that Actions is enabled (forks: section 3).
6. **Wait, checking every 30 to 60 seconds:**
   ```bash
   gh run view <id> -R OWNER/REPO --json status,conclusion,jobs \
     -q '"\(.status) \(.conclusion) " + ([.jobs[].steps[] | select(.status=="in_progress") | .name] | join(","))'
   ```
   Expect about 2 minutes of setup, then 15 to 45 seconds per PDF. A long or complicated
   PDF can take several minutes; the limit is 15 minutes per file.
   - **`cancelled`:** usually not a failure. Runs on a branch go one at a time, and GitHub
     cancels a waiting run when a newer one queues behind it. The newer run checks every PDF
     that has no report yet, so nothing is lost.
7. **When it finishes:**
   - **`success`:** run `git pull`, then report on the files just pushed (section 5).
   - **`failure`:** follow section 7. Valid reports are committed even when some files fail.

**On the website:** open `pdfs/`, choose **Add file → Upload files**, drop the PDFs in and
**Commit changes** (`https://github.com/OWNER/REPO/upload/main/pdfs` goes straight there).
Follow the run on the **Actions** tab. The reports appear in `reports/` when it ends.

---

## 5. Read and report results

`reports/summary.csv` has one row for every report in `reports/`, not only this run's. For
detail, open the report PDF itself.

| Column | Meaning |
|---|---|
| `report` | The report's file name in `reports/` |
| `file` | The PDF, as PAC printed it. PAC shortens long names with `...` in the middle |
| `result` | PAC's own result line, word for word |
| `standard`, `pac_version` | The standard PAC tested against (WCAG 2.2) and the PAC build |
| `title`, `language`, `tags`, `pages`, `size` | PAC's DOCUMENT block. `(no language)` means no document language is set; `(no tags)` means the PDF is untagged |
| `1_1_passed` … `4_1_failed` | PAC's passed / warned / failed counts for each checkpoint (see below) |
| `passed_total`, `warned_total`, `failed_total` | Sums over the checkpoints |
| `pac_check_errors` | How many times PAC said one of its checks could not be completed for this file. Above 0, the counts may be incomplete: say so. Blank means not recorded |

**The checkpoint counts:**
- **Numbering:** checkpoints follow the WCAG 2.2 guidelines. 1.1 Text Alternatives, 1.2
  Time-based Media, 1.3 Adaptable, 1.4 Distinguishable, 2.1 Keyboard Accessible, 2.2 Enough
  Time, 2.3 Seizures and Physical Reactions, 2.4 Navigable, 2.5 Input Modalities, 3.1
  Readable, 3.2 Predictable, 3.3 Input Assistance, 4.1 Compatible.
- **What is counted:** PAC's individual checks of elements, pages and characters, not
  problems as a reader meets them. One missing document language can fail thousands of times.
- **Zeros:** PAC prints `-` where it found nothing to check, and that is recorded as 0. So a
  0 can mean "nothing to check" as well as "checked, no problem".
- **Blanks:** a checkpoint the report does not list is left blank, never zero-filled.

**How to report to the owner.** For each file checked:
- PAC's result line, quoted.
- Failed, warned and passed totals.
- The checkpoints with failures, largest first, each with its guideline name.
- Gaps in the DOCUMENT block: no language, no tags, or a title that is missing or looks like
  a file name.
- `pac_check_errors`, if above 0.

Then list any file that produced no report, with the reason from the run (section 7). End
with this, once:

> PAC checks machine-checkable criteria only, a subset of WCAG 2.2. These results are not a
> statement that any of these PDFs is accessible or WCAG-conformant; that needs human
> evaluation.

Don't rank files or turn the counts into a score. If the owner asks for one, label it as your
own unofficial ranking, not PAC's and not WCAG's.

---

## 6. Re-check or remove

**a. A new version of a file already checked.** Copy it over `pdfs/<name>`, then
`git rm reports/<name without .pdf>_PAC_WCAG_Report.pdf`. Commit both in one commit and push.
The run checks the file because it no longer has a report. Continue from section 4, step 5.

**b. Every file.** Run `gh workflow run pac-check.yml -R OWNER/REPO -f recheck_all=true`, then
find the run with
`gh run list -R OWNER/REPO --workflow pac-check.yml --event workflow_dispatch --limit 1 --json databaseId,status`.
The reports in `reports/` are replaced. The old ones stay in the git history.

**c. Another PAC build.** Add `-f pac_version=<build>` to the run in (b). The builds offered
are those pinned in `tools/install-pac.ps1`. Keep `recheck_all=true` so that every report in
`reports/` comes from the same build; the `pac_version` column shows which. Results from
different builds are not directly comparable.

**d. Remove a file.** In one commit:
- `git rm` the PDF;
- `git rm` its report;
- delete its row from `reports/summary.csv`. The workflow rebuilds the summary only when it
  checks something, so this is the one allowed hand edit.

On a public repository the file is still in the history (rule 5). Removing it from there
too means rewriting the history, which only the owner can decide.

**e. Reports missing after a partial failure.** Start a new run with
`gh workflow run pac-check.yml -R OWNER/REPO`; it checks every PDF that has no report.
Don't use `gh run rerun` if any commit has landed since the failed run. A re-run uses the old
commit, so it would re-check files that now have reports, and its push would then conflict.
`gh run rerun` is fine for a run that failed before committing anything, such as one stopped
by the licence check.

---

## 7. When a run fails

1. **Find the step that failed:**
   `gh run view <id> -R OWNER/REPO --json jobs -q '.jobs[].steps[] | select(.conclusion=="failure") | .name'`
2. **Read its log:** `gh run view <id> -R OWNER/REPO --log-failed | tail -80`
3. **Download the run's artifact, `pac-run`, which is kept for 7 days:**
   `gh run download <id> -R OWNER/REPO -n pac-run -D <temporary folder>`. It holds:
   - **`calibration/`, `reports/` and `probe/`.** Each has `macro.log` (one line per step)
     and `status.csv` (`file,status,seconds,pac_check_errors,detail`). On a failure there is
     also `failed-NN.png` (the screen when file NN failed), `failed-NN-tree.txt` (PAC's
     window as UI Automation saw it) and `pac-error-NN.png` (PAC's own error messages).
   - **`rejected/`:** reports that failed validation.

   The screenshots usually show the cause.

| Failed step | Message | Meaning | Do |
|---|---|---|---|
| Check that the PAC licence has been accepted | `…set the repository variable ACCEPT_PAC_EULA…` | The variable is not set | Rule 4, then `gh run rerun <id>` |
| Install PAC | `Installer hash … does not match the pinned …` | The file at the pinned address has changed | Stop, and don't change the hash. Tell the owner, and treat it as a new build (section 8) |
| Install PAC | A download error such as 404 | axes4 no longer offers that build | Use another pinned build, or add the current one (section 8) |
| Install PAC | `PAC install failed (exit N)` | The installer refused; its log is printed above the message | Re-run once. If it fails again, the Windows image has probably changed: tell the owner |
| Install pdftotext | A download error, or `pdftotext.exe not found` | Both xpdfreader.com and Chocolatey failed | Re-run later |
| Calibrate | `No reference reports in calibration/reference/<build> yet` | That build has no reference reports | Section 8 |
| Calibrate | `MISSING …` | The macro could not make a calibration report | See `calibration/failed-NN.png`. Usually PAC's window or the runner's screen has changed (section 9) |
| Calibrate | `DIFFERS … <field>: <old> -> <new>` | PAC gave different results for the same file | Rule 8. Show the owner the differing fields. Usual causes: GitHub changed the Windows image (the `OS` field shows it), or the macro read the wrong tab. Check no one's files until it is resolved |
| Check the PDFs | `FAILED: timed out after 900s waiting for PAC to finish checking …` | A very large or complicated PDF | Tell the owner; the PDF may need splitting |
| Check the PDFs | Every file fails at the same step | PAC's window or the runner has changed | Section 9 |
| Check the PDFs | `the dialog wanted to overwrite an existing file…` | The macro refused to overwrite a file | Shouldn't happen, since each run saves into an empty folder. Re-run; if it repeats, section 9 |
| Check the PDFs | `BAD … no report` | The macro failed on that file; the log shows a `FAILED:` line for it, with the reason | Act on that reason (rows above and below) |
| Check the PDFs | `BAD … report names '…'; moved to out/rejected` | The report is for a different file | It was kept out of `reports/`. Start a new run (section 6e), and tell the owner if it repeats |
| Check the PDFs | `BAD … PAC '…', expected …` | The report came from the wrong build | As above |
| Check the PDFs | `BAD … N of 13 checkpoints read` | The report couldn't be read in full | Open it from `rejected/`. If PAC's report layout has changed, the reader in `tools/pac_reports.py` needs fixing (section 9) |
| Commit the reports | The push is rejected | Another commit landed and the rebase conflicted | The reports are in the artifact. Start a new run (section 6e) |

---

## 8. Add a new PAC build

The owner reviews the results before anything reaches `main`.

1. **Find the installer** on PAC's download page at pac.pdf-accessibility.org, and its
   SHA-256 in the PAC manifest in `microsoft/winget-pkgs` (search that repository for
   `PAC_Setup.<version>.exe`). Download it once and confirm the hash matches. If the two
   sources disagree, stop.
2. **Pin it on a throwaway branch:**
   ```bash
   git switch -c pac-<version>
   ```
   - Add the build to `$builds` in `tools/install-pac.ps1`.
   - Add it to the `pac_version` options in `.github/workflows/pac-check.yml`.
   ```bash
   git commit -am "Pin PAC <version>"
   git push -u origin pac-<version>
   ```
3. **Probe:**
   `gh workflow run pac-check.yml -R OWNER/REPO --ref pac-<version> -f pac_version=<version> -f mode=probe`.
   In the artifact's `probe/`:
   - `probe-03-checked.png` should show a finished check;
   - `probe-04-wcag-tab.png` should show the WCAG tab selected.

   If either is wrong, follow section 9 first.
4. **Make the calibration reports:** run the same command with `mode` left at its default.
   Calibration fails with "No reference reports … yet", which is expected. In the artifact's
   `calibration/`, check both reports:
   - each names its sample (`tagged.pdf`, `untagged.pdf`);
   - each shows PAC `<version>` and WCAG 2.2, with all 13 checkpoints;
   - the counts look plausible next to the previous build's reports in
     `calibration/reference/`. Any difference should be explained by axes4's release notes.

   Show the owner.
5. **Once the owner approves**, commit the two reports to `calibration/reference/<version>/`
   on the branch. Then:
   - Add one test PDF on the branch: `cp calibration/tagged.pdf pdfs/test.pdf`, then commit
     and push. A push to a branch other than `main` starts no run.
   - Run again with the same `gh workflow run … --ref pac-<version> -f pac_version=<version>`.
     Calibration must report `MATCH` 2 of 2, and `test.pdf` must validate.
6. **Merge only the build files**, not the test PDF or its report:
   ```bash
   git switch main
   git checkout pac-<version> -- tools/install-pac.ps1 .github/workflows/pac-check.yml calibration/reference/<version>
   git commit -m "PAC <version>"
   git push
   git push origin --delete pac-<version>
   ```
   To make it the default, also change `default:` in the workflow and the `PAC_VERSION`
   fallback, and update `README.md`.

---

## 9. Fix the macro after PAC or the runner changes

**Signs:** every file fails at the same step, or calibration reports `MISSING`.

1. **Probe on a throwaway branch** (section 8, step 3). Each `probe-*.txt` lists PAC's
   windows and controls as UI Automation sees them, one per line, with type, name and screen
   rectangle. The matching `probe-*.png` shows the same moment.
2. **Compare with what `tools/pac-macro.ps1` relies on**, and change only what moved:

   | What | Where in `pac-macro.ps1` | Value today |
   |---|---|---|
   | Window titles | `Find-Window` calls | `PAC*`, `Select PDF file*`, `Export PDF report*`, `Error*`, `Confirm*` |
   | Control names | `Find-Like` calls | `Open document`, `PDF report`, `OK` |
   | WCAG tab position | `Click-WcagTab` | 100 px right of and 252 px below the top-left of `Open document` |
   | File dialog keys | `Set-DialogFile` | Alt+N, Ctrl+A, paste, Enter |
   | Report reading | `tools/pac_reports.py`, `parse` | `pdftotext -table` lines: labels, `RESULT`, checkpoint rows, `Version:`, `OS:` |

3. **Test on the branch** with calibration on. Expect `MATCH` 2 of 2, and a test PDF must
   validate. Then merge only the changed `tools/` files (as in section 8, step 6) and delete
   the branch.

---

## 10. Keep a copy up to date with the template

A copy made from the template does not receive the template's later changes. To bring them
in:

```bash
git remote add template https://github.com/jgoetzmann/pdf-accessibility-checker.git   # once
git fetch template
# show the owner what will change, then take it
git diff --stat HEAD template/main -- .github tools calibration README.md SOP.md LICENSE .gitattributes pdfs/README.md reports/README.md
git checkout template/main -- .github tools calibration README.md SOP.md LICENSE .gitattributes pdfs/README.md reports/README.md
git commit -m "Update from the template"
git push
```

- **Never** take `pdfs/` or `reports/` from the template.
- If the owner has changed any of these files (a different default build, say), apply the
  change again afterwards.
- Pushing a workflow change needs a token with the `workflow` scope
  (`gh auth refresh -s workflow`).
- This push starts no run.

---

## 11. Reference

| Path | What |
|---|---|
| `pdfs/` | PDFs to check (`main` only, not in subfolders) |
| `reports/` | `<file>_PAC_WCAG_Report.pdf` per PDF, and `summary.csv`. Written by the workflow |
| `calibration/` | `tagged.pdf` and `untagged.pdf` (written by `tools/make_samples.py`), and `reference/<build>/` reports |
| `.github/workflows/pac-check.yml` | The workflow: runs on a push to `pdfs/` on `main`, or by hand |
| `tools/install-pac.ps1` | Downloads, verifies and silently installs a pinned PAC build |
| `tools/pac-macro.ps1` | Drives PAC's window for each PDF (`check`), or records it (`probe`) |
| `tools/pac_reports.py` | `select`, `calibrate`, `validate` and `summarize`; reads reports with xpdf's `pdftotext` |

**Manual run inputs:**
- `recheck_all` (off)
- `pac_version` (`26.1.0.0`)
- `calibrate` (on)
- `commit_reports` (on; off leaves the reports in the artifact only)
- `mode` (`check` or `probe`)

**Limits and costs:**
- Public repositories run free. Private ones use the account's monthly Actions minutes,
  and Windows minutes count double.
- One run lasts at most 5 hours (`timeout-minutes: 300`), which is several hundred PDFs.
- Artifacts are kept for 7 days.
- Each file must be under 100 MB.
- The bot's report commits end in `[skip ci]` and touch only `reports/`, so they never start
  another run.
