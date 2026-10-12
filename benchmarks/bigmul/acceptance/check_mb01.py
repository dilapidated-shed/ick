#!/usr/bin/env python3
"""Exercise the outer selection/acceptance process, including python -O."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from runner import ROOT, build_provider, digest


def require(condition, message):
    if not condition:
        raise ValueError(message)


def main():
    receipt = {"job": "MB01", "status": "PASS", "scope": "host control; no paper-path proof", "runs": []}
    with tempfile.TemporaryDirectory(prefix="mb01-") as temporary:
        folder = Path(temporary)
        bodies = {
            "baseline": "return mul_schoolbook(a,na,b,nb,out);",
            "zero": "memset(out,0,(na+nb)*4); return 0;",
            "high-carry": "int r=mul_schoolbook(a,na,b,nb,out); out[na+nb-1]=0; return r;",
            "previous": "static unsigned calls; if(calls++) return 0; return mul_schoolbook(a,na,b,nb,out);",
            "nonzero": "static unsigned registered; if(!registered++){atexit(exit99);} return mul_schoolbook(a,na,b,nb,out);",
            "extra": "puts(\"0\"); return mul_schoolbook(a,na,b,nb,out);",
            "hang": "for(;;) {}",
        }
        for name, body in bodies.items():
            source = folder / f"{name}.c"
            source.write_text(
                "#include <stdint.h>\n#include <stddef.h>\n#include <stdio.h>\n"
                "#include <stdlib.h>\n#include <string.h>\n"
                "static void exit99(void){_Exit(99);}\n"
                "extern int mul_schoolbook(const uint32_t*,size_t,const uint32_t*,size_t,uint32_t*);\n"
                "int mul_candidate(const uint32_t*a,size_t na,const uint32_t*b,size_t nb,uint32_t*out){"
                "(void)a;(void)na;(void)b;(void)nb;(void)out;" + body + "}\n")
            binary = folder / name
            identity = build_provider(source, binary, os.environ.get("CC", "cc"),
                                      ["-O2", "-std=c11", "-D_POSIX_C_SOURCE=200809L"],
                                      "baseline", name, "control-limb32-v1")
            manifest = folder / f"{name}.json"
            manifest.write_text(json.dumps(identity))
            for optimized in (False, True):
                argv = [sys.executable, *(["-O"] if optimized else []),
                        str(Path(__file__).with_name("runner.py")), "--binary", str(binary),
                        "--identity", str(manifest), "--timeout", "0.25" if name == "hang" else "30"]
                run = subprocess.run(argv, capture_output=True, text=True, timeout=35)
                expected = 0 if name == "baseline" else 1
                require(run.returncode == expected, f"{name} optimized={optimized}: {run.stdout} {run.stderr}")
                receipt["runs"].append({"mutant": name, "optimized": optimized,
                    "argv": argv, "binary_sha256": digest(binary), "exit_status": run.returncode,
                    "stdout": json.loads(run.stdout), "stderr": run.stderr})
        # Correct products do not allow the forwarding control to call itself
        # the paper candidate. Test declared delegation and direct source policy.
        for defect in ("delegate", "candidate-control", "wrong-binary", "stale-source"):
            altered = json.loads(json.dumps(identity))
            if defect == "delegate":
                altered["whole_product_delegate"] = "Python-int"
            elif defect == "candidate-control":
                altered["role"] = "candidate"
            elif defect == "wrong-binary":
                altered["binary_sha256"] = "0" * 64
            else:
                altered["role"] = "candidate"
                altered["sources"][str(source)] = "0" * 64
            manifest.write_text(json.dumps(altered))
            run = subprocess.run([sys.executable, str(Path(__file__).with_name("runner.py")),
                                  "--binary", str(binary), "--identity", str(manifest)],
                                 capture_output=True, text=True, timeout=5)
            require(run.returncode != 0, f"identity defect accepted: {defect}")
            receipt["runs"].append({"mutant": defect, "exit_status": run.returncode,
                                    "stdout": json.loads(run.stdout)})
        source.write_text("invalid C source\n")
        run = subprocess.run([sys.executable, str(Path(__file__).with_name("runner.py")),
                              "--candidate-source", str(source), "--output-binary", str(binary)],
                             capture_output=True, text=True, timeout=30)
        require(run.returncode != 0 and "build_failure" in run.stdout and "stderr" in run.stdout,
                "build failure lost status/diagnostics")
        run = subprocess.run([sys.executable, str(Path(__file__).with_name("runner.py"))],
                             capture_output=True, text=True, timeout=5)
        require(run.returncode != 0, "missing configuration substituted a provider")
    print(json.dumps(receipt, sort_keys=True))


if __name__ == "__main__":
    main()
