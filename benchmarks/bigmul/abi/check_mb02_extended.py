#!/usr/bin/env python3
"""Additional host safety lanes; unsupported 32-bit builds are explicit."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import check_mb02 as base


def require(condition, message):
    if not condition:
        raise ValueError(message)


def main():
    compiler = shutil.which(base.CC)
    require(compiler is not None, "host compiler unavailable")
    commands, failures, lanes = [], [], {}
    sanitizer_environment = dict(os.environ)
    lanes["leak-sanitizer"] = "NOT_RUN: not yet probed"
    def run(argv, **kwargs):
        result = subprocess.run(argv, capture_output=True, timeout=30, **kwargs)
        commands.append({"argv": argv, "status": result.returncode,
                         "stdout": result.stdout.decode(errors="replace"),
                         "stderr": result.stderr.decode(errors="replace")})
        return result
    with tempfile.TemporaryDirectory(prefix="mb02-extended-") as temporary:
        folder=Path(temporary)
        for sanitizer in ("undefined", "address,undefined"):
            binary=folder / sanitizer.replace(",", "-")
            argv=[compiler,*base.FLAGS,"-fsanitize="+sanitizer,"-fno-omit-frame-pointer","-no-pie",
                  str(base.SOURCE),"-o",str(binary)]
            built=run(argv)
            if built.returncode:
                lanes[sanitizer]="NOT_RUN: sanitizer build unavailable"
                continue
            result=run([str(binary),"--pipe"],input=b"ffffffffffffffff ffffffffffffffff\n0 1\n",env=sanitizer_environment)
            if sanitizer == "address,undefined":
                if result.returncode and b"LeakSanitizer has encountered a fatal error" in result.stderr:
                    lanes["leak-sanitizer"] = "NOT_RUN: runtime blocks process inspection; disabled after retained failed probe"
                    sanitizer_environment["ASAN_OPTIONS"] = "detect_leaks=0"
                    result=run([str(binary),"--pipe"],input=b"ffffffffffffffff ffffffffffffffff\n0 1\n",env=sanitizer_environment)
                else:
                    lanes["leak-sanitizer"] = "AVAILABLE: detector runtime only, no comprehensive leak fixture claim"
            require(result.returncode==0 and [int(x,16) for x in result.stdout.splitlines()]==[(2**64-1)**2,0],
                    f"sanitizer baseline failed: {commands[-1]}")
            # A write two words beyond the checked guard must be caught by ASan.
            if sanitizer == "address,undefined":
                provider=folder / "far-overwrite.c"
                provider.write_text("#include <stdint.h>\n#include <stddef.h>\n"
                    "extern int mul_schoolbook(const uint32_t*,size_t,const uint32_t*,size_t,uint32_t*);\n"
                    "int mul_candidate(const uint32_t*a,size_t na,const uint32_t*b,size_t nb,uint32_t*out){"
                    "out[na+nb+2]=0;return mul_schoolbook(a,na,b,nb,out);}\n")
                bad=folder / "far-overwrite"
                built=run([compiler,*base.FLAGS,"-fsanitize="+sanitizer,"-fno-omit-frame-pointer","-no-pie",
                           "-DHAVE_CANDIDATE",str(base.SOURCE),str(provider),"-o",str(bad)])
                require(built.returncode==0, "sanitizer mutant build failed")
                result=run([str(bad),"--pipe"],input=b"1 2\n",env=sanitizer_environment)
                require(result.returncode!=0 and b"AddressSanitizer" in result.stderr, "far overwrite undetected")
                failures.append("far-output-overwrite")
            lanes[sanitizer]="PASS: host x86-64"
        binary=folder / "allocation-failures"
        built=run([compiler,*base.FLAGS,str(base.SOURCE),str(Path(__file__).with_name("fail_alloc.c")),
                   "-Wl,--wrap=malloc","-Wl,--wrap=calloc","-o",str(binary)])
        require(built.returncode==0, "GNU-linker allocation fixture unavailable")
        for mode, count, payload in (("--pipe",8,b"ffffffff ffffffff\n"),("--bench",3,b"")):
            for index in range(1,count+1):
                environment=dict(os.environ,MB_FAIL_ALLOCATION=str(index))
                args=[str(binary),mode,*(["32","1"] if mode=="--bench" else [])]
                result=run(args,input=payload,env=environment)
                require(result.returncode!=0, f"allocation failure {index} hidden in {mode}")
                require(not result.stdout if mode=="--pipe" else len(result.stdout.splitlines())<=1,
                        "failure produced a valid result/timing record")
                failures.append(f"allocation-{mode}-{index}")
        probe=folder / "overflow-probe.c"
        probe.write_text("#include <stdint.h>\n#include <stddef.h>\n"
            "extern int mul_schoolbook(const uint32_t*,size_t,const uint32_t*,size_t,uint32_t*);\n"
            "int main(void){uint32_t a=1,b=1,out=0;"
            "return mul_schoolbook(&a,SIZE_MAX/sizeof(out)+1,&b,1,&out)==0?99:0;}\n")
        for mutant in (False,True):
            source=base.SOURCE
            if mutant:
                source=folder / "bypass-overflow.c"
                text=base.SOURCE.read_text()
                old="nb > SIZE_MAX / sizeof(*out) ||\n        na > SIZE_MAX / sizeof(*out) - nb"
                require(old in text, "overflow fixture drifted")
                source.write_text(text.replace(old,"0",1))
            obj=folder / "overflow.o"
            require(run([compiler,*base.FLAGS,"-Dmain=unused_main","-c",str(source),"-o",str(obj)]).returncode==0,"probe object build")
            require(run([compiler,*base.FLAGS,str(probe),str(obj),"-o",str(binary)]).returncode==0,"probe link")
            result=run([str(binary)])
            require((result.returncode!=0)==mutant, "overflow check bypass undetected")
        failures.append("bypassed-size-overflow")
        binary=folder / "baseline32"
        built=run([compiler,*base.FLAGS,"-m32",str(base.SOURCE),"-o",str(binary)])
        if built.returncode:
            lanes["ordinary32"]="NOT_RUN: host 32-bit headers/linker runtime unavailable"
        else:
            result=run([str(binary),"--pipe"],input=b"ffffffff ffffffff\n")
            require(result.returncode==0 and int(result.stdout,16)==(2**32-1)**2,"ordinary32 failure")
            lanes["ordinary32"]="PASS: host x86-32, not Android"
    print(json.dumps({"job":"MB02","status":"PASS_SCOPED","lanes":lanes,
                      "mutants_rejected":failures,"commands":commands}))


if __name__ == "__main__":
    main()
