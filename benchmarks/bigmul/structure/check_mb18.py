#!/usr/bin/env python3
"""Scoped graph/permutation controls plus an executed small transform."""
import collections
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT / "traces"))
sys.path.insert(0,str(ROOT))
from trace import require, validate
from network_shape import network_shape


def permutation_cycles(mapping):
    require(sorted(mapping)==list(range(len(mapping))), "map is not bijective")
    visited=set()
    lengths=[]
    for start in range(len(mapping)):
        if start in visited:
            continue
        current,length=start,0
        while current not in visited:
            visited.add(current)
            length+=1
            current=mapping[current]
        require(current==start,"cycle closes outside start")
        lengths.append(length)
    return dict(sorted(collections.Counter(lengths).items()))


def layout_span(mapping):
    # Logical index displacement, not bytes observed on hardware.
    permutation_cycles(mapping)
    return sum(abs(index-target) for index,target in enumerate(mapping))


def dag_structure(events, weights=None):
    weights=weights or {"multiply-accumulate":1,"carry":1}
    require(all(isinstance(value,int) and value>=0 for value in weights.values()),"invalid weights")
    depths=[]
    fanout=[0]*len(events)
    layer=collections.Counter()
    for index,event in enumerate(events):
        dependencies=event["dependencies"]
        require(event["seq"]==index and all(0<=dep<index for dep in dependencies),"invalid DAG")
        depth=max((depths[dep] for dep in dependencies),default=0)+weights.get(event["kind"],0)
        depths.append(depth)
        for dep in dependencies:
            fanout[dep]+=1
        layer[depth]+=1
    return {"weighted_depth":max(depths,default=0),"fan_in_max":max((len(e["dependencies"]) for e in events),default=0),
            "fan_out_max":max(fanout,default=0),"layer_sizes":dict(sorted(layer.items())),
            "weights":weights}


def transform_control(values):
    # Executed direct transform in Z/17Z, length four, primitive fourth root 4.
    require(len(values)==4,"transform domain")
    return [sum(value*pow(4,index*frequency,17) for index,value in enumerate(values))%17
            for frequency in range(4)]


def main():
    run=subprocess.run([sys.executable,str(ROOT/"traces/check_mb17.py")],capture_output=True,text=True,timeout=60)
    require(run.returncode==0,run.stderr)
    receipt=json.loads(run.stdout)
    structures=[]
    for raw in receipt["traces"]:
        parsed=validate(raw["raw_trace"],raw["source_sha256"],raw["binary_sha256"],raw["left_limbs"],raw["right_limbs"])
        structures.append({"case_sha256":parsed["metadata"]["case_sha256"],"profile":parsed["metadata"]["profile"],
                           "dag":dag_structure(parsed["events"]),"counts":parsed["counts"]})
    require(network_shape(8)["bit_reverse_permutation_cycle_histogram"]=={"1":4,"2":2},"eight-point bit reversal")
    require(permutation_cycles([0,1,2,3])=={1:4},"identity")
    require(permutation_cycles([1,2,3,0])=={4:1},"long cycle")
    try:
        permutation_cycles([0,0,2])
    except ValueError:
        pass
    else:
        raise ValueError("nonbijective map accepted")
    near,far=[1,0,3,2],[3,2,1,0]
    require(permutation_cycles(near)==permutation_cycles(far)=={2:2},"relabeling cycle invariance")
    require(layout_span(near)==4 and layout_span(far)==8,"relabeling changes layout span")
    tiny=[{"seq":0,"kind":"multiply-accumulate","dependencies":[]},
          {"seq":1,"kind":"multiply-accumulate","dependencies":[0]},
          {"seq":2,"kind":"carry","dependencies":[0]},
          {"seq":3,"kind":"multiply-accumulate","dependencies":[1,2]}]
    require(dag_structure(tiny)["weighted_depth"]==3,"tiny depth by hand enumeration")
    require(dag_structure(tiny)["fan_out_max"]==2,"tiny fanout")
    invalid=copy.deepcopy(tiny); invalid[0]["dependencies"]=[3]
    try:
        dag_structure(invalid)
    except ValueError:
        pass
    else:
        raise ValueError("cyclic/future dependency accepted")
    transformed=transform_control([1,2,3,4])
    require(transformed==[10,7,15,6],"direct finite-ring transform")
    # Independently executed radix-two factorization for the same convention.
    even=[(1+3)%17,(1-3)%17]; odd=[(2+4)%17,(2-4)%17]
    factored=[(even[0]+odd[0])%17,(even[1]+4*odd[1])%17,
              (even[0]-odd[0])%17,(even[1]-4*odd[1])%17]
    require(factored==transformed,"independent transform factorization")
    print(json.dumps({"job":"MB18","status":"PASS_SCOPED","structures":structures,
                      "layout_counterexample":{"cycle_type":{"2":2},"near_span":4,"far_span":8},
                      "transform":{"ring":"Z/17Z","root":4,"length":4,"normalization":"none",
                                   "input":[1,2,3,4],"output":transformed},
                      "recursive_provider":"NOT_RUN: no accepted recursive trace",
                      "paper_candidate":"NOT_RUN: waits for MB16"}))


if __name__=="__main__":
    main()
