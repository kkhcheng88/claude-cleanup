import pathlib, re, sys
p = pathlib.Path.home() / ".dsh" / "skills" / "claude-cleanup" / "SKILL.md"
text = p.read_text(encoding="utf-8")
m = re.match(r"^---\r?\n(.*?)\r?\n---\r?\n", text, re.S)
print("frontmatter block found:", bool(m))
body = m.group(1) if m else ""
name = re.search(r"(?m)^name:\s*(\S+)\s*$", body)
desc = re.search(r"(?m)^description:\s*(.+)$", body)
print("name:", name.group(1) if name else None)
print("name kebab-case ok:", bool(name) and re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", name.group(1)) is not None)
print("description length:", len(desc.group(1)) if desc else 0)
print("body bytes:", len(text.encode("utf-8")))
