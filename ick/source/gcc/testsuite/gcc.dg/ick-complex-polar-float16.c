/* { dg-do compile } */
/* { dg-options "-O2" } */

/* _Float16 has no complete hypot/atan2/sin/cos builtin family on targets
   such as x86_64.  ICK must widen polar transcendental work instead of
   asserting in complex lowering.  */

_Float16 _Complex
make_complex_half (_Float16 real, _Float16 imaginary)
{
  return __builtin_complex (real, imaginary);
}
