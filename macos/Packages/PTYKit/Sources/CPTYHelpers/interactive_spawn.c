#include "CPTYHelpers.h"

#include <errno.h>
#include <fcntl.h>
#include <libproc.h>
#include <limits.h>
#include <pthread.h>
#include <signal.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>

static void child_failed(int error_fd) {
    int child_errno = errno;
    ssize_t result;
    do { result = write(error_fd, &child_errno, sizeof(child_errno)); } while (result < 0 && errno == EINTR);
    _exit(127);
}

static int descriptor_upper_bound(void) {
    struct rlimit limit;
    if (getrlimit(RLIMIT_NOFILE, &limit) < 0) return -1;
    int upper = limit.rlim_cur > INT_MAX ? INT_MAX : (int)limit.rlim_cur;
    int capacity = 128 * sizeof(struct proc_fdinfo);
    for (;;) {
        struct proc_fdinfo *descriptors = malloc(capacity);
        if (descriptors == NULL) return -1;
        int bytes = proc_pidinfo(getpid(), PROC_PIDLISTFDS, 0, descriptors, capacity);
        if (bytes <= 0 || bytes % sizeof(descriptors[0]) != 0) {
            int saved = bytes <= 0 ? errno : EIO;
            free(descriptors);
            errno = saved;
            return -1;
        }
        for (size_t index = 0; index < bytes / sizeof(descriptors[0]); index++) {
            int fd = descriptors[index].proc_fd;
            if (fd > upper) upper = fd;
        }
        free(descriptors);
        if (bytes < capacity) return upper;
        if (capacity > INT_MAX / 2) { errno = EOVERFLOW; return -1; }
        capacity *= 2;
    }
}

pid_t cpty_spawn_interactive(const char *command, char *const argv[], char *const envp[],
                             int slave_fd, const char *working_directory) {
    int errors[2];
    if (pipe(errors) < 0) return -1;
    for (int index = 0; index < 2; index++) {
        int moved = fcntl(errors[index], F_DUPFD_CLOEXEC, 3);
        if (moved < 0) {
            int saved = errno;
            close(errors[0]); close(errors[1]); errno = saved;
            return -1;
        }
        close(errors[index]);
        errors[index] = moved;
    }
    sigset_t all, previous, empty;
    sigfillset(&all);
    sigemptyset(&empty);
    struct sigaction action = { .sa_handler = SIG_DFL };
    sigemptyset(&action.sa_mask);
    int mask_error = pthread_sigmask(SIG_SETMASK, &all, &previous);
    if (mask_error != 0) {
        close(errors[0]); close(errors[1]); errno = mask_error;
        return -1;
    }
    int upper = descriptor_upper_bound();
    if (upper < 0) {
        int saved = errno;
        pthread_sigmask(SIG_SETMASK, &previous, NULL);
        close(errors[0]); close(errors[1]); errno = saved;
        return -1;
    }
    // ADR 0201: 列挙後に別スレッドが上限超の fd を作ると漏れうる。
    // Phlox は RLIMIT_NOFILE を下げないため実害は小さい。必要になれば fd 作成を同期する。
    pid_t pid = fork();
    int fork_errno = errno;
    if (pid == 0) {
        // fork 後は Swift・メモリ確保・Foundation を呼ばない。
        close(errors[0]);
        if (setsid() < 0 || ioctl(slave_fd, TIOCSCTTY, 0) < 0) child_failed(errors[1]);
        for (int fd = 0; fd <= STDERR_FILENO; fd++) {
            if (dup2(slave_fd, fd) < 0) child_failed(errors[1]);
        }
        if (working_directory != NULL && chdir(working_directory) < 0) child_failed(errors[1]);
        for (long fd = 3; fd <= upper; fd++) {
            if (fd != errors[1]) close((int)fd);
        }
        for (int signal = 1; signal < NSIG; signal++) {
            if (signal != SIGKILL && signal != SIGSTOP && sigaction(signal, &action, NULL) < 0) child_failed(errors[1]);
        }
        if (sigprocmask(SIG_SETMASK, &empty, NULL) < 0) child_failed(errors[1]);
        execve(command, argv, envp);
        child_failed(errors[1]);
    }
    pthread_sigmask(SIG_SETMASK, &previous, NULL);
    close(errors[1]);
    if (pid < 0) { close(errors[0]); errno = fork_errno; return -1; }
    int child_errno = 0;
    ssize_t count;
    do { count = read(errors[0], &child_errno, sizeof(child_errno)); } while (count < 0 && errno == EINTR);
    int read_errno = errno;
    close(errors[0]);
    if (count == 0) return pid; // exec が成功して error pipe が閉じた。
    if (count < 0) kill(pid, SIGKILL);
    while (waitpid(pid, NULL, 0) < 0 && errno == EINTR) {}
    errno = count == sizeof(child_errno) ? child_errno : (count < 0 ? read_errno : EIO);
    return -1;
}
