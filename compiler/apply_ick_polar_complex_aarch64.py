#!/usr/bin/env python3
"""Run the recovered physical-polar patch against its pinned GCC tree.

The recovered checkpoint had one stale textual insertion marker in varasm.cc:
it named the output_constant prototype shape instead of the definition shape
present in the exact blob it already guards. Correct that marker, and nothing
else, before executing the guarded patch.
"""
from pathlib import Path

patch_path = Path(__file__).with_name("apply_ick_polar_complex.py")
text = patch_path.read_text(encoding="utf-8")

old = """marker = '''static unsigned HOST_WIDE_INT
output_constant (tree, unsigned HOST_WIDE_INT, unsigned int, bool,
'''
"""
new = """marker = '''static unsigned HOST_WIDE_INT
output_constant (tree exp, unsigned HOST_WIDE_INT size, unsigned int align,
'''
"""

count = text.count(old)
if count != 1:
    raise SystemExit(f"expected exactly one stale varasm marker, found {count}")

corrected = text.replace(old, new, 1)
code = compile(corrected, str(patch_path), "exec")
exec(code, {"__name__": "__main__", "__file__": str(patch_path)})
