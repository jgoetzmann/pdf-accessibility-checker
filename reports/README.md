# reports/

Written by the **PAC check** workflow; do not edit by hand.

- `<file>_PAC_WCAG_Report.pdf` — PAC's own WCAG report for `pdfs/<file>.pdf`.
- `summary.csv` — one row per report: result, title, language, tags, pages, size, then
  `passed` / `warned` / `failed` for each of PAC's 13 WCAG checkpoints (`1_1_passed` ...
  `4_1_failed`) and totals. A checkpoint a report does not list is blank, not zero.

PAC checks machine-checkable criteria only, a subset of WCAG. A report with no failures is
not a statement that a document is accessible or conformant.
