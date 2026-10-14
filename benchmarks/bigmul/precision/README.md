# Realized carry evidence

The checker computes nonzero carry-event counts and longest serial nonzero
segments from executed schoolbook traces. A segment resets at each row's initial
zero carry. It records the maximum actual intermediate bit width separately
from input bit patterns. Exhaustive two-digit controls in radix 2, 4 and 8 use
direct integer multiplication as an independent product oracle.

The recovery validator operates on exact rational values and trusted error bounds.
The whole interval must stay strictly inside one nearest-integer rounding cell;
a tie or unknown/relaxed bound cannot pass. It checks the declared truncation
location and actual scratch before/after state. These are validator fixtures.
No sampled discrepancy becomes a rigorous bound. Paper-stage magnitudes,
Gaussian widths, truncation and certified bounds await accepted MUL3/MUL4/MB16.
Signed packed coefficients are also pending those accepted encoding contracts.
The baseline does not claim scratch restoration merely because values are right.
