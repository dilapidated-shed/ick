#!/usr/bin/env python3
"""Fail-closed, source-free verification of the Linux x86_64 IDK candidate."""
import hashlib
import pathlib
import sys

SOURCE = "45a65d8b8c8928843b1bdaa1e737ce8b5ae814e0"
DMD = "74917954b53f7f35b13e61b4438c7253834929ed"
PHOBOS = "7b158eba80b97dfcdd8931bcaea1ad0ca35ceb95"
ORDINARY_SHA = "371b78028c535780b5ba58333b182d1164f27545aa6f863ac842893502a06a79"
DIVERGENT_SHA = "b7394a1b808e5c7d8cde8824915158ff8cb7ab12cb4a05df46f8453a9ce1b9b6"

REQUIRED = (
    "bin/idk", "libexec/idk-dmd", "lib/libdruntime.a", "lib/libphobos2.a",
    "import/druntime/object.d", "import/phobos/std/bigint.d",
    "import/phobos/std/stdio.d", "meta/SOURCE.lock", "meta/RUNTIME.lock",
    "meta/identity.tsv", "meta/FILES.sha256",
    "fixtures/idk_ordinary_runtime_smoke.d",
    "fixtures/idk_full_runtime_smoke.d", "share/verify-candidate.py",
    "share/consume-candidate.sh",
)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def key_values(path):
    result = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        require("=" in line, "invalid identity/lock line in " + str(path))
        key, value = line.split("=", 1)
        require(key and key not in result, "duplicate/empty identity key: " + key)
        result[key] = value
    return result


def elf_header(data, context):
    require(len(data) >= 20 and data[:4] == b"\x7fELF", "non-ELF object: " + context)
    require(data[4] == 2 and data[5] == 1 and
            int.from_bytes(data[18:20], "little") == 62,
            "wrong-ABI ELF: " + context)


def archive_abi(path):
    data = path.read_bytes()
    require(data.startswith(b"!<arch>\n"), "wrong-ABI or malformed archive: " + str(path))
    position = 8
    objects = 0
    while position < len(data):
        hdr = data[position:position + 60]
        require(len(hdr) == 60 and hdr[58] == 96 and hdr[59] == 10,
                "malformed archive member: " + str(path))
        try:
            size = int(hdr[48:58].decode("ascii").strip())
        except (ValueError, UnicodeError) as exc:
            raise ValueError("invalid archive member size: " + str(path)) from exc
        require(size >= 0, "negative archive member size")
        position += 60
        require(position + size <= len(data), "truncated archive member: " + str(path))
        member = data[position:position + size]
        position += size + (size % 2)
        name = hdr[:16].decode("ascii", errors="replace").strip()
        if name in ("/", "//", "/SYM64/", "__.SYMDEF", "__.SYMDEF SORTED"):
            continue
        if name.startswith("#1/"):
            try:
                name_length = int(name[3:])
            except ValueError as exc:
                raise ValueError("malformed BSD archive filename") from exc
            member = member[name_length:]
        elf_header(member, str(path) + ":" + name)
        objects += 1
    require(position == len(data) and objects > 0,
            "empty or malformed archive: " + str(path))


def verify(root):
    root = root.resolve(strict=True)
    require(root.is_dir(), "missing bundle root")
    for item in REQUIRED:
        require((root / item).is_file(), "missing required bundle member: " + item)

    # Identity and target ABI are checked independently of the checksum list.
    ident = key_values(root / "meta/identity.tsv")
    expected = {
        "format": "idk-linux-x86_64-candidate-v1",
        "compiler_line": "idk",
        "compiler_source_head": SOURCE,
        "dmd_upstream_commit": DMD,
        "phobos_upstream_commit": PHOBOS,
        "host": "linux-x86_64",
        "bootstrap_is_payload": "false",
        "conservative_dmd_is_payload": "false",
        "ordinary_stdout": "123456789012345678901234567891",
        "divergent_stdout": "1000000000000000000000000000000",
        "unicode_mutant_exit": "3",
        "historical_qualification_run": "37304142154",
    }
    for key, value in expected.items():
        require(ident.get(key) == value,
                "mismatched source/runtime identity: " + key)
    require(len(ident.get("workflow_source_head", "")) == 40 and
            all(c in "0123456789abcdef" for c in ident["workflow_source_head"]),
            "mismatched workflow source identity")

    source_lock = key_values(root / "meta/SOURCE.lock")
    runtime_lock = key_values(root / "meta/RUNTIME.lock")
    require(source_lock.get("upstream_commit") == DMD,
            "mismatched source identity in SOURCE.lock")
    require(runtime_lock.get("compiler_line") == "idk" and
            runtime_lock.get("dmd_upstream_commit") == DMD and
            runtime_lock.get("phobos_upstream_commit") == PHOBOS,
            "mismatched runtime identity in RUNTIME.lock")
    require(runtime_lock.get("idk_base_source_head") ==
            "297112cc526cddbba098716d1617681852b8c4c9",
            "mismatched IDK lineage")
    require(digest(root / "fixtures/idk_ordinary_runtime_smoke.d") == ORDINARY_SHA,
            "mismatched original ordinary-D fixture fingerprint")
    require(digest(root / "fixtures/idk_full_runtime_smoke.d") == DIVERGENT_SHA,
            "mismatched original divergent-IDK fixture fingerprint")

    elf_header((root / "libexec/idk-dmd").read_bytes()[:64], "owned IDK compiler")
    archive_abi(root / "lib/libdruntime.a")
    archive_abi(root / "lib/libphobos2.a")

    files = {}
    for path in root.rglob("*"):
        require(not path.is_symlink(), "symlink in bundle: " + str(path))
        if path.is_file():
            rel = path.relative_to(root).as_posix()
            require("conservative-dmd" not in rel.lower() and "ldmd2" not in rel.lower(),
                    "negative control or bootstrap compiler in payload: " + rel)
            files[rel] = path
        else:
            require(path.is_dir(), "non-regular bundle member")
    checksum_path = "meta/FILES.sha256"
    lines = (root / checksum_path).read_text(encoding="utf-8").splitlines()
    declared = {}
    for line in lines:
        require("  " in line, "invalid checksum manifest row")
        sha, rel = line.split("  ", 1)
        require(len(sha) == 64 and all(c in "0123456789abcdef" for c in sha),
                "invalid checksum")
        require(rel.startswith("./"), "non-relative checksum manifest entry")
        rel = rel[2:]
        require(rel not in declared, "duplicate checksum manifest entry")
        declared[rel] = sha
    actual_names = sorted(set(files) - {checksum_path})
    require(list(declared) == actual_names,
            "missing/extra/tampered package member in checksum manifest")
    for rel in actual_names:
        require(digest(files[rel]) == declared[rel],
                "tampered package member: " + rel)
    require((root / "bin/idk").stat().st_mode & 0o111,
            "missing executable wrapper")
    require((root / "libexec/idk-dmd").stat().st_mode & 0o111,
            "missing executable owned compiler")
    return len(actual_names)


def main():
    if len(sys.argv) != 2:
        print("usage: verify-candidate.py /path/to/idk-linux-x86_64", file=sys.stderr)
        return 2
    try:
        count = verify(pathlib.Path(sys.argv[1]))
    except (ValueError, OSError, UnicodeError) as exc:
        print("REJECTED: " + str(exc), file=sys.stderr)
        return 1
    print("PASS idk-linux-x86_64 integrity and ABI: " + str(count) + " members")
    return 0


if __name__ == "__main__":
    sys.exit(main())
