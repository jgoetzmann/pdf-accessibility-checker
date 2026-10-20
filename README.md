# PDF Accessibility Checker on GitHub Actions

Put PDFs in `pdfs/`, push, and get back a **PAC WCAG 2.2 report** for each one in
`reports/`, plus a `summary.csv` and a results table on the run page.

[PAC](https://pac.pdf-accessibility.org) is axes4's free PDF Accessibility Checker. It only
runs on Windows and has no command-line mode, so this repository runs it for you on a fresh
GitHub-hosted Windows machine for each run and drives its window the way a person would:
open the file, wait for the check, pick the WCAG tab, save PAC's own PDF report. Nothing is
installed on your computer, and the machine is discarded when the run ends.

> Not affiliated with axes4. This repository does not contain PAC; every run downloads the
> installer from axes4's own site and checks its SHA-256 before installing.

## Use it

1. **Make your own copy.** Click **Use this template → Create a new repository**. Choose
   **Private** unless your PDFs may be public: everything in `pdfs/` and `reports/` is as
   public as the repository, and a fork of a public repository cannot be made private.
2. **Accept PAC's licence.** PAC is free, but licensed by axes4. Read the
   [licence](https://pac.pdf-accessibility.org/en/resources/general-terms/end-user-license-agreement).
   If you accept it, go to **Settings → Secrets and variables → Actions → Variables** and add
   a repository variable `ACCEPT_PAC_EULA` with the value `true`. The workflow will not
   install PAC without it.
3. **Add PDFs.** Put them directly in `pdfs/` and push, or use **Add file → Upload files** on
   GitHub and upload them into `pdfs/`.
4. **Wait.** The **PAC check** workflow starts on its own (see the **Actions** tab). Setup takes
   about 3 minutes, then 15 to 45 seconds per PDF. The reports are committed to `reports/`
   when it finishes.

Only PDFs without a report are checked, so pushing new files does not re-check old ones.
To re-check everything, or to choose a different PAC build, run the workflow by hand:
**Actions → PAC check → Run workflow**.

## What you get

| Where | What |
|---|---|
| `reports/<file>_PAC_WCAG_Report.pdf` | PAC's own one-page WCAG report for `pdfs/<file>.pdf` |
| `reports/summary.csv` | One row per report: result, title, language, tags, pages, size, then `passed` / `warned` / `failed` for each of PAC's 13 WCAG checkpoints and totals. Plain numbers, consistent columns, ready for a spreadsheet. A checkpoint a report does not list is blank, never zero |
| The run page | A results table, and a list of any files that produced no report |
| The run's artifact, `pac-run` | The reports again, the macro's log, calibration reports and screenshots of anything that went wrong. Kept for 7 days |

## Options (manual runs)

| Input | Default | What it does |
|---|---|---|
| `recheck_all` | off | Check every PDF, not only those without a report |
| `pac_version` | `26.1.0.0` | PAC build. Each build's installer is pinned by URL and SHA-256 in `tools/install-pac.ps1` |
| `calibrate` | on | Check the machine against the reference reports first (below) |
| `commit_reports` | on | Commit the reports to `reports/`. Off leaves them in the artifact only |
| `mode` | `check` | `probe` records PAC's interface instead, for fixing the macro after a PAC update |

## Why the reports can be trusted

- **Pinned installer.** A PAC installer whose SHA-256 differs from the pinned value is refused.
- **Calibration every run.** Before your files, PAC checks two sample PDFs in `calibration/`
  and every field and checkpoint count must match the reference reports made earlier on the
  same build. Otherwise the run stops before touching your files.
- **Every report is validated.** It must name the file it checked, come from the chosen build
  and contain PAC's full checkpoint table.
- **Nothing is overwritten.** If a save would replace an existing file, the macro answers No
  and fails that file instead.
- **It has been cross-checked.** The same scripts reproduced 34 PAC reports, made separately
  on another Windows machine with the same PAC build, identically on every field and checkpoint.

## What PAC tells you, and what it doesn't

PAC checks **machine-checkable** criteria, which is a subset of WCAG. A report with no
failures means PAC found nothing left to flag among the things it can test. It is **not** a
statement that a PDF is accessible or WCAG-conformant: that needs human evaluation. PAC also
checks that a title, a language or alt text **exists**, not that it is **right**. A wrong
title or alt text that describes the wrong picture passes.

## Costs and limits

- **Actions minutes.** Public repositories get GitHub-hosted runners free. Private ones use
  your account's monthly Actions minutes, and Windows minutes count double: 34 PDFs plus
  setup took about 16 minutes, so roughly 30 minutes of allowance.
- **One job runs at most 6 hours.** That is several hundred PDFs. Split bigger batches.
- **Files over 100 MB** cannot be committed to GitHub without Git LFS.
- **Use it for your own documents.** GitHub's terms allow Actions for building and testing
  the project in the repository, and rule out using them to run a service for other people.
  Checking the PDFs you keep in your own repository fits the first. Accepting PDFs from
  strangers, for example through issues or pull requests, and checking them for them, would
  not, so don't wire it up that way.
- **PAC's licence** forbids offering PAC for download from your own servers and providing
  commercial hosting services, which is why the installer is fetched from axes4 on every run
  rather than stored here. It says nothing either way about automated use; if that matters for
  your organisation, ask axes4.

## When it breaks

PAC's controls are DevExpress components that Windows UI Automation sees only as unnamed
panes, and its tab headers are not exposed at all. So `tools/pac-macro.ps1` relies on:

- the window titles `PAC*`, `Select PDF file*`, `Export PDF report*`, `Error*`, `Confirm*`;
- the controls named `Open document` and `PDF report`, clicked at the centre of their rectangle;
- the **WCAG tab**, 100 px right of and 252 px below the top-left corner of `Open document`;
- the file dialogs' **Alt+N** shortcut to the file-name box, a pasted path, and Enter.

A PAC update that moves any of these makes files fail, each with a screenshot of where it
stopped. Run the workflow with `mode = probe`: it opens a sample PDF and saves PAC's UI
Automation tree and screenshots at each step, which is where these values came from. When PAC
reports that one of its checks could not be completed, the macro acknowledges the message,
carries on and counts it in `summary.csv` (`pac_check_errors`).

## Files

| File | What it does |
|---|---|
| `.github/workflows/pac-check.yml` | The workflow |
| `tools/install-pac.ps1` | Download, verify and silently install a pinned PAC build |
| `tools/pac-macro.ps1` | Drive PAC through each PDF (`check`) or record its interface (`probe`) |
| `tools/pac_reports.py` | Choose files, calibrate, validate and summarise reports |
| `tools/make_samples.py` | Write the two calibration PDFs |
| `calibration/` | The sample PDFs and their reference reports per PAC build |

The scripts in this repository are MIT-licensed (see `LICENSE`). PAC is axes4 GmbH's.
