"""Line anchors: find a cited or ledger span by its own text, and the text a file holds outside its rows.

A span is 1-based and inclusive: lines start to end. Its text anchor (text_sha256) is the SHA-256 of
its lines joined with LF, after decoding with replacement and splitting lines (so LF, CRLF and CR files
hash alike); this is the span rule the readiness check has always used. Its enclosing-line anchor
(context_sha256) is the SHA-256 of the nearest less-indented non-blank line above it, stripped, or of
the empty string for a top-level span.

locate() looks at the recorded lines first, then searches the whole file for one window of the same
length: one hit is a move, two or more are ambiguous, none means the text changed. An identical copy of
a deleted span elsewhere therefore counts as moved; the enclosing line narrows that case. The search is
bounded in characters (MAX_LOCATE_WORK): over the bound it is not run and the status is too-large.

Standard library only: no clock, no randomness, no subprocess.
"""
import hashlib

PROSE_SUFFIXES = (".md", ".mdc", ".markdown", ".mdx", ".txt", ".rst", ".adoc")
# The most characters, line breaks included, one whole-file search may join and hash. Each character is hashed in at
# most min(span, windows) windows, so a search costs at most that many times (characters + lines).
MAX_LOCATE_WORK = 100_000_000


def lines(data):
    return data.decode("utf-8", "replace").splitlines()


def text_sha256(lines, start, end):
    return hashlib.sha256("\n".join(lines[start - 1:end]).encode()).hexdigest()


def _indent(line):
    return len(line) - len(line.lstrip())


def context_line(lines, start):
    """The nearest non-blank line above start whose indent is below the span's, stripped; "" if none."""
    first = next((line for line in lines[start - 1:] if line.strip()), "")
    depth = _indent(first)
    for line in reversed(lines[:start - 1]):
        if line.strip() and _indent(line) < depth:
            return line.strip()
    return ""


def context_sha256(lines, start):
    return hashlib.sha256(context_line(lines, start).encode()).hexdigest()


def locate(lines, start, end, text, context=None):
    """Return (status, line): ("same", start), ("moved", line), ("ambiguous", None), ("changed", None),
    or ("context-changed", line) when a given context anchor differs at the line where the text is.
    ("too-large", None) when the span is not at its recorded lines and the whole-file search would cost more than
    MAX_LOCATE_WORK characters: min(span, windows) x (characters + lines), windows = len(lines) - span + 1."""
    span = end - start + 1
    if end <= len(lines) and text_sha256(lines, start, end) == text:
        status, found = "same", start
    else:
        if min(span, len(lines) - span + 1) * (sum(len(line) for line in lines) + len(lines)) > MAX_LOCATE_WORK:
            return "too-large", None
        hits = []
        for first in range(1, len(lines) - span + 2):
            if text_sha256(lines, first, first + span - 1) == text:
                hits.append(first)
                if len(hits) > 1:
                    return "ambiguous", None
        if not hits:
            return "changed", None
        status, found = "moved", hits[0]
    if context is not None and context_sha256(lines, found) != context:
        return "context-changed", found
    return status, found


def blocks(lines, spans):
    """Every maximal run of non-blank lines that holds no line of a span, as (first, last, text_sha256).
    A blank line or a span line ends a run, so text directly above and below a row are two blocks."""
    inside = set()
    for start, end in spans:
        inside.update(range(start, end + 1))
    found, run = [], []
    for number, line in enumerate(lines, 1):
        if line.strip() and number not in inside:
            run.append(number)
        elif run:
            found.append((run[0], run[-1], text_sha256(lines, run[0], run[-1])))
            run = []
    if run:
        found.append((run[0], run[-1], text_sha256(lines, run[0], run[-1])))
    return found


def is_prose(path):
    return path.lower().endswith(PROSE_SUFFIXES)
