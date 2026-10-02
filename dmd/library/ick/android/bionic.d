module ick.android.bionic;

/**
 * Small Android/Bionic ABI surface required by the Shizuku Rish translation.
 *
 * These declarations target the Android API-21+ libc ABI used by current Rish.
 * Keep policy and process logic in consumers; this module only names C ABI
 * types, constants and functions.
 */

alias pid_t = int;
alias ssize_t = ptrdiff_t;
alias pthread_t = ptrdiff_t;
alias sigset_t = size_t;

enum int STDIN_FILENO = 0;
enum int STDOUT_FILENO = 1;
enum int STDERR_FILENO = 2;

enum int F_OK = 0;
enum int X_OK = 1;
enum int W_OK = 2;
enum int R_OK = 4;

enum int O_RDWR = 2;

enum int EINTR = 4;
enum int ECHILD = 10;

enum int SIGKILL = 9;
enum int SIGWINCH = 28;
enum int SIG_BLOCK = 0;

enum int TCSANOW = 0;
enum int TIOCGWINSZ = 0x5413;
enum int TIOCSWINSZ = 0x5414;

enum size_t PATH_MAX = 4096;
enum size_t NCCS = 19;

extern(C) struct BionicTermios {
    uint c_iflag;
    uint c_oflag;
    uint c_cflag;
    uint c_lflag;
    ubyte c_line;
    ubyte[NCCS] c_cc;
}

extern(C) struct BionicWinSize {
    ushort ws_row;
    ushort ws_col;
    ushort ws_xpixel;
    ushort ws_ypixel;
}

extern(C) struct BionicPthreadMutex {
    version (D_LP64) {
        int[10] private_;
    } else {
        int[1] private_;
    }
}

static assert(BionicWinSize.sizeof == 8);
static if (size_t.sizeof == 4) {
    static assert(BionicTermios.sizeof == 36);
    static assert(BionicPthreadMutex.sizeof == 4);
} else {
    static assert(BionicPthreadMutex.sizeof == 40);
}

alias BionicThreadStart =
    extern(C) void* function(void* arg) nothrow @nogc;
alias BionicSignalHandler =
    extern(C) void function(int signal_number) nothrow @nogc;

extern(C) nothrow @nogc:

int* __errno();

void* malloc(size_t size);
void free(void* pointer);
void exit(int status);

ssize_t read(int fd, void* buffer, size_t count);
ssize_t write(int fd, const(void)* buffer, size_t count);
int close(int fd);
int pipe2(int* pipe_fds, int flags);
int open(const(char)* path, int flags, ...);

uint getuid();
pid_t fork();
pid_t setsid();
int access(const(char)* path, int mode);
int chdir(const(char)* path);
int dup2(int old_fd, int new_fd);

int execvp(const(char)* file, char** argv);
int execvpe(const(char)* file, char** argv, char** envp);
void _exit(int status);

int isatty(int fd);
int grantpt(int fd);
int unlockpt(int fd);
int ptsname_r(int fd, char* buffer, size_t length);

int kill(pid_t pid, int signal_number);
pid_t waitpid(pid_t pid, int* status, int options);

int ioctl(int fd, int operation, ...);

int tcgetattr(int fd, BionicTermios* termios);
int tcsetattr(int fd, int optional_actions, const(BionicTermios)* termios);
void cfmakeraw(BionicTermios* termios);

int pthread_create(
    pthread_t* thread,
    const(void)* attributes,
    BionicThreadStart start,
    void* argument
);
int pthread_detach(pthread_t thread);
int pthread_mutex_init(BionicPthreadMutex* mutex, const(void)* attributes);
int pthread_mutex_lock(BionicPthreadMutex* mutex);
int pthread_mutex_unlock(BionicPthreadMutex* mutex);
int pthread_mutex_destroy(BionicPthreadMutex* mutex);
int pthread_sigmask(int how, const(sigset_t)* set, sigset_t* old_set);

int sigemptyset(sigset_t* set);
int sigaddset(sigset_t* set, int signal_number);
BionicSignalHandler signal(int signal_number, BionicSignalHandler handler);

nothrow @nogc int bionic_errno()
{
    auto p = __errno();
    return p is null ? 0 : *p;
}

/* Linux wait-status macros used by RishHost.waitFor. */
pure nothrow @nogc bool wifexited(int status)
{
    return (status & 0x7f) == 0;
}

pure nothrow @nogc int wexitstatus(int status)
{
    return (status >> 8) & 0xff;
}

pure nothrow @nogc bool wifsignaled(int status)
{
    const int signal_number = status & 0x7f;
    return signal_number != 0 && signal_number != 0x7f;
}

pure nothrow @nogc int wtermsig(int status)
{
    return status & 0x7f;
}
