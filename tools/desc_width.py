"""Rough pixel width of a line of Bag / mart description text, for build_items.py's check.

The mart's description box holds about 106 px (measured from a screenshot); this estimate runs
about 16% under the real width, so LIMIT leaves a little margin. Uppercase and digits count 6,
m and w 7, f j r t 4, i l and punctuation 3, the rest 5, a space 3."""

LIMIT = 88


def width(line: str) -> int:
    total = 0
    for c in line:
        if c == " " or c in "il.,'!:;|":
            total += 3
        elif c in "fjrt":
            total += 4
        elif c in "mw":
            total += 7
        elif c.isupper() or c.isdigit():
            total += 6
        else:
            total += 5
    return total
