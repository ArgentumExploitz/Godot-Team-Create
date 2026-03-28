import re

with open("addons/team_create/ui.gd", "r") as f:
    lines = f.readlines()

new_lines = []
seen = set()

for line in lines:
    if line.startswith("var "):
        if line not in seen:
            seen.add(line)
            new_lines.append(line)
    else:
        new_lines.append(line)

with open("addons/team_create/ui.gd", "w") as f:
    f.writelines(new_lines)
