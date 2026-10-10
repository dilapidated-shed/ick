module ordinary_d_peer;

// Same spelling and signature as ordinary_d_linkage. Module qualification must
// keep these as different linker symbols, including at imported call sites.
int ordinary_d_identity(int value) { return value + 100; }
