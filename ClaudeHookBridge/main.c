//
//  main.c
//  island-claude-hook
//
//  Claude Code runs this for every hook event (ClaudeHookInstaller registers it in
//  ~/.claude/settings.json). It forwards the event JSON from stdin to Mac灵动岛 over the
//  Unix socket given as the first argument, prefixed with one JSON line describing where
//  the session runs, so the island can bring its terminal to the front.
//
//  It prints nothing and always exits 0: stdout would be read by Claude Code as hook
//  output, a non-zero exit shows a "hook error" notice, and the island may not be running.
//

#include <errno.h>
#include <libproc.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

enum { kMaxPayload = 16 * 1024 * 1024 };

static void quit(int signal) {
    (void)signal;
    _exit(0);
}

static char *readStdin(size_t *length) {
    size_t capacity = 64 * 1024;
    char *buffer = malloc(capacity);
    *length = 0;
    while (buffer) {
        if (*length == capacity) {
            if (capacity >= kMaxPayload) {
                free(buffer);
                return NULL;
            }
            capacity *= 2;
            char *grown = realloc(buffer, capacity);
            if (!grown) {
                free(buffer);
                return NULL;
            }
            buffer = grown;
        }
        ssize_t count = read(STDIN_FILENO, buffer + *length, capacity - *length);
        if (count == 0) break;
        if (count < 0) {
            if (errno == EINTR) continue;
            break;
        }
        *length += (size_t)count;
    }
    return buffer;
}

static pid_t parentOf(pid_t pid) {
    struct proc_bsdinfo info;
    if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof info) != sizeof info) return 0;
    return (pid_t)info.pbi_ppid;
}

/// The Claude Code process: the first ancestor that isn't a shell wrapping the hook command.
static pid_t agentProcess(void) {
    static const char *shells[] = { "sh", "bash", "zsh", "dash", "fish" };
    pid_t pid = getppid();
    for (int depth = 0; pid > 1 && depth < 4; depth++) {
        char name[2 * MAXCOMLEN + 1] = { 0 };
        proc_name(pid, name, sizeof name);
        int isShell = 0;
        for (size_t i = 0; i < sizeof shells / sizeof *shells; i++) {
            if (strcmp(name, shells[i]) == 0) isShell = 1;
        }
        if (!isShell) return pid;
        pid = parentOf(pid);
    }
    return 0;
}

/// Name of the controlling terminal, e.g. "ttys003" (Terminal and iTerm2 report it per tab).
static const char *controllingTTY(void) {
    struct kinfo_proc info;
    size_t size = sizeof info;
    int mib[] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid() };
    if (sysctl(mib, 4, &info, &size, NULL, 0) != 0 || size == 0) return NULL;
    if (info.kp_eproc.e_tdev == NODEV) return NULL;
    return devname(info.kp_eproc.e_tdev, S_IFCHR);
}

/// Appends `"key":"value"` (JSON-escaped) to the header object being built in `out`.
static void appendString(char *out, size_t size, const char *key, const char *value) {
    if (!value || !*value) return;
    size_t used = strlen(out);
    int written = snprintf(out + used, size - used, "%s\"%s\":\"", used > 1 ? "," : "", key);
    if (written < 0 || (size_t)written >= size - used) return;
    used += (size_t)written;
    for (const char *c = value; *c && used + 8 < size; c++) {
        unsigned char ch = (unsigned char)*c;
        if (ch == '"' || ch == '\\') {
            out[used++] = '\\';
            out[used++] = (char)ch;
        } else if (ch < 0x20) {
            used += (size_t)snprintf(out + used, size - used, "\\u%04x", ch);
        } else {
            out[used++] = (char)ch;
        }
    }
    out[used++] = '"';
    out[used] = '\0';
}

static int writeAll(int fd, const char *bytes, size_t length) {
    while (length > 0) {
        ssize_t written = write(fd, bytes, length);
        if (written < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        bytes += written;
        length -= (size_t)written;
    }
    return 0;
}

int main(int argc, char *argv[]) {
    // Never hold Claude Code up, and never die of a closed socket
    signal(SIGALRM, quit);
    signal(SIGPIPE, SIG_IGN);
    alarm(3);

    size_t length = 0;
    char *payload = readStdin(&length);
    if (argc < 2 || !payload || length == 0) return 0;

    struct sockaddr_un address = { .sun_family = AF_UNIX };
    if (strlen(argv[1]) >= sizeof address.sun_path) return 0;
    strlcpy(address.sun_path, argv[1], sizeof address.sun_path);

    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return 0;
    if (connect(fd, (struct sockaddr *)&address, sizeof address) != 0) return 0; // Island not running

    struct timespec now;
    clock_gettime(CLOCK_REALTIME, &now);
    char header[2048] = "{";
    char number[32];
    snprintf(number, sizeof number, "%.6f", (double)now.tv_sec + (double)now.tv_nsec / 1e9);
    appendString(header, sizeof header, "time", number);
    snprintf(number, sizeof number, "%d", (int)agentProcess());
    appendString(header, sizeof header, "agent_pid", number);
    appendString(header, sizeof header, "tty", controllingTTY());
    appendString(header, sizeof header, "app_bundle_id", getenv("__CFBundleIdentifier"));
    appendString(header, sizeof header, "term_program", getenv("TERM_PROGRAM"));
    appendString(header, sizeof header, "iterm_session_id", getenv("ITERM_SESSION_ID"));
    strlcat(header, "}\n", sizeof header);

    if (writeAll(fd, header, strlen(header)) == 0) {
        writeAll(fd, payload, length);
    }
    close(fd);
    return 0;
}
