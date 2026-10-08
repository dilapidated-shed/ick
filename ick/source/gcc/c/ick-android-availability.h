/* ICK Android declaration metadata checks.  Included only by c-typeck.cc. */
static unsigned
ick_android_api_macro (const char *name, unsigned depth = 0)
{
  if (depth > 8) return 0;
  cpp_hashnode *node = cpp_lookup (parse_in, (const unsigned char *)name, strlen (name));
  if (!node || !cpp_user_macro_p (node)) return 0;
  const unsigned char *definition = cpp_macro_definition (parse_in, node);
  if (!definition) return 0;
  const char *value = (const char *)definition;
  while (*value && !ISSPACE (*value)) ++value;
  while (ISSPACE (*value) || *value == '(') ++value;
  if (ISDIGIT (*value))
    {
      char *end;
      unsigned long level = strtoul (value, &end, 10);
      while (ISSPACE (*end) || *end == ')') ++end;
      return !*end && level > 0 && level <= INT_MAX ? (unsigned)level : 0;
    }
  char alias[128];
  unsigned length = 0;
  while ((ISALNUM (*value) || *value == '_') && length < sizeof (alias) - 1)
    alias[length++] = *value++;
  alias[length] = 0;
  while (ISSPACE (*value) || *value == ')') ++value;
  return length && !*value ? ick_android_api_macro (alias, depth + 1) : 0;
}

static tree
ick_availability_arguments (tree declaration)
{
  if (!declaration || !DECL_P (declaration)) return NULL_TREE;
  tree attribute = lookup_attribute ("availability", DECL_ATTRIBUTES (declaration));
  if (!attribute && TREE_TYPE (declaration))
    attribute = lookup_attribute ("availability", TYPE_ATTRIBUTES (TREE_TYPE (declaration)));
  return attribute ? TREE_VALUE (attribute) : NULL_TREE;
}
static unsigned
ick_availability_version (tree arguments, const char *name)
{
  if (!arguments) return 0;
  for (tree field = TREE_CHAIN (arguments); field; field = TREE_CHAIN (field))
    if (strcmp (IDENTIFIER_POINTER (TREE_PURPOSE (field)), name) == 0
        && TREE_CODE (TREE_VALUE (field)) == INTEGER_CST
        && tree_fits_uhwi_p (TREE_VALUE (field)))
      return tree_to_uhwi (TREE_VALUE (field));
  return 0;
}
static void
ick_check_android_availability (location_t location, tree declaration)
{
  tree arguments = ick_availability_arguments (declaration);
  if (!arguments) return;
  unsigned minimum = ick_android_api_macro ("__ANDROID_API__");
  if (!minimum) minimum = ick_android_api_macro ("__ANDROID_MIN_SDK_VERSION__");
  if (!minimum)
    {
      error_at (location, "Android API use requires an explicit numeric minimum API");
      return;
    }
  unsigned introduced = ick_availability_version (arguments, "introduced");
  unsigned obsolete = ick_availability_version (arguments, "obsoleted");
  unsigned enclosing = ick_availability_version
    (ick_availability_arguments (current_function_decl), "introduced");
  if (ick_availability_version (arguments, "unavailable")
      || (obsolete && minimum >= obsolete))
    error_at (location, "%qD is unavailable at Android API %u", declaration, minimum);
  else if (introduced > minimum && introduced > enclosing)
    error_at (location, "%qD requires Android API %u (minimum is %u)",
              declaration, introduced, minimum);
  unsigned deprecated = ick_availability_version (arguments, "deprecated");
  if (deprecated && minimum >= deprecated)
    warning_at (location, OPT_Wdeprecated_declarations, "%qD is deprecated at Android API %u",
                declaration, deprecated);
}
