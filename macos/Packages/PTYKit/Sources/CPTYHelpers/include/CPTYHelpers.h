#ifndef CPTYHelpers_h
#define CPTYHelpers_h

#include <sys/types.h>

struct pty_winsize {
    unsigned short ws_row;
    unsigned short ws_col;
    unsigned short ws_xpixel;
    unsigned short ws_ypixel;
};

/// Creates a pseudo-terminal pair. Returns 0 on success, -1 on failure (errno set).
int cpty_open(int *amaster, int *aslave, const struct pty_winsize *winp);
int cpty_open_mode(int *amaster, int *aslave, const struct pty_winsize *winp, int raw_mode);

/// Sets the window size on an open PTY master fd via TIOCSWINSZ. Returns 0 on success, -1 on failure (errno set).
int cpty_set_winsize(int fd, unsigned short cols, unsigned short rows);

/// Reads the window size from an open PTY fd via TIOCGWINSZ. Returns 0 on success, -1 on failure (errno set).
/// `cols` and `rows` may be NULL (unused out-parameters).
int cpty_get_winsize(int fd, unsigned short *cols, unsigned short *rows);

/// 制御端末を確立して exec。失敗は errno を設定して -1 を返し、子は回収する。
pid_t cpty_spawn_interactive(const char *command, char *const argv[], char *const envp[],
                             int slave_fd, const char *working_directory);

#endif /* CPTYHelpers_h */
