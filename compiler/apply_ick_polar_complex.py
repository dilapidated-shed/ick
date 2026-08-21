#!/usr/bin/env python3
"""Apply the ICK polar-complex experiment to the exact inspected GCC tree.

Run from the root of isomorphisms/the-equality-sign-means-equality on
branch circles-are-balanced at commit 756f5b0aeeabc67caf804380495f82d86b87b878.

The script deliberately refuses source drift.  It edits the working tree only:
no git add, commit, branch update, or push is performed.
"""
from __future__ import annotations

import hashlib
import sys
from pathlib import Path

EXPECTED = {
    "gcc/tree-complex.cc": "98b022f1b2c67763deed2e2ccaf9d04370e3c045",
    "gcc/c/c-typeck.cc": "5199a352ecc97878bdca68d60dc6a2b40c6812e0",
    "gcc/varasm.cc": "0dbc35d926a34031d7e980e6c9a6b6a1c06ed776",
    "gcc/builtins.def": "4adeb440ed9dada5a40ceed0ca1c96c80e9fb787",
}

ROOT = Path.cwd()


def git_blob_sha(data: bytes) -> str:
    hdr = f"blob {len(data)}\0".encode()
    return hashlib.sha1(hdr + data).hexdigest()


def load(rel: str) -> str:
    p = ROOT / rel
    if not p.is_file():
        raise SystemExit(f"missing {rel}; run this from the GCC repository root")
    data = p.read_bytes()
    got = git_blob_sha(data)
    want = EXPECTED[rel]
    if got != want:
        raise SystemExit(
            f"refusing source drift in {rel}: expected blob {want}, got {got}"
        )
    return data.decode("utf-8")


def store(rel: str, text: str) -> None:
    p = ROOT / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    n = text.count(old)
    if n != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {n}")
    return text.replace(old, new, 1)


def replace_n(text: str, old: str, new: str, count: int, label: str) -> str:
    n = text.count(old)
    if n != count:
        raise SystemExit(f"{label}: expected {count} matches, found {n}")
    return text.replace(old, new)


def replace_region(text: str, start: str, end: str, replacement: str, label: str) -> str:
    a = text.find(start)
    if a < 0:
        raise SystemExit(f"{label}: start marker not found")
    b = text.find(end, a)
    if b < 0:
        raise SystemExit(f"{label}: end marker not found")
    return text[:a] + replacement + text[b:]


# Verify the entire inspected source set before computing or writing edits.
source = {rel: load(rel) for rel in EXPECTED}

# ---------------------------------------------------------------------------
# gcc/builtins.def: private middle-end hooks for complex floor/ceil.
# ---------------------------------------------------------------------------
builtins = source["gcc/builtins.def"]
old = '''DEF_LIB_BUILTIN        (BUILT_IN_FLOOR, "floor", BT_FN_DOUBLE_DOUBLE, ATTR_CONST_NOTHROW_LEAF_LIST)
DEF_C99_C90RES_BUILTIN (BUILT_IN_FLOORF, "floorf", BT_FN_FLOAT_FLOAT, ATTR_CONST_NOTHROW_LEAF_LIST)
DEF_C99_C90RES_BUILTIN (BUILT_IN_FLOORL, "floorl", BT_FN_LONGDOUBLE_LONGDOUBLE, ATTR_CONST_NOTHROW_LEAF_LIST)
#define FLOOR_TYPE(F) BT_FN_##F##_##F
DEF_EXT_LIB_FLOATN_NX_BUILTINS (BUILT_IN_FLOOR, "floor", FLOOR_TYPE, ATTR_CONST_NOTHROW_LEAF_LIST)
#undef FLOOR_TYPE
'''
new = old + '''/* ICK extension: radial floor/ceiling for floating complex values.
   These are implementation hooks; the C front end redirects ordinary
   floor/ceil spellings here when the actual argument has complex type.  */
DEF_GCC_BUILTIN        (BUILT_IN_CFLOOR, "cfloor", BT_FN_COMPLEX_DOUBLE_COMPLEX_DOUBLE, ATTR_CONST_NOTHROW_LEAF_LIST)
DEF_GCC_BUILTIN        (BUILT_IN_CFLOORF, "cfloorf", BT_FN_COMPLEX_FLOAT_COMPLEX_FLOAT, ATTR_CONST_NOTHROW_LEAF_LIST)
DEF_GCC_BUILTIN        (BUILT_IN_CFLOORL, "cfloorl", BT_FN_COMPLEX_LONGDOUBLE_COMPLEX_LONGDOUBLE, ATTR_CONST_NOTHROW_LEAF_LIST)
DEF_GCC_BUILTIN        (BUILT_IN_CCEIL, "cceil", BT_FN_COMPLEX_DOUBLE_COMPLEX_DOUBLE, ATTR_CONST_NOTHROW_LEAF_LIST)
DEF_GCC_BUILTIN        (BUILT_IN_CCEILF, "cceilf", BT_FN_COMPLEX_FLOAT_COMPLEX_FLOAT, ATTR_CONST_NOTHROW_LEAF_LIST)
DEF_GCC_BUILTIN        (BUILT_IN_CCEILL, "cceill", BT_FN_COMPLEX_LONGDOUBLE_COMPLEX_LONGDOUBLE, ATTR_CONST_NOTHROW_LEAF_LIST)
'''
builtins = replace_once(builtins, old, new, "builtins: complex rounding hooks")


# ---------------------------------------------------------------------------
# gcc/c/c-typeck.cc: dispatch floor/ceil(complex) before prototype conversion
# discards the imaginary part.
# ---------------------------------------------------------------------------
ctype = source["gcc/c/c-typeck.cc"]
ctype = replace_once(
    ctype,
    '#include "realmpfr.h"\n#include "tree-pretty-print-markup.h"',
    '#include "realmpfr.h"\n#include "builtins.h"\n#include "tree-pretty-print-markup.h"',
    "c-typeck: include builtins.h",
)

helper = r'''/* ICK gives the ordinary floor/ceil spellings a floating-complex
   overload.  Dispatch before convert_arguments applies the ordinary C
   prototype and loses the imaginary component.  */
static enum built_in_function
ick_complex_rounding_builtin (tree fundecl, tree arg)
{
  if (!fundecl
      || !fndecl_built_in_p (fundecl, BUILT_IN_NORMAL)
      || !arg
      || TREE_CODE (TREE_TYPE (arg)) != COMPLEX_TYPE
      || !SCALAR_FLOAT_TYPE_P (TREE_TYPE (TREE_TYPE (arg))))
    return END_BUILTINS;

  switch ((enum built_in_function) DECL_FUNCTION_CODE (fundecl))
    {
    case BUILT_IN_FLOOR:
      return BUILT_IN_CFLOOR;
    case BUILT_IN_FLOORF:
      return BUILT_IN_CFLOORF;
    case BUILT_IN_FLOORL:
      return BUILT_IN_CFLOORL;
    case BUILT_IN_CEIL:
      return BUILT_IN_CCEIL;
    case BUILT_IN_CEILF:
      return BUILT_IN_CCEILF;
    case BUILT_IN_CEILL:
      return BUILT_IN_CCEILL;
    default:
      return END_BUILTINS;
    }
}

'''
marker = '''tree
build_function_call_vec (location_t loc, vec<location_t> arg_loc,
'''
ctype = replace_once(ctype, marker, helper + marker, "c-typeck: insert dispatch helper")

old = '''      if (name && startswith (IDENTIFIER_POINTER (name), "__atomic_"))
        origtypes = NULL;
    }
  if (TREE_CODE (TREE_TYPE (function)) == FUNCTION_TYPE)
    function = function_to_pointer_conversion (loc, function);
'''
new = '''      if (name && startswith (IDENTIFIER_POINTER (name), "__atomic_"))
        origtypes = NULL;
    }

  if (fundecl && params && params->length () == 1)
    {
      enum built_in_function code
        = ick_complex_rounding_builtin (fundecl, (*params)[0]);
      if (code != END_BUILTINS)
        {
          fundecl = builtin_decl_explicit (code);
          gcc_assert (fundecl);
          function = fundecl;
          name = DECL_NAME (fundecl);
          orig_fundecl = fundecl;
        }
    }

  if (TREE_CODE (TREE_TYPE (function)) == FUNCTION_TYPE)
    function = function_to_pointer_conversion (loc, function);
'''
ctype = replace_once(ctype, old, new, "c-typeck: redirect complex rounding calls")


# ---------------------------------------------------------------------------
# gcc/varasm.cc: static floating-complex constants are emitted as (rho,theta).
# ---------------------------------------------------------------------------
varasm = source["gcc/varasm.cc"]
varasm = replace_once(
    varasm,
    '#include "gimple-expr.h"\n',
    '#include "gimple-expr.h"\n#include "realmpfr.h"\n',
    "varasm: include realmpfr.h",
)

helper = r'''/* Convert a semantic Cartesian COMPLEX_CST to ICK's physical
   (modulus, argument) pair using MPFR, then round each component to the
   actual target real type.  The zero value has canonical argument +0.  */
static void
ick_polar_complex_constant_parts (tree exp, tree *radius, tree *angle)
{
  gcc_assert (TREE_CODE (exp) == COMPLEX_CST);
  tree inner_type = TREE_TYPE (TREE_TYPE (exp));
  tree real = TREE_REALPART (exp);
  tree imag = TREE_IMAGPART (exp);
  gcc_assert (SCALAR_FLOAT_TYPE_P (inner_type));
  gcc_assert (TREE_CODE (real) == REAL_CST && TREE_CODE (imag) == REAL_CST);

  mpfr_prec_t precision = 2 * TYPE_PRECISION (inner_type);
  if (precision < 256)
    precision = 256;

  auto_mpfr x (precision), y (precision), r (precision), theta (precision);
  mpfr_from_real (x, &TREE_REAL_CST (real), MPFR_RNDN);
  mpfr_from_real (y, &TREE_REAL_CST (imag), MPFR_RNDN);
  mpfr_hypot (r, x, y, MPFR_RNDN);
  if (mpfr_zero_p (r))
    mpfr_set_zero (theta, 1);
  else
    mpfr_atan2 (theta, y, x, MPFR_RNDN);

  REAL_VALUE_TYPE rv, av;
  real_from_mpfr (&rv, r, inner_type, MPFR_RNDN);
  real_from_mpfr (&av, theta, inner_type, MPFR_RNDN);
  *radius = build_real (inner_type, rv);
  *angle = build_real (inner_type, av);
}

'''
marker = '''static unsigned HOST_WIDE_INT
output_constant (tree, unsigned HOST_WIDE_INT, unsigned int, bool,
'''
varasm = replace_once(varasm, marker, helper + marker, "varasm: constant polar helper")
old = '''    case COMPLEX_TYPE:
      output_constant (TREE_REALPART (exp), thissize / 2, align,
\t\t       reverse, false);
      output_constant (TREE_IMAGPART (exp), thissize / 2,
\t\t       min_align (align, BITS_PER_UNIT * (thissize / 2)),
\t\t       reverse, false);
      break;
'''
new = '''    case COMPLEX_TYPE:
      if (SCALAR_FLOAT_TYPE_P (TREE_TYPE (TREE_TYPE (exp))))
        {
          tree radius, angle;
          ick_polar_complex_constant_parts (exp, &radius, &angle);
          output_constant (radius, thissize / 2, align, reverse, false);
          output_constant (angle, thissize / 2,
                           min_align (align, BITS_PER_UNIT * (thissize / 2)),
                           reverse, false);
          break;
        }
      output_constant (TREE_REALPART (exp), thissize / 2, align,
\t\t       reverse, false);
      output_constant (TREE_IMAGPART (exp), thissize / 2,
\t\t       min_align (align, BITS_PER_UNIT * (thissize / 2)),
\t\t       reverse, false);
      break;
'''
varasm = replace_once(varasm, old, new, "varasm: emit floating complex polar")


# ---------------------------------------------------------------------------
# gcc/tree-complex.cc
# ---------------------------------------------------------------------------
tc = source["gcc/tree-complex.cc"]
tc = replace_once(
    tc,
    '#include "tree-ssa-dce.h"\n',
    '#include "tree-ssa-dce.h"\n#include "realmpfr.h"\n',
    "tree-complex: include realmpfr.h",
)

old = '''static bool
is_complex_reg (tree lhs)
{
  return TREE_CODE (TREE_TYPE (lhs)) == COMPLEX_TYPE && is_gimple_reg (lhs);
}
'''
new = old + r'''
/* ICK floating complex values are physically a pair (modulus, argument).
   GCC's COMPLEX_CST remains a semantic Cartesian tree constant until it is
   lowered or emitted.  */
static bool
floating_complex_type_p (tree type)
{
  return (TREE_CODE (type) == COMPLEX_TYPE
          && SCALAR_FLOAT_TYPE_P (TREE_TYPE (type)));
}

static enum built_in_function
normal_builtin_code (gimple *stmt)
{
  tree decl = is_gimple_call (stmt) ? gimple_call_fndecl (stmt) : NULL_TREE;
  if (!decl || !fndecl_built_in_p (decl, BUILT_IN_NORMAL))
    return END_BUILTINS;
  return (enum built_in_function) DECL_FUNCTION_CODE (decl);
}
'''
tc = replace_once(tc, old, new, "tree-complex: type/builtin helpers")

old = '''\t\t  switch (gimple_call_combined_fn (stmt))
\t\t    {
\t\t    CASE_CFN_CABS:
\t\t      /* Expand cabs only if unsafe math and optimizing. */
\t\t      if (optimize && flag_unsafe_math_optimizations)
\t\t\tsaw_a_complex_op = true;
\t\t      break;
\t\t    default:;
\t\t    }
'''
new = '''\t\t  switch (normal_builtin_code (stmt))
\t\t    {
\t\t    case BUILT_IN_CABS:
\t\t    case BUILT_IN_CABSF:
\t\t    case BUILT_IN_CABSL:
\t\t    case BUILT_IN_CARG:
\t\t    case BUILT_IN_CARGF:
\t\t    case BUILT_IN_CARGL:
\t\t    case BUILT_IN_CFLOOR:
\t\t    case BUILT_IN_CFLOORF:
\t\t    case BUILT_IN_CFLOORL:
\t\t    case BUILT_IN_CCEIL:
\t\t    case BUILT_IN_CCEILF:
\t\t    case BUILT_IN_CCEILL:
\t\t      saw_a_complex_op = true;
\t\t      break;
\t\t    default:;
\t\t    }
'''
tc = replace_once(tc, old, new, "tree-complex: force complex builtin lowering")
tc = replace_once(
    tc,
    "\t\t}\n\t      break;\n\n\t    case GIMPLE_ASSIGN:",
    "\t\t}\n"
    "\t      if (gimple_call_lhs (stmt)\n"
    "\t\t  && is_complex_reg (gimple_call_lhs (stmt)))\n"
    "\t\t saw_a_complex_op = true;\n"
    "\t      for (unsigned int i = 0; i < gimple_call_num_args (stmt); ++i)\n"
    "\t\tif (TREE_CODE (TREE_TYPE (gimple_call_arg (stmt, i)))\n"
    "\t\t    == COMPLEX_TYPE)\n"
    "\t\t  {\n"
    "\t\t    saw_a_complex_op = true;\n"
    "\t\t    break;\n"
    "\t\t  }\n"
    "\t      break;\n\n\t    case GIMPLE_ASSIGN:",
    "tree-complex: mark complex call boundaries",
)

# Disable Cartesian lattice's synthetic zero component for floating polar.
tc = replace_n(
    tc,
    '''  if (lattice == (imag_p ? ONLY_REAL : ONLY_IMAG))\n''',
    '''  if (!floating_complex_type_p (TREE_TYPE (ssa_name))
      && lattice == (imag_p ? ONLY_REAL : ONLY_IMAG))\n''',
    2,
    "tree-complex: lattice zero shortcut",
)

# Forward declarations before the component extractor uses polar helpers.
old = '''/* Extract the real or imaginary part of a complex variable or constant.
   Make sure that it's a proper gimple_val and gimplify it if not.
   Emit any new code before gsi.  */

static tree
extract_component (gimple_stmt_iterator *gsi, tree t, bool imagpart_p,
\t\t   bool gimple_p, bool phiarg_p = false)
'''
new = r'''static bool polar_math_builtins_available (tree);
static tree build_polar_unary_call (gimple_seq *, location_t, tree,
                                    enum built_in_function, tree);
static tree build_polar_binary_call (gimple_seq *, location_t, tree,
                                     enum built_in_function, tree, tree);

/* Convert one Cartesian tree constant to ICK's physical polar pair.  */
static void
polar_constant_parts (tree t, tree *radius, tree *angle)
{
  tree inner_type = TREE_TYPE (TREE_TYPE (t));
  tree real = TREE_REALPART (t);
  tree imag = TREE_IMAGPART (t);

  mpfr_prec_t precision = 2 * TYPE_PRECISION (inner_type);
  if (precision < 256)
    precision = 256;
  auto_mpfr x (precision), y (precision), r (precision), theta (precision);
  mpfr_from_real (x, &TREE_REAL_CST (real), MPFR_RNDN);
  mpfr_from_real (y, &TREE_REAL_CST (imag), MPFR_RNDN);
  mpfr_hypot (r, x, y, MPFR_RNDN);
  if (mpfr_zero_p (r))
    mpfr_set_zero (theta, 1);
  else
    mpfr_atan2 (theta, y, x, MPFR_RNDN);

  REAL_VALUE_TYPE rv, av;
  real_from_mpfr (&rv, r, inner_type, MPFR_RNDN);
  real_from_mpfr (&av, theta, inner_type, MPFR_RNDN);
  *radius = build_real (inner_type, rv);
  *angle = build_real (inner_type, av);
}

/* Extract a raw physical slot.  For floating complex this is modulus for
   slot zero and argument for slot one.  */
static tree
extract_storage_component (gimple_stmt_iterator *gsi, tree t,
                           bool second_slot_p, bool gimple_p,
                           bool phiarg_p = false)
'''
tc = replace_once(tc, old, new, "tree-complex: split component extractor")

# Rename variables within the now-raw extractor region only.
start = tc.find('static tree\nextract_storage_component')
end = tc.find('/* Update the complex components of the ssa name on the lhs of STMT.  */', start)
if start < 0 or end < 0:
    raise SystemExit("tree-complex: raw extractor region not found")
region = tc[start:end]
region = region.replace('imagpart_p', 'second_slot_p')
# Complex constants need physical polar slots, not semantic Cartesian slots.
old_const = '''    case COMPLEX_CST:
      return second_slot_p ? TREE_IMAGPART (t) : TREE_REALPART (t);
'''
new_const = '''    case COMPLEX_CST:
      if (floating_complex_type_p (TREE_TYPE (t)))
        {
          tree radius, angle;
          polar_constant_parts (t, &radius, &angle);
          return second_slot_p ? angle : radius;
        }
      return second_slot_p ? TREE_IMAGPART (t) : TREE_REALPART (t);
'''
region = replace_once(region, old_const, new_const, "tree-complex: constant raw polar slots")
tc = tc[:start] + region + tc[end:]

# Add semantic Cartesian extractor after raw extractor and before update helper.
insert_at = tc.find('/* Update the complex components of the ssa name on the lhs of STMT.  */')
semantic = r'''/* Extract a mathematical Cartesian component.  Existing GCC middle-end code
   is allowed to keep asking for real/imaginary values; ICK reconstructs them
   from its physical (rho,theta) pair.  */
static tree
extract_component (gimple_stmt_iterator *gsi, tree t, bool imagpart_p,
                   bool gimple_p, bool phiarg_p = false)
{
  if (!floating_complex_type_p (TREE_TYPE (t)))
    return extract_storage_component (gsi, t, imagpart_p, gimple_p, phiarg_p);

  if (TREE_CODE (t) == COMPLEX_CST)
    return imagpart_p ? TREE_IMAGPART (t) : TREE_REALPART (t);

  gcc_assert (gsi && gimple_p);
  tree inner_type = TREE_TYPE (TREE_TYPE (t));
  tree radius = extract_storage_component (gsi, t, false, true, phiarg_p);
  tree angle = extract_storage_component (gsi, t, true, true, phiarg_p);
  gimple_seq stmts = NULL;
  location_t loc = gimple_location (gsi_stmt (*gsi));
  enum built_in_function trig = imagpart_p ? BUILT_IN_SIN : BUILT_IN_COS;
  tree direction = build_polar_unary_call (&stmts, loc, inner_type, trig, angle);
  tree result = gimple_build (&stmts, loc, MULT_EXPR, inner_type,
                              radius, direction);
  gsi_insert_seq_before (gsi, stmts, GSI_SAME_STMT);
  return result;
}

'''
if insert_at < 0:
    raise SystemExit("tree-complex: semantic extractor insertion marker missing")
tc = tc[:insert_at] + semantic + tc[insert_at:]

# Replace assignment updater with raw-pair updater + Cartesian->polar converter.
start_marker = '/* Update an assignment to a complex variable in place.  */\n\nstatic void\nupdate_complex_assignment'
end_marker = '/* Generate code at the entry point of the function to initialize the\n'
start = tc.find(start_marker)
end = tc.find(end_marker, start)
if start < 0 or end < 0:
    raise SystemExit("tree-complex: assignment updater region missing")
replacement = r'''/* Update an assignment whose two values already are the physical pair.
   For floating ICK complex values this pair is (modulus, argument).  */
static void
update_polar_assignment (gimple_stmt_iterator *gsi, tree radius, tree angle)
{
  gimple *old_stmt = gsi_stmt (*gsi);
  gimple_assign_set_rhs_with_ops (gsi, COMPLEX_EXPR, radius, angle);
  gimple *stmt = gsi_stmt (*gsi);
  update_stmt (stmt);
  if (maybe_clean_or_replace_eh_stmt (old_stmt, stmt))
    bitmap_set_bit (need_eh_cleanup, gimple_bb (stmt)->index);
  if (optimize)
    bitmap_set_bit (dce_worklist, SSA_NAME_VERSION (gimple_assign_lhs (stmt)));

  update_complex_components (gsi, gsi_stmt (*gsi), radius, angle);
}

/* Convert a semantic Cartesian assignment to the ICK physical pair.  */
static void
update_complex_assignment (gimple_stmt_iterator *gsi, tree real, tree imag)
{
  tree lhs = gimple_get_lhs (gsi_stmt (*gsi));
  tree complex_type = TREE_TYPE (lhs);
  if (!floating_complex_type_p (complex_type))
    {
      update_polar_assignment (gsi, real, imag);
      return;
    }

  tree inner_type = TREE_TYPE (complex_type);
  gcc_assert (polar_math_builtins_available (inner_type));
  gimple_seq stmts = NULL;
  location_t loc = gimple_location (gsi_stmt (*gsi));
  tree radius = build_polar_binary_call (&stmts, loc, inner_type,
                                         BUILT_IN_HYPOT, real, imag);
  tree angle = build_polar_binary_call (&stmts, loc, inner_type,
                                        BUILT_IN_ATAN2, imag, real);
  gsi_insert_seq_before (gsi, stmts, GSI_SAME_STMT);
  update_polar_assignment (gsi, radius, angle);
}

'''
tc = tc[:start] + replacement + tc[end:]

# PHIs deal in raw physical slots.
tc = replace_n(
    tc,
    'extract_component (NULL, arg,',
    'extract_storage_component (NULL, arg,',
    2,
    "tree-complex: raw PHI slots",
)

# Incoming parameter components are already raw ABI slots; comments/names aside,
# existing REALPART_EXPR/IMAGPART_EXPR loads are deliberately kept here.

# Complex move: pure floating-complex copies must copy physical slots.
old = '''\t  if (gimple_assign_rhs_code (stmt) != COMPLEX_EXPR)
\t    {
\t      r = extract_component (gsi, rhs, 0, true);
\t      i = extract_component (gsi, rhs, 1, true);
\t    }
\t  else
\t    {
\t      r = gimple_assign_rhs1 (stmt);
\t      i = gimple_assign_rhs2 (stmt);
\t    }
\t  update_complex_assignment (gsi, r, i);
'''
new = '''\t  if (floating_complex_type_p (type)
\t      && gimple_assign_rhs_code (stmt) != COMPLEX_EXPR
\t      && TREE_CODE (rhs) != COMPLEX_CST)
\t    {
\t      r = extract_storage_component (gsi, rhs, false, true);
\t      i = extract_storage_component (gsi, rhs, true, true);
\t      update_polar_assignment (gsi, r, i);
\t      return;
\t    }
\t  if (gimple_assign_rhs_code (stmt) != COMPLEX_EXPR)
\t    {
\t      r = extract_component (gsi, rhs, 0, true);
\t      i = extract_component (gsi, rhs, 1, true);
\t    }
\t  else
\t    {
\t      r = gimple_assign_rhs1 (stmt);
\t      i = gimple_assign_rhs2 (stmt);
\t    }
\t  update_complex_assignment (gsi, r, i);
'''
tc = replace_once(tc, old, new, "tree-complex: polar SSA moves")

old = '''      loc = gimple_location (stmt);
      r = extract_component (gsi, rhs, 0, false);
      i = extract_component (gsi, rhs, 1, false);

      x = build1 (REALPART_EXPR, inner_type, unshare_expr (lhs));
'''
new = '''      loc = gimple_location (stmt);
      if (floating_complex_type_p (TREE_TYPE (rhs)))
        {
          r = extract_storage_component (gsi, rhs, false, false);
          i = extract_storage_component (gsi, rhs, true, false);
        }
      else
        {
          r = extract_component (gsi, rhs, 0, false);
          i = extract_component (gsi, rhs, 1, false);
        }

      x = build1 (REALPART_EXPR, inner_type, unshare_expr (lhs));
'''
tc = replace_once(tc, old, new, "tree-complex: polar memory stores")

# Replace old temporary-polar helpers with true native-polar helpers.
start = tc.find('static void\nexpand_complex_multiplication_polar')
end = tc.find('/* Perform a complex multiplication on two complex constants', start)
if start < 0 or end < 0:
    raise SystemExit("tree-complex: old polar helper region missing")
replacement = r'''static void
expand_complex_multiplication_polar (gimple_stmt_iterator *gsi, tree type,
                                     tree a_radius, tree a_angle,
                                     tree b_radius, tree b_angle)
{
  gimple_seq stmts = NULL;
  location_t loc = gimple_location (gsi_stmt (*gsi));
  tree radius = gimple_build (&stmts, loc, MULT_EXPR, type,
                              a_radius, b_radius);
  tree angle = gimple_build (&stmts, loc, PLUS_EXPR, type,
                             a_angle, b_angle);
  gsi_insert_seq_before (gsi, stmts, GSI_SAME_STMT);
  update_polar_assignment (gsi, radius, angle);
}

static void
expand_complex_division_polar (gimple_stmt_iterator *gsi, tree type,
                               tree a_radius, tree a_angle,
                               tree b_radius, tree b_angle,
                               enum tree_code code)
{
  gimple_seq stmts = NULL;
  location_t loc = gimple_location (gsi_stmt (*gsi));
  tree radius = gimple_build (&stmts, loc, code, type,
                              a_radius, b_radius);
  tree angle = gimple_build (&stmts, loc, MINUS_EXPR, type,
                             a_angle, b_angle);
  gsi_insert_seq_before (gsi, stmts, GSI_SAME_STMT);
  update_polar_assignment (gsi, radius, angle);
}

'''
tc = tc[:start] + replacement + tc[end:]

# Remove obsolete early paths in Cartesian multiply/divide; native polar is
# now dispatched before Cartesian extraction in expand_complex_operations_1.
old = '''  if (SCALAR_FLOAT_TYPE_P (inner_type)
      && polar_math_builtins_available (inner_type))
    {
      expand_complex_multiplication_polar (&stmts, loc, inner_type,
\t\t\t\t\t   ar, ai, br, bi, &rr, &ri);
      gsi_insert_seq_before (gsi, stmts, GSI_SAME_STMT);
      update_complex_assignment (gsi, rr, ri);
      return;
    }

'''
tc = replace_once(tc, old, '', "tree-complex: remove old multiply polar roundtrip")
old = '''  if (SCALAR_FLOAT_TYPE_P (inner_type)
      && polar_math_builtins_available (inner_type))
    {
      expand_complex_division_polar (&stmts, loc, inner_type,
\t\t\t\t     ar, ai, br, bi, code, &rr, &ri);
      gsi_insert_seq_before (gsi, stmts, GSI_SAME_STMT);
      update_complex_assignment (gsi, rr, ri);
      return;
    }

'''
tc = replace_once(tc, old, '', "tree-complex: remove old divide polar roundtrip")

# cabs for floating complex is exactly the first physical slot.
needle = '''  /* If there is not a LHS, then just keep the statement around.  */
  if (!lhs)
    return;

  real_part = extract_component (gsi, arg, false, true);
'''
replacement = '''  /* If there is not a LHS, then just keep the statement around.  */
  if (!lhs)
    return;

  if (floating_complex_type_p (TREE_TYPE (arg)))
    {
      tree radius = extract_storage_component (gsi, arg, false, true);
      new_stmt = gimple_build_assign (lhs, radius);
      gimple_set_location (new_stmt, gimple_location (old_stmt));
      gsi_replace (gsi, new_stmt, true);
      return;
    }

  real_part = extract_component (gsi, arg, false, true);
'''
tc = replace_once(tc, needle, replacement, "tree-complex: direct cabs")

# Add carg and radial round expanders after cabs.
marker = '/* Process one statement.  If we identify a complex operation, expand it.  */\n'
extra = r'''/* carg remains a semantic operation: return the principal phase even if the
   stored polar argument has wandered outside [-pi,pi] after multiplication or
   division.  Reconstructing the Cartesian pair also preserves the usual NaN
   and signed-zero behavior better than returning the raw angle slot.  */
static void
gimple_expand_builtin_carg (gimple_stmt_iterator *gsi, gimple *old_stmt)
{
  tree lhs = gimple_call_lhs (old_stmt);
  if (!lhs)
    return;
  tree arg = gimple_call_arg (old_stmt, 0);
  tree inner_type = TREE_TYPE (TREE_TYPE (arg));
  tree real = extract_component (gsi, arg, false, true);
  tree imag = extract_component (gsi, arg, true, true);
  gimple_seq stmts = NULL;
  tree principal = build_polar_binary_call (&stmts,
                                             gimple_location (old_stmt),
                                             inner_type, BUILT_IN_ATAN2,
                                             imag, real);
  gsi_insert_seq_before (gsi, stmts, GSI_SAME_STMT);
  gimple *new_stmt = gimple_build_assign (lhs, principal);
  gimple_set_location (new_stmt, gimple_location (old_stmt));
  gsi_replace (gsi, new_stmt, true);
}

/* ICK complex floor/ceil: round only the modulus and preserve the argument. */
static void
gimple_expand_builtin_cround (gimple_stmt_iterator *gsi, gimple *old_stmt,
                              enum built_in_function fncode)
{
  tree lhs = gimple_call_lhs (old_stmt);
  if (!lhs)
    return;

  tree arg = gimple_call_arg (old_stmt, 0);
  tree inner_type = TREE_TYPE (TREE_TYPE (arg));
  tree radius = extract_storage_component (gsi, arg, false, true);
  tree angle = extract_storage_component (gsi, arg, true, true);
  enum built_in_function rounding
    = (fncode == BUILT_IN_CFLOOR
       || fncode == BUILT_IN_CFLOORF
       || fncode == BUILT_IN_CFLOORL)
      ? BUILT_IN_FLOOR : BUILT_IN_CEIL;

  gimple_seq stmts = NULL;
  tree rounded = build_polar_unary_call (&stmts, gimple_location (old_stmt),
                                         inner_type, rounding, radius);
  gsi_insert_seq_before (gsi, stmts, GSI_SAME_STMT);

  tree rhs = build2 (COMPLEX_EXPR, TREE_TYPE (arg), rounded, angle);
  gimple *new_stmt = gimple_build_assign (lhs, rhs);
  gimple_set_location (new_stmt, gimple_location (old_stmt));
  gsi_replace (gsi, new_stmt, true);
  update_complex_components (gsi, new_stmt, rounded, angle);
}

/* A complex constant can appear directly as a GIMPLE_CALL argument rather
   than first passing through a complex assignment.  Materialize such constants
   as the ICK physical pair before the call so ICK-to-ICK call boundaries are
   consistently polar.  */
static void
polarize_complex_call_arguments (gimple_stmt_iterator *gsi, gimple *stmt)
{
  gcc_assert (is_gimple_call (stmt));
  bool changed = false;
  for (unsigned int i = 0; i < gimple_call_num_args (stmt); ++i)
    {
      tree arg = gimple_call_arg (stmt, i);
      if (TREE_CODE (arg) != COMPLEX_CST
          || !floating_complex_type_p (TREE_TYPE (arg)))
        continue;

      tree radius, angle;
      polar_constant_parts (arg, &radius, &angle);
      tree tmp = make_ssa_name (TREE_TYPE (arg));
      tree pair = build2 (COMPLEX_EXPR, TREE_TYPE (arg), radius, angle);
      gimple *assign = gimple_build_assign (tmp, pair);
      gimple_set_location (assign, gimple_location (stmt));
      gsi_insert_before (gsi, assign, GSI_SAME_STMT);
      gimple_call_set_arg (as_a <gcall *> (stmt), i, tmp);
      changed = true;
    }
  if (changed)
    update_stmt (stmt);
}

'''
tc = replace_once(tc, marker, extra + marker, "tree-complex: carg/cround expanders")

# Replace call dispatch in expand_complex_operations_1.
old = '''  if (gimple_code (stmt) == GIMPLE_CALL)
    {
      switch (gimple_call_combined_fn (stmt))
\t{
\tCASE_CFN_CABS:
\t  gimple_expand_builtin_cabs (gsi, stmt);
\t  return;
\tdefault:;
\t}
    }
'''
new = '''  if (gimple_code (stmt) == GIMPLE_CALL)
    {
      enum built_in_function fncode = normal_builtin_code (stmt);
      switch (fncode)
\t{
\tcase BUILT_IN_CABS:
\tcase BUILT_IN_CABSF:
\tcase BUILT_IN_CABSL:
\t  gimple_expand_builtin_cabs (gsi, stmt);
\t  return;
\tcase BUILT_IN_CARG:
\tcase BUILT_IN_CARGF:
\tcase BUILT_IN_CARGL:
\t  gimple_expand_builtin_carg (gsi, stmt);
\t  return;
\tcase BUILT_IN_CFLOOR:
\tcase BUILT_IN_CFLOORF:
\tcase BUILT_IN_CFLOORL:
\tcase BUILT_IN_CCEIL:
\tcase BUILT_IN_CCEILF:
\tcase BUILT_IN_CCEILL:
\t  gimple_expand_builtin_cround (gsi, stmt, fncode);
\t  return;
\tdefault:;
\t}
      polarize_complex_call_arguments (gsi, stmt);
    }
'''
tc = replace_once(tc, old, new, "tree-complex: builtin call dispatch")

# Dispatch floating multiply/divide on raw polar slots before Cartesian extract.
needle = '''  ar = extract_component (gsi, ac, false, true);
  ai = extract_component (gsi, ac, true, true);
'''
insert = r'''  if (SCALAR_FLOAT_TYPE_P (inner_type)
      && (code == MULT_EXPR
          || code == TRUNC_DIV_EXPR
          || code == CEIL_DIV_EXPR
          || code == FLOOR_DIV_EXPR
          || code == ROUND_DIV_EXPR
          || code == RDIV_EXPR))
    {
      tree a_radius = extract_storage_component (gsi, ac, false, true);
      tree a_angle = extract_storage_component (gsi, ac, true, true);
      tree b_radius, b_angle;
      if (ac == bc)
        b_radius = a_radius, b_angle = a_angle;
      else
        {
          b_radius = extract_storage_component (gsi, bc, false, true);
          b_angle = extract_storage_component (gsi, bc, true, true);
        }

      if (code == MULT_EXPR)
        expand_complex_multiplication_polar (gsi, inner_type,
                                             a_radius, a_angle,
                                             b_radius, b_angle);
      else
        expand_complex_division_polar (gsi, inner_type,
                                       a_radius, a_angle,
                                       b_radius, b_angle, code);
      return;
    }

  ar = extract_component (gsi, ac, false, true);
  ai = extract_component (gsi, ac, true, true);
'''
tc = replace_once(tc, needle, insert, "tree-complex: native polar multiply/divide dispatch")



# All transformations succeeded; only now touch the working tree.
store("gcc/builtins.def", builtins)
store("gcc/c/c-typeck.cc", ctype)
store("gcc/varasm.cc", varasm)
store("gcc/tree-complex.cc", tc)

# ---------------------------------------------------------------------------
# Focused tests.
# ---------------------------------------------------------------------------
layout_test = r'''/* { dg-do run } */
/* { dg-options "-O2" } */

#include <complex.h>
#include <math.h>
#include <string.h>

extern void abort (void);

static double _Complex static_z = 3.0 + 4.0i;

static int
close_enough (double a, double b)
{
  double d = a - b;
  return d < 1e-12 && d > -1e-12;
}

__attribute__ ((noinline))
static double _Complex
bounce (double _Complex z)
{
  return z;
}

int
main (void)
{
  double raw[2];
  memcpy (raw, &static_z, sizeof raw);
  if (!close_enough (raw[0], 5.0)
      || !close_enough (raw[1], atan2 (4.0, 3.0)))
    abort ();

  /* Language-level Cartesian access is reconstructed from polar storage.  */
  if (!close_enough (__real__ static_z, 3.0)
      || !close_enough (__imag__ static_z, 4.0))
    abort ();

  double _Complex automatic_z = 3.0 + 4.0i;
  double automatic_raw[2];
  memcpy (automatic_raw, &automatic_z, sizeof automatic_raw);
  if (!close_enough (automatic_raw[0], 5.0)
      || !close_enough (automatic_raw[1], raw[1]))
    abort ();

  /* ICK-to-ICK function arguments and returns carry the same polar pair.  */
  double _Complex returned_z = bounce (automatic_z);
  double returned_raw[2];
  memcpy (returned_raw, &returned_z, sizeof returned_raw);
  if (returned_raw[0] != automatic_raw[0]
      || returned_raw[1] != automatic_raw[1])
    abort ();

  double _Complex constant_returned = bounce (3.0 + 4.0i);
  double constant_returned_raw[2];
  memcpy (constant_returned_raw, &constant_returned,
          sizeof constant_returned_raw);
  if (!close_enough (constant_returned_raw[0], 5.0)
      || !close_enough (constant_returned_raw[1], raw[1]))
    abort ();

  /* Multiplication operates natively on the polar pair.  */
  double _Complex product = (1.0 + 1.0i) * (1.0 + 1.0i);
  double product_raw[2];
  memcpy (product_raw, &product, sizeof product_raw);
  if (!close_enough (product_raw[0], 2.0)
      || !close_enough (__real__ product, 0.0)
      || !close_enough (__imag__ product, 2.0)
      || !close_enough (cabs (product), 2.0)
      || !close_enough (carg (product), atan2 (2.0, 0.0)))
    abort ();

  return 0;
}
'''
round_test = r'''/* { dg-do run } */
/* { dg-options "-O2" } */

#include <math.h>
#include <string.h>

extern void abort (void);

int
main (void)
{
  double _Complex z = 1.0 + 1.0i;
  double _Complex down = floor (z);
  double _Complex up = ceil (z);
  double zr[2], dr[2], ur[2];

  memcpy (zr, &z, sizeof zr);
  memcpy (dr, &down, sizeof dr);
  memcpy (ur, &up, sizeof ur);

  if (dr[0] != 1.0 || ur[0] != 2.0)
    abort ();
  if (dr[1] != zr[1] || ur[1] != zr[1])
    abort ();

  /* Even when radial floor collapses to zero, its stored argument is kept.  */
  double _Complex small = 0.3 + 0.4i;
  double _Complex small_down = floor (small);
  double sr[2], sdr[2];
  memcpy (sr, &small, sizeof sr);
  memcpy (sdr, &small_down, sizeof sdr);
  if (sdr[0] != 0.0 || sdr[1] != sr[1])
    abort ();

  return 0;
}
'''
store("gcc/testsuite/gcc.dg/ick-complex-polar-layout.c", layout_test)
store("gcc/testsuite/gcc.dg/ick-complex-round.c", round_test)

print("Applied ICK polar-complex working-tree edits.")
print("Modified:")
for rel in EXPECTED:
    print(f"  {rel}")
print("Added:")
print("  gcc/testsuite/gcc.dg/ick-complex-polar-layout.c")
print("  gcc/testsuite/gcc.dg/ick-complex-round.c")
print("No git staging, commit, branch update, or push was performed.")
