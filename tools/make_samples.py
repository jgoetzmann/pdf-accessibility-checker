"""Write the two calibration PDFs in calibration/.

    python tools/make_samples.py

Both are written byte for byte by this script, with no timestamps or random IDs, so they
never change and their reference reports stay valid. They are deliberately small and use
PDF's standard Helvetica font, so they carry no third-party content.

untagged.pdf  A page of text with no tags, no language and no title shown: the case PAC
              fails on structure and language.
tagged.pdf    The same text, tagged (Document > H1, P), with a language, a displayed title
              and PDF/UA-style metadata: the case PAC mostly passes.
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'calibration')

HEADING = 'Calibration sample'
BODY = [
    'This document exists to check that PAC gives the same answer every time it runs.',
    'It was written by tools/make_samples.py and contains no third-party content.',
]


def content(tagged):
    lines = []
    if tagged:
        lines.append('/H1 <</MCID 0>> BDC')
    lines += ['BT', '/F1 20 Tf', '72 720 Td', '(%s) Tj' % HEADING, 'ET']
    if tagged:
        lines += ['EMC', '/P <</MCID 1>> BDC']
    y = 690
    for text in BODY:
        lines += ['BT', '/F1 12 Tf', '72 %d Td' % y, '(%s) Tj' % text, 'ET']
        y -= 18
    if tagged:
        lines.append('EMC')
    return '\n'.join(lines).encode('latin-1')


def build(tagged):
    title = 'PAC calibration sample (%s)' % ('tagged' if tagged else 'untagged')
    stream = content(tagged)
    objs = {}
    catalog = '<< /Type /Catalog /Pages 2 0 R'
    if tagged:
        catalog += (' /StructTreeRoot 7 0 R /MarkInfo << /Marked true >> /Lang (en-US)'
                    ' /ViewerPreferences << /DisplayDocTitle true >> /Metadata 10 0 R')
    objs[1] = catalog + ' >>'
    objs[2] = '<< /Type /Pages /Kids [3 0 R] /Count 1 >>'
    page = ('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R'
            ' /Resources << /Font << /F1 5 0 R >> >>')
    if tagged:
        page += ' /StructParents 0 /Tabs /S'
    objs[3] = page + ' >>'
    objs[4] = b'<< /Length %d >>\nstream\n' % len(stream) + stream + b'\nendstream'
    objs[5] = '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>'
    objs[6] = '<< /Title (%s) /Producer (tools/make_samples.py) >>' % title
    if tagged:
        objs[7] = '<< /Type /StructTreeRoot /K 8 0 R /ParentTree 11 0 R /ParentTreeNextKey 1 >>'
        objs[8] = '<< /Type /StructElem /S /Document /P 7 0 R /K [9 0 R 12 0 R] >>'
        objs[9] = '<< /Type /StructElem /S /H1 /P 8 0 R /Pg 3 0 R /K 0 >>'
        objs[12] = '<< /Type /StructElem /S /P /P 8 0 R /Pg 3 0 R /K 1 >>'
        objs[11] = '<< /Nums [0 [9 0 R 12 0 R]] >>'
        xmp = ('<?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>'
               '<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF '
               'xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
               '<rdf:Description rdf:about="" xmlns:dc="http://purl.org/dc/elements/1.1/" '
               'xmlns:pdfuaid="http://www.aiim.org/pdfua/ns/id/">'
               '<dc:title><rdf:Alt><rdf:li xml:lang="x-default">%s</rdf:li></rdf:Alt></dc:title>'
               '<pdfuaid:part>1</pdfuaid:part>'
               '</rdf:Description></rdf:RDF></x:xmpmeta><?xpacket end="w"?>' % title).encode()
        objs[10] = (b'<< /Type /Metadata /Subtype /XML /Length %d >>\nstream\n' % len(xmp)
                    + xmp + b'\nendstream')

    out = bytearray(b'%PDF-1.7\n%\xe2\xe3\xcf\xd3\n')
    offsets = {}
    for n in sorted(objs):
        offsets[n] = len(out)
        body = objs[n] if isinstance(objs[n], bytes) else objs[n].encode('latin-1')
        out += b'%d 0 obj\n' % n + body + b'\nendobj\n'
    size = max(objs) + 1
    xref = len(out)
    out += b'xref\n0 %d\n0000000000 65535 f \n' % size
    for n in range(1, size):
        out += (b'%010d 00000 n \n' % offsets[n]) if n in offsets else b'0000000000 65535 f \n'
    fid = b'<00112233445566778899aabbccddeeff>'
    out += (b'trailer\n<< /Size %d /Root 1 0 R /Info 6 0 R /ID [%s %s] >>\nstartxref\n%d\n%%%%EOF\n'
            % (size, fid, fid, xref))
    return bytes(out)


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    for tagged, name in ((False, 'untagged.pdf'), (True, 'tagged.pdf')):
        path = os.path.join(OUT, name)
        with open(path, 'wb') as fh:
            fh.write(build(tagged))
        print('wrote', os.path.relpath(path))
