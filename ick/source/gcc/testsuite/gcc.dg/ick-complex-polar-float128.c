/* { dg-do compile } */
/* { dg-options "-O2" } */
/* { dg-add-options float128 } */
/* { dg-require-effective-target float128 } */

/* x86-64 libgcc uses TFmode for __multc3/__divtc3.  ICK's polar
   conversion must be able to perform hypot/atan2/sin/cos at that precision
   instead of stopping its widening ladder at long double.  */

_Float128 _Complex
make_complex_float128 (_Float128 real, _Float128 imaginary)
{
  return __builtin_complex (real, imaginary);
}
