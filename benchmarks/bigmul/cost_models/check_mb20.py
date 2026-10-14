#!/usr/bin/env python3
"""Explicit tiny movement models. Their charges are not hardware observations."""
import json
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"traces"))
from trace import require,validate


def movement_cost(schedule,width=32):
    require(isinstance(width,int) and width>0 and width<=64,"unsupported model word width")
    require(schedule and schedule[0][0]=="prepare","missing charged preparation")
    ram_operations,logical_bits,tape_steps=0,0,0
    head=0
    prepared=False
    stages={}
    for kind,source,destination,bits,stage in schedule:
        require(kind in ("prepare","move","scalar"),"unresolved/uncharged operation")
        require(bits==width and source>=0 and destination>=0,"model word-width/address mismatch")
        require(stage,"missing stage identity")
        if kind=="prepare":
            require(not prepared,"duplicate preparation")
            prepared=True
            # Named finite model: prepare one width-bit descriptor; scan/write it.
            ram,bits_moved,steps=1,width,width
            head=0
        elif kind=="move":
            require(prepared,"move precedes preparation")
            # A word occupies width adjacent cells on a single binary tape.
            # Copy: travel to source, scan width cells, travel back from source
            # end to destination, then write width cells. One width-bit finite
            # control register is assumed for this bounded model, explicitly.
            ram,bits_moved=2,2*width
            steps=abs(head-source*width)+width+abs((source+1)*width-destination*width)+width
            head=(destination+1)*width
        else:
            # Symbolic width-bit scalar operation, charged width steps. This is
            # NOT a simulated multiplication or the paper's tape-machine bound.
            ram,bits_moved,steps=1,0,width
        ram_operations+=ram;logical_bits+=bits_moved;tape_steps+=steps
        stages[stage]=stages.get(stage,0)+steps
    require(sum(stages.values())==tape_steps,"stage total disagreement")
    return {"word_ram_operations":ram_operations,"logical_bits_moved":logical_bits,
            "tape_model_steps":tape_steps,"per_stage_steps":stages,
            "unresolved_costs":[],"width":width}


def trace_ram_counts(parsed):
    counts=parsed["counts"]
    reads=counts.get("read",0)
    writes=counts.get("write",0)
    # Logical operands/outputs, not compiler instruction counts or physical bytes.
    return {"logical_limb_reads":reads,"logical_limb_writes":writes,
            "logical_bytes":4*(reads+writes),
            "multiply_accumulates":counts.get("multiply-accumulate",0),
            "unresolved_costs":["trace formatting", "source-to-machine lowering", "hardware memory traffic"]}


def main():
    copy=[("prepare",0,0,8,"prepare"),("move",0,1,8,"copy")]
    require(movement_cost(copy,8)["tape_model_steps"]==24,"hand-enumerated tiny copy")
    adjacent=[("prepare",0,0,8,"prepare"),("move",0,1,8,"copy"),("move",1,2,8,"copy")]
    distant=[("prepare",0,0,8,"prepare"),("move",0,4,8,"copy"),("move",4,2,8,"copy")]
    near,far=movement_cost(adjacent,8),movement_cost(distant,8)
    require(near["tape_model_steps"]==48 and far["tape_model_steps"]==96,"movement schedule hand counts")
    require(near["word_ram_operations"]==far["word_ram_operations"]==5,"equal RAM counts")
    require(near["logical_bits_moved"]==far["logical_bits_moved"]==40,"equal logical traffic")
    # Independent finite-value execution confirms identical copied result.
    values={0:37}
    for _,source,destination,_,_ in adjacent[1:]:values[destination]=values[source]
    other={0:37}
    for _,source,destination,_,_ in distant[1:]:other[destination]=other[source]
    require(values[2]==other[2]==37,"equivalent movement value computations")
    rejected=[]
    for name,schedule,width in (("missing-preparation",copy[1:],8),
                                ("changed-width",copy,16),
                                ("uncharged-lookup",copy+[("lookup",0,0,8,"table")],8)):
        try:movement_cost(schedule,width)
        except ValueError:rejected.append(name)
        else:raise ValueError(f"cost-accounting defect passed: {name}")
    changed=copy+[("move",1,3,8,"copy")]
    require(movement_cost(changed,8)!=movement_cost(copy,8),"omitted movement invisible")
    run=subprocess.run([sys.executable,str(ROOT/"traces/check_mb17.py")],capture_output=True,text=True,timeout=60)
    require(run.returncode==0,run.stderr)
    rows=[]
    for raw in json.loads(run.stdout)["traces"]:
        parsed=validate(raw["raw_trace"],raw["source_sha256"],raw["binary_sha256"],raw["left_limbs"],raw["right_limbs"])
        totals=trace_ram_counts(parsed)
        direct_reads=sum(event["kind"]=="read" for event in parsed["events"])
        require(totals["logical_limb_reads"]==direct_reads,"independent event total")
        rows.append({"case_sha256":parsed["metadata"]["case_sha256"],"counts":totals,
                     "observed_endpoint_ns":{"traced":raw["trace_endpoint_ns"],"plain":raw["plain_endpoint_ns"]}})
    print(json.dumps({"job":"MB20","status":"PASS_SCOPED","model":"bounded-binary-tape-copy-v1",
                      "assumptions":{"finite_control_storage_bits":8,"tapes":1,"alphabet":[0,1],
                                     "scalar_charges":"symbolic, not simulated arithmetic"},
                      "near_schedule":near,"far_schedule":far,"mutants_rejected":[*rejected,"omitted-move"],
                      "trace_counts":rows,"paper_component_costs":"NOT_RUN: requires accepted MUL1..4 schedules",
                      "hardware_cache_misses":"NOT_AVAILABLE; no simulator or hardware-counter claim"}))


if __name__=="__main__":main()
