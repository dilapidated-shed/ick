#!/usr/bin/env python3
"""Independent oracle routes. bc is mandatory unless explicitly omitted."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"acceptance"))
sys.path.insert(0,str(ROOT/"corpus"))
from runner import as_hex,build_provider,digest,execute,Refusal
from corpus import validate, value


def require(condition,message):
    if not condition:raise ValueError(message)


def parse_oracle(result,count):
    require(result.returncode==0,"oracle nonzero exit")
    require(not result.stderr.strip(),"oracle reported diagnostics")
    lines=result.stdout.replace("\\\n","").splitlines()
    require(len(lines)==count,"blank/extra/truncated oracle results")
    require(all(re.fullmatch(r"-?[0-9A-Fa-f]+",line) for line in lines),"invalid oracle output")
    return [int(line,16) for line in lines]


def bc_products(binary,pairs):
    query="scale=0\nobase=16\nibase=16\n"+"".join(f"{as_hex(a).upper()}*{as_hex(b).upper()}\n" for a,b in pairs)
    try:
        result=subprocess.run([str(binary)],input=query,text=True,capture_output=True,timeout=30)
    except subprocess.TimeoutExpired as error:
        raise Refusal("bc oracle timeout") from error
    return parse_oracle(result,len(pairs))


def cache_bytes(rows):
    lines=["oracle-cache-v1\tPython-int\tcase_sha256\tproduct_hex"]
    for row in rows:
        lines.append(row["case_sha256"]+"\t"+as_hex(value(row,"left")*value(row,"right")))
    body=("\n".join(lines)+"\n").encode("ascii")
    return body+f"# sha256\t{hashlib.sha256(body).hexdigest()}\n".encode("ascii")


def validate_cache(payload,rows,expected_sha):
    require(hashlib.sha256(payload).hexdigest()==expected_sha,"stale/changed oracle cache")
    lines=payload.decode("ascii").splitlines()
    require(lines[0]=="oracle-cache-v1\tPython-int\tcase_sha256\tproduct_hex","cache schema")
    require(len(lines)==len(rows)+2,"cache record count")
    for line,row in zip(lines[1:-1],rows):
        tokens=line.split("\t")
        require(len(tokens)==2 and tokens[0]==row["case_sha256"],"wrong cached case identity")
        require(re.fullmatch(r"-?[0-9a-f]+",tokens[1]) and int(tokens[1],16)==value(row,"left")*value(row,"right"),"bad expected product")


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--allow-missing-bc",action="store_true")
    parser.add_argument("--cache-output",type=Path)
    args=parser.parse_args()
    bc=shutil.which("bc")
    if not bc and not args.allow_missing_bc:
        print(json.dumps({"job":"MB04","status":"BLOCKED_EXTERNAL","error":"required bc executable unavailable"}))
        return 1
    with (ROOT/"corpus/smoke-v2.tsv").open("rb") as stream:
        rows=validate(stream)
    pairs=[(value(row,"left"),value(row,"right")) for row in rows]
    byte_pairs=[(a,b) for a in range(256) for b in range(256)]
    with tempfile.TemporaryDirectory(prefix="mb04-") as temporary:
        binary=Path(temporary)/"control"
        identity=build_provider(ROOT/"candidate.example.c",binary,"cc",
                                ["-O2","-std=c11","-D_POSIX_C_SOURCE=200809L"],
                                "baseline","schoolbook-oracle-control","unsigned-limb32-v1")
        small=execute(binary,identity,byte_pairs,90)
        corpus=execute(binary,identity,pairs,30)
    route={"status":"NOT_RUN","reason":"bc unavailable; omitted by explicit option","coverage":0}
    if bc:
        sample=pairs+[(-7,13),((1<<513)-1,(1<<255)-19)]
        products=bc_products(bc,sample)
        require(products==[a*b for a,b in sample],"bc/Python disagreement")
        version=subprocess.run([bc,"--version"],capture_output=True,text=True,timeout=5)
        route={"status":"PASS","executable":bc,"sha256":digest(bc),"coverage":len(sample),
               "version_stdout":version.stdout,"version_stderr":version.stderr,"version_status":version.returncode}
    rejected=[]
    for name,result in {
        "blank":subprocess.CompletedProcess([],0,"",""),
        "extra":subprocess.CompletedProcess([],0,"1\n2\n",""),
        "nonzero":subprocess.CompletedProcess([],99,"1\n",""),
        "bad-syntax":subprocess.CompletedProcess([],0,"garbage\n",""),
    }.items():
        try:parse_oracle(result,1)
        except ValueError:rejected.append(name)
        else:raise ValueError(f"oracle defect accepted: {name}")
    payload=cache_bytes(rows)
    cache_hash=hashlib.sha256(payload).hexdigest()
    validate_cache(payload,rows,cache_hash)
    for name,bad,expected in (("stale-cache",payload,"0"*64),
                              ("bad-expected",payload.replace(b"\t0\n",b"\t1\n",1),None)):
        try:validate_cache(bad,rows,expected or hashlib.sha256(bad).hexdigest())
        except ValueError:rejected.append(name)
        else:raise ValueError(f"cache defect accepted: {name}")
    if args.cache_output:args.cache_output.write_bytes(payload)
    print(json.dumps({"job":"MB04","status":"PASS" if bc else "PASS_PYTHON_ONLY",
                      "scope":"explicit schoolbook host control, not actual paper candidate",
                      "python":{"executable":sys.executable,"sha256":digest(sys.executable),"version":sys.version,
                                "exhaustive_byte_pairs":small["cases"],"v2_cases":corpus["cases"]},
                      "bc":route,"candidate_binary_sha256":identity["binary_sha256"],
                      "cache_sha256":cache_hash,"mutants_rejected":rejected,
                      "gmp_oracle":"NOT_RUN: development header not available"}))
    return 0


if __name__=="__main__":sys.exit(main())
