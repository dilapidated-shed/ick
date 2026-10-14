#!/usr/bin/env python3
"""Executed baseline carry statistics and exact certificate-validator fixtures."""
import itertools
import json
from fractions import Fraction
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"traces"))
sys.path.insert(0,str(ROOT/"corpus"))
from trace import require,validate
from corpus import validate as validate_corpus


def small_schoolbook(left,right,radix,drop_carry=False):
    output=[0]*(len(left)+len(right))
    events=[]
    for i,a in enumerate(left):
        carry=0
        for j,b in enumerate(right):
            intermediate=a*b+output[i+j]+carry
            output[i+j]=intermediate%radix
            carry=0 if drop_carry else intermediate//radix
            events.append((i,j,intermediate,carry))
        output[i+len(right)]=carry
    return output,events


def carry_signature(parsed):
    current,longest,count=0,0,0
    maximum_width=0
    for event in parsed["events"]:
        if event["kind"]=="multiply-accumulate":
            if len(event["dependencies"])==3:
                current=0  # a new schoolbook row starts with zero carry
            maximum_width=max(maximum_width,event["value"].bit_length())
        elif event["kind"]=="carry":
            nonzero=event["value"]!=0
            count+=nonzero
            current=current+1 if nonzero else 0
            longest=max(longest,current)
    return {"radix":2**32,"scan":"schoolbook-row-order","nonzero_carry_events":count,
            "longest_serial_nonzero_segment":longest,"maximum_intermediate_bits":maximum_width,
            "normalization_passes":1,"scratch_restoration":"UNKNOWN"}


def certificate(value,bound,trusted_bound,truncation,expected_truncation,before,after,claimed_restore):
    # These are exact validator fixtures. trusted_bound must come from a separately
    # established contract; sampling discrepancies cannot create that contract.
    require(isinstance(value,Fraction) and isinstance(bound,Fraction),"exact rational certificate required")
    require(0<=bound<=trusted_bound,"unsupported/relaxed error bound")
    require(truncation==expected_truncation,"changed truncation location")
    nearest=(value.numerator*2+value.denominator)//(2*value.denominator)
    margin=Fraction(1,2)-abs(value-nearest)-bound
    require(margin>0,"recovery interval touches an ambiguous rounding boundary")
    require(not claimed_restore or before==after,"false scratch restoration")
    return nearest,margin


def main():
    checked=0
    for radix in (2,4,8):
        digits=list(itertools.product(range(radix),repeat=2))
        for left in digits:
            for right in digits:
                output,_=small_schoolbook(left,right,radix)
                a=left[0]+radix*left[1]; b=right[0]+radix*right[1]
                direct=a*b
                require(sum(digit*radix**index for index,digit in enumerate(output))==direct,"small-radix direct oracle")
                checked+=1
    wrong,_=small_schoolbook([7,7],[7,7],8,True)
    require(sum(digit*8**index for index,digit in enumerate(wrong))!=63**2,"dropped carry mutant invisible")
    run=subprocess.run([sys.executable,str(ROOT/"traces/check_mb17.py")],capture_output=True,text=True,timeout=60)
    require(run.returncode==0,run.stderr)
    traces=json.loads(run.stdout)["traces"]
    signatures=[]
    for raw in traces:
        parsed=validate(raw["raw_trace"],raw["source_sha256"],raw["binary_sha256"],raw["left_limbs"],raw["right_limbs"])
        signatures.append({"case_sha256":parsed["metadata"]["case_sha256"],"signature":carry_signature(parsed)})
    with (ROOT/"corpus/smoke-v2.tsv").open("rb") as stream:
        corpus=validate_corpus(stream)
    require(any(row["family"]=="ones" for row in corpus) and any(row["family"]=="near-power" for row in corpus),"required carry corpus families")
    nearest,margin=certificate(Fraction(249,100),Fraction(1,1000),Fraction(1,1000),"after-product","after-product",[1,2],[1,2],True)
    require(nearest==2 and margin==Fraction(9,1000),"exact recovery margin")
    rejected=[]
    for name,args in {
        "rounding-boundary":(Fraction(5,2),Fraction(0),Fraction(0),"after-product","after-product",[],[],False),
        "relaxed-bound":(Fraction(2),Fraction(1,100),Fraction(1,1000),"after-product","after-product",[],[],False),
        "truncation-location":(Fraction(2),Fraction(0),Fraction(0),"before-product","after-product",[],[],False),
        "scratch-restoration":(Fraction(2),Fraction(0),Fraction(0),"after-product","after-product",[1],[2],True),
    }.items():
        try:
            certificate(*args)
        except ValueError:
            rejected.append(name)
        else:
            raise ValueError(f"certificate defect passed: {name}")
    print(json.dumps({"job":"MB19","status":"PASS_SCOPED","small_radix_products":checked,
                      "signatures":signatures,"mutants_rejected":["dropped-carry",*rejected],
                      "paper_precision_certificates":"NOT_RUN: requires MB16 and accepted MUL3/MUL4 contracts",
                      "certificate_scope":"exact rational fixture validation, not a newly proved error bound"}))


if __name__=="__main__":
    main()
