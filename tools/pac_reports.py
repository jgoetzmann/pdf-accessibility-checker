"""Read, check and summarise PAC WCAG reports.

    python tools/pac_reports.py select <pdf-dir> <reports-dir> [--all]
    python tools/pac_reports.py calibrate <reports-dir> <reference-dir>
    python tools/pac_reports.py validate <pdf-dir> <reports-dir> <pac-version> <file> ...
    python tools/pac_reports.py summarize <reports-dir> <csv-out> [--status status.csv] [--md out.md]

select     Print the PDFs in <pdf-dir> that have no report in <reports-dir> yet (all of them
           with --all), one file name a line.
calibrate  Compare the reports just made from calibration/*.pdf with the reference reports
           for the same PAC build. Every DOCUMENT field and every checkpoint count must match;
           only the date may differ. Exit 1 on any difference.
validate   Every listed PDF must have a report that names it, on the expected PAC build, with
           a full checkpoint table.
summarize  One CSV row per report: metadata, then passed / warned / failed for every PAC
           checkpoint, then totals. Plain numbers, consistent column names. Optionally a
           Markdown table for the run page.

Reading a report needs xpdf's pdftotext on PATH: only its -table mode keeps each
checkpoint's passed / warned / failed counts on the checkpoint's own line.
"""
import csv
import os
import re
import subprocess
import sys

REPORT_SUFFIX = '_PAC_WCAG_Report.pdf'
CHECKPOINTS = ['1.1', '1.2', '1.3', '1.4', '2.1', '2.2', '2.3', '2.4', '2.5',
               '3.1', '3.2', '3.3', '4.1']
FIELDS = ['Title', 'Filename', 'Language', 'Tags', 'Pages', 'Size', 'Standard', 'Result',
          'PAC version', 'OS']

_LABELS = {'Title', 'Filename', 'Language', 'Tags', 'Pages', 'Size', 'Date/Time', 'Standard'}
_CHECK_RE = re.compile(r'^(\d\.\d)\s+(.+?)\s{2,}(-|\d+)\s+(-|\d+)\s+(-|\d+)\s*$')
_SPLIT = re.compile(r'\s{2,}')


def report_name(pdf_name):
    return os.path.splitext(os.path.basename(pdf_name))[0] + REPORT_SUFFIX


def parse(path):
    """One PAC WCAG report -> dict of DOCUMENT fields, Result, version and checkpoints."""
    out = subprocess.run(['pdftotext', '-table', path, '-'], capture_output=True,
                         encoding='utf-8', errors='replace')
    if out.returncode != 0:
        raise RuntimeError('pdftotext failed on %s: %s' % (path, out.stderr.strip()))
    lines = [l.rstrip() for l in out.stdout.replace('\r', '').split('\n') if l.strip()]
    rec = {}
    # The DOCUMENT block rewraps with the title's length, so pair label lines with the line
    # after them wherever they occur.
    for i, line in enumerate(lines):
        toks = _SPLIT.split(line.strip())
        if not toks or not all(t in _LABELS for t in toks) or i + 1 >= len(lines):
            continue
        vals = _SPLIT.split(lines[i + 1].strip())
        if len(toks) == 1:
            rec[toks[0]] = lines[i + 1].strip()
        elif len(toks) == len(vals):
            rec.update(zip(toks, vals))
    for i, line in enumerate(lines):
        if line.strip() == 'RESULT' and i + 1 < len(lines):
            rec['Result'] = lines[i + 1].strip()
            break
    rec['checkpoints'] = {}
    for line in lines:
        m = _CHECK_RE.match(line.strip())
        if m:
            n = lambda t: 0 if t == '-' else int(t)    # PAC prints '-' for nothing found
            rec['checkpoints'][m.group(1)] = {'label': m.group(2).strip(), 'passed': n(m.group(3)),
                                              'warned': n(m.group(4)), 'failed': n(m.group(5))}
    for line in lines:
        if line.startswith('Version:'):
            rec['PAC version'] = line.split(':', 1)[1].strip()
        elif line.startswith('OS:'):
            rec['OS'] = line.split(':', 1)[1].strip()
    return rec


def _norm(v):
    return re.sub(r'\s+', ' ', str(v if v is not None else '')).strip()


def _key(name):
    return re.sub(r'[^a-z0-9]+', '', os.path.splitext(_norm(name))[0].lower())


def names_file(rec, pdf):
    """PAC elides long file names in the middle with '...'; compare on what survives."""
    target = _norm(rec.get('Filename'))
    if target == pdf:
        return True
    if '...' in target:
        head, tail = target.split('...', 1)
        return pdf.startswith(head) and pdf.endswith(tail)
    return False


def cmd_select(pdf_dir, reports_dir, everything):
    have = set(os.listdir(reports_dir)) if os.path.isdir(reports_dir) else set()
    for f in sorted(os.listdir(pdf_dir)):
        if f.lower().endswith('.pdf') and (everything or report_name(f) not in have):
            print(f)
    return 0


def cmd_calibrate(reports_dir, reference_dir):
    refs = sorted(f for f in os.listdir(reference_dir) if f.endswith(REPORT_SUFFIX)) \
        if os.path.isdir(reference_dir) else []
    if not refs:
        print('No reference reports in %s yet. Review the calibration reports in this run\'s '
              'artifact and commit them there to start calibrating this build.' % reference_dir)
        return 1
    bad = 0
    for f in refs:
        path = os.path.join(reports_dir, f)
        if not os.path.exists(path):
            print('MISSING  %s' % f); bad += 1; continue
        old, new = parse(os.path.join(reference_dir, f)), parse(path)
        diffs = []
        for fld in FIELDS:
            a, b = old.get(fld), new.get(fld)
            same = _key(a) == _key(b) if fld == 'Filename' else _norm(a) == _norm(b)
            if not same:
                diffs.append('%s: %r -> %r' % (fld, a, b))
        for c in sorted(set(old['checkpoints']) | set(new['checkpoints'])):
            a = {k: old['checkpoints'].get(c, {}).get(k) for k in ('passed', 'warned', 'failed')}
            b = {k: new['checkpoints'].get(c, {}).get(k) for k in ('passed', 'warned', 'failed')}
            if a != b:
                diffs.append('%s: %s -> %s' % (c, a, b))
        print('%-8s %s %s' % ('MATCH' if not diffs else 'DIFFERS', f, '; '.join(diffs)))
        bad += bool(diffs)
    print('calibration: %d of %d match the reference reports' % (len(refs) - bad, len(refs)))
    return 1 if bad else 0


def cmd_validate(pdf_dir, reports_dir, version, files):
    bad = 0
    for pdf in files:
        path = os.path.join(reports_dir, report_name(pdf))
        problems = []
        if not os.path.exists(path):
            problems.append('no report')
        else:
            rec = parse(path)
            if not names_file(rec, pdf):
                problems.append('report names %r' % rec.get('Filename'))
            if rec.get('PAC version') != version:
                problems.append('PAC %r, expected %s' % (rec.get('PAC version'), version))
            if len(rec['checkpoints']) != len(CHECKPOINTS):
                problems.append('%d of %d checkpoints read' % (len(rec['checkpoints']), len(CHECKPOINTS)))
        print('%-4s %s %s' % ('ok' if not problems else 'BAD', pdf, '; '.join(problems)))
        bad += bool(problems)
    print('validate: %d of %d reports pass' % (len(files) - bad, len(files)))
    return 1 if bad else 0


def cmd_summarize(reports_dir, csv_out, status_csv=None, md_out=None):
    status = {}
    if status_csv and os.path.exists(status_csv):
        for row in csv.DictReader(open(status_csv, encoding='utf-8-sig')):
            status[report_name(row['file'])] = row
    cols = (['report', 'file', 'result', 'standard', 'pac_version', 'title', 'language', 'tags',
             'pages', 'size']
            + ['%s_%s' % (c.replace('.', '_'), k) for c in CHECKPOINTS for k in ('passed', 'warned', 'failed')]
            + ['passed_total', 'warned_total', 'failed_total', 'pac_check_errors'])
    rows = []
    for f in sorted(x for x in os.listdir(reports_dir) if x.endswith(REPORT_SUFFIX)):
        rec = parse(os.path.join(reports_dir, f))
        cps = rec['checkpoints']
        row = {'report': f, 'file': _norm(rec.get('Filename')), 'result': rec.get('Result', ''),
               'standard': rec.get('Standard', ''), 'pac_version': rec.get('PAC version', ''),
               'title': _norm(rec.get('Title')), 'language': rec.get('Language', ''),
               'tags': rec.get('Tags', ''), 'pages': rec.get('Pages', ''), 'size': rec.get('Size', '')}
        for c in CHECKPOINTS:
            for k in ('passed', 'warned', 'failed'):
                # a checkpoint the report does not list is left blank, never zero-filled
                row['%s_%s' % (c.replace('.', '_'), k)] = cps[c][k] if c in cps else ''
        for k in ('passed', 'warned', 'failed'):
            row['%s_total' % k] = sum(v[k] for v in cps.values())
        row['pac_check_errors'] = status.get(f, {}).get('pac_check_errors', '')
        rows.append(row)
    with open(csv_out, 'w', newline='', encoding='utf-8') as fh:
        w = csv.DictWriter(fh, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)
    print('summarized %d reports into %s' % (len(rows), csv_out))
    if md_out:
        L = ['## PAC WCAG reports', '',
             '| File | Result | Failed | Warned | Passed | Language | Tags | Pages |',
             '|---|---|--:|--:|--:|---|--:|--:|']
        for r in rows:
            L.append('| %s | %s | %s | %s | %s | %s | %s | %s |'
                     % (r['file'], r['result'], r['failed_total'], r['warned_total'],
                        r['passed_total'], r['language'], r['tags'], r['pages']))
        failed = [row for row in status.values() if row.get('status') != 'ok']
        if failed:
            L += ['', '**%d file(s) produced no report:**' % len(failed), '']
            L += ['- %s: %s' % (row['file'], row.get('detail', '')) for row in failed]
        L += ['', 'PAC checks machine-checkable criteria only, a subset of WCAG. A report with '
              'no failures is not a statement that a document is accessible or conformant; '
              'that needs human evaluation.']
        with open(md_out, 'a', encoding='utf-8') as fh:
            fh.write('\n'.join(L) + '\n')
    return 0


if __name__ == '__main__':
    a = sys.argv[1:]
    if not a:
        sys.exit(__doc__)
    cmd = a[0]
    if cmd == 'select':
        sys.exit(cmd_select(a[1], a[2], '--all' in a))
    if cmd == 'calibrate':
        sys.exit(cmd_calibrate(a[1], a[2]))
    if cmd == 'validate':
        sys.exit(cmd_validate(a[1], a[2], a[3], a[4:]))
    if cmd == 'summarize':
        opt = lambda flag: a[a.index(flag) + 1] if flag in a else None
        sys.exit(cmd_summarize(a[1], a[2], opt('--status'), opt('--md')))
    sys.exit('unknown command %r\n\n%s' % (cmd, __doc__))
