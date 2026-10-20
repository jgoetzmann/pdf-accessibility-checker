# calibration/

Before checking anything, the workflow runs PAC on the two PDFs here and compares the
results with the reference reports for the same PAC build. Every field and checkpoint count
must match, only the date may differ, or the run stops. That catches a changed PAC
installer, a runner image that behaves differently, or a macro that clicked the wrong thing.

- `untagged.pdf`, `tagged.pdf` — written by `../tools/make_samples.py`, byte for byte the
  same every time, with no third-party content.
- `reference/<build>/` — the reports this workflow produced for each PAC build, reviewed and
  committed. To add a build, run the workflow with that build: calibration fails with "no
  reference reports yet", and the reports to review are in the run's artifact under
  `calibration/`.
