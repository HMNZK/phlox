#include "CPTYHelpers.h"

#include <errno.h>
#include <pthread.h>
#include <string.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <util.h>

static pthread_mutex_t cpty_open_mutex = PTHREAD_MUTEX_INITIALIZER;

int cpty_open(int *amaster, int *aslave, const struct pty_winsize *winp) {
    struct winsize ws;
    struct winsize *wsp = NULL;
    if (winp != NULL) {
        ws.ws_row = winp->ws_row;
        ws.ws_col = winp->ws_col;
        ws.ws_xpixel = winp->ws_xpixel;
        ws.ws_ypixel = winp->ws_ypixel;
        wsp = &ws;
    }

    struct termios term;
    memset(&term, 0, sizeof(term));
    cfmakeraw(&term);
    // cfmakeraw は OPOST も無効化するが、それだと PTY 側で LF→CRLF 変換が走らず、
    // `\n` のみで改行する TUI (cursor-agent 等) で行ごとにカーソル列が右にズレて
    // レイアウトが崩れる。WezTerm / Apple Terminal は ONLCR 有効が既定であり、
    // SwiftTerm にも同じ前提のバイトが渡るよう OPOST + ONLCR を再有効化する。
    term.c_oflag |= OPOST | ONLCR;

    int lock_result = pthread_mutex_lock(&cpty_open_mutex);
    if (lock_result != 0) {
        errno = lock_result;
        return -1;
    }

    int result = openpty(amaster, aslave, NULL, &term, wsp);
    int saved_errno = errno;
    pthread_mutex_unlock(&cpty_open_mutex);
    errno = saved_errno;
    return result;
}

int cpty_set_winsize(int fd, unsigned short cols, unsigned short rows) {
    struct winsize ws = {
        .ws_row = rows,
        .ws_col = cols,
        .ws_xpixel = 0,
        .ws_ypixel = 0,
    };
    return ioctl(fd, TIOCSWINSZ, &ws);
}

int cpty_get_winsize(int fd, unsigned short *cols, unsigned short *rows) {
    struct winsize ws;
    if (ioctl(fd, TIOCGWINSZ, &ws) == -1) {
        return -1;
    }
    if (cols) {
        *cols = ws.ws_col;
    }
    if (rows) {
        *rows = ws.ws_row;
    }
    return 0;
}
