# -*- coding: utf-8 -*-
"""One version's CHANGELOG section as HTML, for the update window.

    python3 scripts/changelog-html.py CHANGELOG.md 1.4.1 > notes.html

Handles what CHANGELOG.md uses: ### headings, paragraphs, "- " lists
(nested by indent), **bold**, `code` and [links](url). Relative links
(docs/…) point at the repo on GitHub.
"""
import html
import re
import sys

REPO_URL = "https://github.com/brightlifecreations-projects/LF-Studios"


def section(text, version):
    lines, on = [], False
    for line in text.splitlines():
        if re.match(r"^## \[", line):
            if on:
                break
            on = line.startswith("## [%s]" % version)
            continue
        if on:
            lines.append(line)
    return lines


def inline(text):
    text = html.escape(text, quote=False)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)

    def link(match):
        url = match.group(2)
        if not re.match(r"^[a-z]+:", url):
            url = "%s/blob/main/%s" % (REPO_URL, url)
        return '<a href="%s">%s</a>' % (html.escape(url), match.group(1))

    return re.sub(r"\[([^\]]+)\]\(([^)]+)\)", link, text)


def render(lines):
    out, depth, paragraph = [], [], []

    def close_paragraph():
        if paragraph:
            out.append("<p>%s</p>" % inline(" ".join(paragraph)))
            paragraph.clear()

    def close_lists(to=0):
        while len(depth) > to:
            depth.pop()
            out.append("</li></ul>")

    for line in lines:
        item = re.match(r"^( *)- (.*)$", line)
        if item:
            close_paragraph()
            level = len(item.group(1)) // 2 + 1
            if len(depth) >= level:
                close_lists(level)
                out.append("</li><li>%s" % inline(item.group(2)))
            else:
                while len(depth) < level:
                    depth.append(level)
                    out.append("<ul><li>")
                out[-1] += inline(item.group(2))
            continue
        if depth and line.startswith("  ") and line.strip():
            out[-1] += " " + inline(line.strip())
            continue
        close_lists()
        heading = re.match(r"^#{3,} (.*)$", line)
        if heading:
            close_paragraph()
            out.append("<h3>%s</h3>" % inline(heading.group(1)))
        elif line.strip():
            paragraph.append(line.strip())
        else:
            close_paragraph()
    close_paragraph()
    close_lists()
    return "\n".join(out)


def main():
    path, version = sys.argv[1], sys.argv[2]
    with open(path, encoding="utf-8") as f:
        lines = section(f.read(), version)
    if not any(line.strip() for line in lines):
        sys.exit("CHANGELOG.md has no entries for %s" % version)
    print("""<!DOCTYPE html>
<html><head><meta charset="utf-8">
<style>
body { font: 13px -apple-system, sans-serif; line-height: 1.45; margin: 12px 16px; }
h3 { font-size: 13px; margin: 14px 0 4px; }
ul { padding-left: 18px; margin: 4px 0; }
li { margin: 3px 0; }
code { font: 12px ui-monospace, Menlo, monospace; }
@media (prefers-color-scheme: dark) { body { color: #e6e6e6; } a { color: #8ab4ff; } }
</style></head><body>
%s
</body></html>""" % render(lines))


if __name__ == "__main__":
    main()
