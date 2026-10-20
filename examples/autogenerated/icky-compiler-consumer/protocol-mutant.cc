/* Deliberately hostile foreign executables for compiler refusal tests.
   Replay real ICKY output with one corruption; do not parse source syntax. */
#include <cstdio>
#include <cstdlib>
#include <string>
static std::string read (const std::string &path)
{
  FILE *file = fopen (path.c_str (), "rb");
  if (!file) exit (2);
  std::string bytes; char buffer[4096]; size_t amount;
  while ((amount = fread (buffer, 1, sizeof buffer, file))) bytes.append (buffer, amount);
  if (ferror (file) || fclose (file)) exit (2);
  return bytes;
}
int main (int argc, char **argv)
{
  if (argc != 3 || std::string (argv[1]) != "--parse-v3" || read (argv[2]) != "010") return 2;
  std::string executable = argv[0];
  size_t slash = executable.rfind ('/');
  if (slash == std::string::npos) return 2;
  std::string root = executable.substr (0, slash), mode = executable.substr (slash + 1);
  std::string output = read (root + "/golden.tsv");
  if (mode == "truncated") output.resize (output.size () - 1);
  else if (mode == "frame")
    {
      size_t at = output.find ("303130");
      if (at == std::string::npos) return 2;
      output.replace (at, 6, "313030");
    }
  else if (mode == "span")
    {
      size_t at = output.find ("natural\t0.0\t0\t1\t1\t3\t1\t4\t0\t3");
      if (at == std::string::npos) return 2;
      output.replace (at, std::string ("natural\t0.0\t0\t1\t1\t3\t1\t4\t0\t3").size (),
                      "natural\t0.0\t0\t1\t2\t3\t1\t4\t0\t3");
    }
  else if (mode == "changed-map")
    {
      FILE *raw = fopen ((root + "/../mutable.c").c_str (), "ab");
      if (!raw || fputs ("\n/* changed after CPP map capture */\n", raw) < 0 || fclose (raw)) return 2;
    }
  else return 2;
  return fwrite (output.data (), 1, output.size (), stdout) == output.size () ? 0 : 2;
}
