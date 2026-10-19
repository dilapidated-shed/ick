#!/usr/bin/env python3
"""Run available campaign controls; full readiness fails on partial/missing work."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]
REPOSITORY=ROOT.parents[1]
sys.path.insert(0,str(ROOT/"corpus"))
from corpus import require

CHECKS={
    "MB01":"acceptance/check_mb01.py", "MB02":"abi/check_mb02.py",
    "MB03":"corpus/check_mb03.py", "MB04":"oracles/check_mb04.py",
    "MB05":"providers/check_mb05.py", "MB06":"timing/check_mb06.py",
    "MB07":"modes/hot/check_mb07.py", "MB08":"modes/mixed/check_mb08.py",
    "MB09":"modes/cache/check_mb09.py", "MB10":"modes/end_to_end/check_mb10.py",
    "MB11":"memory/check_mb11.py", "MB12":"analysis/check_mb12.py",
    "MB13":"platforms/native/check_mb13.py", "MB14":"platforms/android/check_mb14.py",
    "MB15":"platforms/power/check_mb15.py", "MB16":"providers/openai2026/check_mb16.py",
    "MB17":"traces/check_mb17.py", "MB18":"structure/check_mb18.py",
    "MB19":"precision/check_mb19.py", "MB20":"cost_models/check_mb20.py",
}
ESSENTIAL=[f"MB{number:02}" for number in list(range(1,14))+list(range(16,21))]


def ready_gate(manifest,observed):
    require(manifest["source_sha"]==observed["source_sha"],"stale source hash")
    require(manifest["corpus_sha256"]==observed["corpus_sha256"],"missing/stale mandatory corpus")
    require(manifest["candidate"]["role"]=="paper-candidate" and not manifest["candidate"]["example"],"substituted example provider")
    require(manifest["candidate"]["binary_sha256"]==observed["candidate_binary_sha256"],"candidate identity mismatch")
    require(set(manifest["stage_receipts"])>=set(ESSENTIAL),"absent essential stage receipt")
    require(all(manifest["stage_receipts"][job]=="PASS" for job in ESSENTIAL),"partial/failed essential stage")
    require(manifest["products"]==observed["products"],"wrong product")
    require(manifest["products"],"no independently checked products")
    require({"hot","mixed"}<=set(manifest["modes"]),"missing required timing mode")
    require(manifest["paired_case_sha256"]==observed["corpus_sha256"],"unpaired operands")
    require(manifest["serious_baseline"] is True,"missing qualified conventional comparison")
    for target in ("MB14","MB15"):
        require(manifest["targets"].get(target) in ("PASS","BLOCKED_EXTERNAL"),"missing target boundary")
    return True


def gate_controls():
    # Synthetic fixtures qualify the gate logic only. They never produce a
    # benchmark-readiness claim or stand in for stage execution receipts.
    observed={"source_sha":"1"*40,"corpus_sha256":"2"*64,
              "candidate_binary_sha256":"3"*64,"products":[6,35]}
    good={"source_sha":observed["source_sha"],"corpus_sha256":observed["corpus_sha256"],
          "candidate":{"role":"paper-candidate","example":False,"binary_sha256":"3"*64},
          "stage_receipts":{job:"PASS" for job in ESSENTIAL},"products":[6,35],
          "modes":["hot","mixed"],"paired_case_sha256":"2"*64,"serious_baseline":True,
          "targets":{"MB14":"BLOCKED_EXTERNAL","MB15":"BLOCKED_EXTERNAL"}}
    require(ready_gate(good,observed),"native-only fixture should admit explicit target blockers")
    rejected=[]
    for name in ("wrong-product","stale-source","missing-corpus","example-substitution","missing-stage","partial-stage","unpaired-input"):
        bad=copy.deepcopy(good)
        if name=="wrong-product":bad["products"][0]=0
        elif name=="stale-source":bad["source_sha"]="0"*40
        elif name=="missing-corpus":bad["corpus_sha256"]=""
        elif name=="example-substitution":bad["candidate"]["example"]=True
        elif name=="missing-stage":del bad["stage_receipts"]["MB16"]
        elif name=="partial-stage":bad["stage_receipts"]["MB04"]="PASS_PYTHON_ONLY"
        else:bad["paired_case_sha256"]="0"*64
        try:ready_gate(bad,observed)
        except ValueError:rejected.append(name)
        else:raise ValueError(f"release gate defect passed: {name}")
    return rejected


def execute_control(job,path,optional_bc):
    argv=[sys.executable,str(path)]
    if job=="MB04" and optional_bc:argv.append("--allow-missing-bc")
    if job=="MB05":
        # Local extracted headers remain an explicit host configuration;
        # hosted lanes install the pinned GMP development package instead.
        import os
        for variable,option in (("MB05_GMP_INCLUDE","--gmp-include"),("MB05_GMP_LIBRARY","--gmp-library")):
            if os.environ.get(variable):argv.extend([option,os.environ[variable]])
    result=subprocess.run(argv,capture_output=True,text=True,timeout=180,cwd=REPOSITORY)
    parsed=None
    if result.stdout:
        try:parsed=json.loads(result.stdout)
        except ValueError:pass
    return {"job":job,"status":"PASS_SCOPED" if result.returncode==0 else "FAIL",
            "argv":argv,"exit_status":result.returncode,"stdout":result.stdout,"stderr":result.stderr,
            "receipt":parsed,"driver_sha256":hashlib.sha256(path.read_bytes()).hexdigest()}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-controls",action="store_true")
    parser.add_argument("--allow-missing-bc",action="store_true")
    parser.add_argument("--require-ready",action="store_true")
    parser.add_argument("--expected-arch",choices=("x86_64","aarch64"))
    parser.add_argument("--output",type=Path)
    args=parser.parse_args()
    architecture=platform.machine()
    require(not args.expected_arch or architecture==args.expected_arch,"wrong native architecture label")
    head=subprocess.run(["git","-C",str(REPOSITORY),"rev-parse","HEAD"],capture_output=True,text=True,check=True).stdout.strip()
    report={"job":"MB21","gate_tests":"PASS","gate_mutants_rejected":gate_controls(),
            "source_sha":head,"architecture":architecture,"python":sys.version,
            "corpus_sha256":hashlib.sha256((ROOT/"corpus/smoke-v2.tsv").read_bytes()).hexdigest(),
            "controls":[],"missing_drivers":[],"benchmark_readiness":"BLOCKED",
            "targets":{"MIRO-A1-ARM32":"BLOCKED_EXTERNAL: no physical serial/transport access",
                       "AIX-POWER":"BLOCKED_EXTERNAL: no authorized native host"},
            "actual_candidate":"BLOCKED: accepted MUL5/MB16 implementation not present"}
    failed=False
    for job,relative in CHECKS.items():
        path=ROOT/relative
        if not path.is_file():
            report["missing_drivers"].append(job)
            continue
        if args.run_controls:
            control=execute_control(job,path,args.allow_missing_bc)
            report["controls"].append(control)
            failed|=control["exit_status"]!=0
    if args.run_controls:
        extended=execute_control("MB02-extended",ROOT/"abi/check_mb02_extended.py",False)
        report["controls"].append(extended)
        failed|=extended["exit_status"]!=0
    report["controls_status"]="FAIL" if failed else "PASS_SCOPED" if args.run_controls else "NOT_RUN"
    report["status"]="FAIL" if failed else "BLOCKED" if args.require_ready else "PASS_SCOPED" if args.run_controls else "PASS_GATE_TESTS"
    text=json.dumps(report,sort_keys=True)
    if args.output:
        args.output.parent.mkdir(parents=True,exist_ok=True)
        args.output.write_text(text+"\n")
    print(json.dumps({key:value for key,value in report.items() if key!="controls"},sort_keys=True))
    # The implemented gate cannot admit this partial package. Requesting readiness
    # fails until actual essential providers/modes/stages are integrated and rerun.
    return 1 if failed or args.require_ready else 0


if __name__=="__main__":sys.exit(main())
