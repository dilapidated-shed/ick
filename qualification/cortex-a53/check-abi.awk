/Class:/ { if ($2 == "ELF64") class_ok = 1 }
/Machine:/ { if ($2 == "AArch64") machine_ok = 1 }
/Type:/ { if ($2 == "DYN") dynamic_ok = 1 }
/Flags:/ { if ($2 == "0x0") flags_ok = 1 }
/^[[:space:]]*LOAD/ { loads++; if ($NF != "0x4000") bad_alignment = 1 }
END {
    if (!class_ok || !machine_ok || !dynamic_ok || !flags_ok || !loads || bad_alignment) {
        print "FAIL ELF64/AArch64/DYN/16KiB load contract" > "/dev/stderr";
        exit 1;
    }
}
