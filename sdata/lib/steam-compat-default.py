#!/usr/bin/env python3
"""Read or set Steam's global compatibility tool in config.vdf.

    steam-compat-default.py get <config.vdf>
        Prints the global default's tool name, or nothing when none is set.
    steam-compat-default.py set <config.vdf> <tool>
        Makes <tool> the global default. A missing file is created with only
        that setting; an existing one has its "0" CompatToolMapping entry
        replaced, leaving per-game choices and every other setting alone.

Exit status: 0 done, 1 the file could not be read (left alone), 2 the file
has no CompatToolMapping (set only, left alone).
"""
import os, sys, tempfile

SEED = """"InstallConfigStore"
{
	"Software"
	{
		"Valve"
		{
			"Steam"
			{
				"CompatToolMapping"
				{
					"0"
					{
						"name"		"%s"
						"config"	""
						"priority"	"1"
					}
				}
			}
		}
	}
}
"""


def skip_space(text, i):
    while i < len(text) and text[i].isspace():
        i += 1
    return i


def string_end(text, i):
    if text[i] != '"':
        raise ValueError(f"expected a quoted token at offset {i}")
    i += 1
    while text[i] != '"':
        i += 2 if text[i] == "\\" else 1
    return i + 1


def value_end(text, i):
    # A value is a quoted string or a brace block of key and value pairs.
    if text[i] == '"':
        return string_end(text, i)
    if text[i] != "{":
        raise ValueError(f"expected a value at offset {i}")
    i = skip_space(text, i + 1)
    while text[i] != "}":
        i = skip_space(text, value_end(text, skip_space(text, string_end(text, i))))
    return i + 1


def entries(text, start):
    """Yields (key, value start, value end) for the block opening at start."""
    i = skip_space(text, start + 1)
    while text[i] != "}":
        name_end = string_end(text, i)
        value = skip_space(text, name_end)
        end = value_end(text, value)
        yield text[i + 1:name_end - 1], value, end
        i = skip_space(text, end)


def mapping_start(content):
    key = content.find('"CompatToolMapping"')
    if key < 0:
        return None
    start = skip_space(content, key + len('"CompatToolMapping"'))
    if content[start] != "{":
        raise ValueError("CompatToolMapping is not a block")
    return start


def check_whole(content):
    root = skip_space(content, 0)
    if skip_space(content, value_end(content, skip_space(content, string_end(content, root)))) != len(content):
        raise ValueError("config.vdf does not parse")


def current(content):
    check_whole(content)
    start = mapping_start(content)
    name = ""
    if start is None:
        return name
    for key, value, end in entries(content, start):
        if key == "0" and content[value] == "{":
            for inner, ivalue, iend in entries(content, value):
                if inner == "name" and content[ivalue] == '"':
                    name = content[ivalue + 1:iend - 1]
    return name


def patched(content, tool):
    start = mapping_start(content)
    if start is None:
        return None
    zero_block = (
        '\n\t\t\t\t\t"0"\n'
        '\t\t\t\t\t{\n'
        f'\t\t\t\t\t\t"name"\t\t"{tool}"\n'
        '\t\t\t\t\t\t"config"\t\t""\n'
        '\t\t\t\t\t\t"priority"\t\t"1"\n'
        '\t\t\t\t\t}'
    )
    # Every earlier global default goes, so the new one is the only "0" entry.
    out, i = [content[:start + 1], zero_block], start + 1
    while True:
        entry = skip_space(content, i)
        if content[entry] == "}":
            out.append(content[i:])
            break
        name_end = string_end(content, entry)
        end = value_end(content, skip_space(content, name_end))
        if content[entry:name_end] != '"0"':
            out.append(content[i:end])
        i = end
    new_content = "".join(out)
    # Refuse to write anything that no longer reads as one whole document.
    check_whole(new_content)
    return new_content


def write(vdf_path, text, mode):
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(os.path.abspath(vdf_path)), prefix=".config.vdf.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", errors="surrogateescape") as f:
            f.write(text)
        os.chmod(tmp, mode)
        os.replace(tmp, vdf_path)
    except BaseException:
        os.unlink(tmp)
        raise


def main(argv):
    if len(argv) < 3 or argv[1] not in ("get", "set") or (argv[1] == "set" and len(argv) != 4):
        sys.stderr.write(__doc__)
        return 64
    # Write through a symlink rather than replacing it with a plain file.
    vdf_path = os.path.realpath(argv[2])
    if not os.path.exists(vdf_path):
        if argv[1] == "get":
            return 0
        os.makedirs(os.path.dirname(vdf_path), exist_ok=True)
        write(vdf_path, SEED % argv[3], 0o644)
        print(f"Created: global Proton default is {argv[3]}")
        return 0
    try:
        with open(vdf_path, encoding="utf-8", errors="surrogateescape") as f:
            content = f.read()
        if argv[1] == "get":
            print(current(content))
            return 0
        new_content = patched(content, argv[3])
    except (OSError, ValueError, IndexError) as error:
        sys.stderr.write(f"Warning: config.vdf could not be read ({error}), leaving it alone.\n")
        return 1
    if new_content is None:
        sys.stderr.write("Warning: CompatToolMapping not found in config.vdf, skipping patch.\n")
        return 2
    write(vdf_path, new_content, os.stat(vdf_path).st_mode & 0o7777)
    print(f"Patched: global Proton default is now {argv[3]}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
