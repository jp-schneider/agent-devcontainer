"""Check relative links in Markdown files: the target exists and, for `file#anchor`, the anchor does.

Usage: python3 md-links.py <root> <file.md>...  (files relative to <root>; prints broken links,
exits 1 if there are any). Anchors follow GitHub's heading slugs. External links are not checked.
"""

import os
import re
import sys

FENCE = re.compile(r"^\s*(```|~~~)")
HEADING = re.compile(r"^#{1,6}\s+(.*?)\s*#*\s*$")
LINK = re.compile(r"\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
CODE_SPAN = re.compile(r"`[^`]*`")


def lines_outside_fences(path):
    in_fence = False
    with open(path, encoding="utf-8") as f:
        for line in f:
            if FENCE.match(line):
                in_fence = not in_fence
            elif not in_fence:
                yield line


def slug(heading):
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", heading)  # [text](url) -> text
    text = re.sub(r"<[^>]+>", "", text).replace("`", "").lower()
    text = "".join(c for c in text if c.isalnum() or c in " -_")
    return text.replace(" ", "-")


def anchors(path, cache={}):
    if path not in cache:
        seen, result = {}, set()
        for line in lines_outside_fences(path):
            m = HEADING.match(line)
            if m:
                s = slug(m.group(1))
                n = seen.get(s, 0)
                seen[s] = n + 1
                result.add(s if n == 0 else f"{s}-{n}")
        cache[path] = result
    return cache[path]


def main(root, files):
    broken = []
    for rel in files:
        src = os.path.join(root, rel)
        for line in lines_outside_fences(src):
            for target in LINK.findall(CODE_SPAN.sub("", line)):
                if re.match(r"^[a-z][a-z0-9+.-]*:", target):  # https:, mailto:, …
                    continue
                file_part, _, anchor = target.partition("#")
                dest = os.path.normpath(os.path.join(os.path.dirname(src), file_part)) if file_part else src
                if not os.path.exists(dest):
                    broken.append(f"{rel}: {target} (no such file)")
                elif anchor and dest.endswith(".md") and anchor not in anchors(dest):
                    broken.append(f"{rel}: {target} (no such anchor)")
    for b in broken:
        print(b)
    return 1 if broken else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2:]))
