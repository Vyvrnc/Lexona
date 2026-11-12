#define _GNU_SOURCE
#include <dlfcn.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <stdio.h>
#include <pthread.h>
#include <stdlib.h>
#include <stddef.h>
#include <stdarg.h>
#include <errno.h>
#include <dirent.h>
#include <android/log.h>
#include <spawn.h>
#include <stdint.h>
#include <limits.h>
#include <sys/prctl.h>
#include <sys/syscall.h>

#ifndef NEW_PREFIX
#define NEW_PREFIX "/data/user/0/io.github.vyvrnc.lexona/files/usr"
#endif

/*
 * The prefix this copy of the hook serves, taken from its own path at load time
 * (<prefix>/lib/libsocket_hook.so). The prebuilt binary then also works when the app
 * runs as another Android user (/data/user/10/... on Android Automotive, ScreenMate
 * One). NEW_PREFIX stays the fallback and what an on-device build bakes in.
 */
static char hook_prefix[512] = NEW_PREFIX;

__attribute__((constructor)) static void init_hook_prefix(void) {
    Dl_info info;
    static const char suffix[] = "/lib/libsocket_hook.so";
    if (!dladdr((void *) init_hook_prefix, &info) || !info.dli_fname) return;
    size_t len = strlen(info.dli_fname), suffix_len = sizeof(suffix) - 1;
    if (len <= suffix_len || len - suffix_len >= sizeof(hook_prefix)) return;
    if (strcmp(info.dli_fname + len - suffix_len, suffix) != 0) return;
    memcpy(hook_prefix, info.dli_fname, len - suffix_len);
    hook_prefix[len - suffix_len] = 0;
}

static const char *TERMUX_PREFIX = "/data/data/com.termux/files/usr";
static const char *REL_TERMUX_PREFIX = "data/data/com.termux/files/usr";
static const char *REL_TERMUX_BASE = "data/data/com.termux";

/* Path-based libc wrappers we need to redirect. */
static int (*real_connect)(int, const struct sockaddr *, socklen_t) = NULL;
static int (*real_bind)(int, const struct sockaddr *, socklen_t) = NULL;
static int (*real_open)(const char *, int, ...) = NULL;
static int (*real_open64)(const char *, int, ...) = NULL;
static int (*real_openat)(int, const char *, int, ...) = NULL;
static int (*real_openat64)(int, const char *, int, ...) = NULL;
static FILE *(*real_fopen)(const char *, const char *) = NULL;
static FILE *(*real_fopen64)(const char *, const char *) = NULL;
static int (*real_stat)(const char *, struct stat *) = NULL;
static int (*real_stat64)(const char *, struct stat64 *) = NULL;
static int (*real_lstat)(const char *, struct stat *) = NULL;
static int (*real_lstat64)(const char *, struct stat64 *) = NULL;
static int (*real_fstatat)(int, const char *, struct stat *, int) = NULL;
static int (*real_fstatat64)(int, const char *, struct stat64 *, int) = NULL;
static int (*real_access)(const char *, int) = NULL;
static int (*real_faccessat)(int, const char *, int, int) = NULL;
static int (*real_mkdir)(const char *, mode_t) = NULL;
static int (*real_mkdirat)(int, const char *, mode_t) = NULL;
static int (*real_chmod)(const char *, mode_t) = NULL;
static int (*real_fchmodat)(int, const char *, mode_t, int) = NULL;
static int (*real_chown)(const char *, uid_t, gid_t) = NULL;
static int (*real_lchown)(const char *, uid_t, gid_t) = NULL;
static int (*real_fchownat)(int, const char *, uid_t, gid_t, int) = NULL;
static int (*real_unlink)(const char *) = NULL;
static int (*real_unlinkat)(int, const char *, int) = NULL;
static int (*real_rmdir)(const char *) = NULL;
static int (*real_rename)(const char *, const char *) = NULL;
static int (*real_renameat)(int, const char *, int, const char *) = NULL;
static ssize_t (*real_readlink)(const char *, char *, size_t) = NULL;
static ssize_t (*real_readlinkat)(int, const char *, char *, size_t) = NULL;
static int (*real_symlink)(const char *, const char *) = NULL;
static int (*real_symlinkat)(const char *, int, const char *) = NULL;
static int (*real_link)(const char *, const char *) = NULL;
static int (*real_linkat)(int, const char *, int, const char *, int) = NULL;
static int (*real_utimensat)(int, const char *, const struct timespec [2], int) = NULL;
static int (*real_utimes)(const char *, const struct timeval [2]) = NULL;
static int (*real_lutimes)(const char *, const struct timeval [2]) = NULL;
static int (*real_mknod)(const char *, mode_t, dev_t) = NULL;
static int (*real_mknodat)(int, const char *, mode_t, dev_t) = NULL;
static int (*real_mkfifo)(const char *, mode_t) = NULL;
static int (*real_mkfifoat)(int, const char *, mode_t) = NULL;
static void *(*real_dlopen)(const char *, int) = NULL;
static DIR *(*real_opendir)(const char *) = NULL;

static volatile int hook_initialized = 0;
static volatile int hook_initializing = 0;

static void do_init() {
    if (hook_initialized) return;
    if (__sync_lock_test_and_set(&hook_initializing, 1)) {
        int spins = 10000;
        while (!hook_initialized && spins-- > 0) {}
        return;
    }
    real_connect = dlsym(RTLD_NEXT, "connect");
    real_bind = dlsym(RTLD_NEXT, "bind");
    real_open = dlsym(RTLD_NEXT, "open");
    real_open64 = dlsym(RTLD_NEXT, "open64");
    real_openat = dlsym(RTLD_NEXT, "openat");
    real_openat64 = dlsym(RTLD_NEXT, "openat64");
    real_fopen = dlsym(RTLD_NEXT, "fopen");
    real_fopen64 = dlsym(RTLD_NEXT, "fopen64");
    real_stat = dlsym(RTLD_NEXT, "stat");
    real_stat64 = dlsym(RTLD_NEXT, "stat64");
    real_lstat = dlsym(RTLD_NEXT, "lstat");
    real_lstat64 = dlsym(RTLD_NEXT, "lstat64");
    real_fstatat = dlsym(RTLD_NEXT, "fstatat");
    real_fstatat64 = dlsym(RTLD_NEXT, "fstatat64");
    real_access = dlsym(RTLD_NEXT, "access");
    real_faccessat = dlsym(RTLD_NEXT, "faccessat");
    real_mkdir = dlsym(RTLD_NEXT, "mkdir");
    real_mkdirat = dlsym(RTLD_NEXT, "mkdirat");
    real_chmod = dlsym(RTLD_NEXT, "chmod");
    real_fchmodat = dlsym(RTLD_NEXT, "fchmodat");
    real_chown = dlsym(RTLD_NEXT, "chown");
    real_lchown = dlsym(RTLD_NEXT, "lchown");
    real_fchownat = dlsym(RTLD_NEXT, "fchownat");
    real_unlink = dlsym(RTLD_NEXT, "unlink");
    real_unlinkat = dlsym(RTLD_NEXT, "unlinkat");
    real_rmdir = dlsym(RTLD_NEXT, "rmdir");
    real_rename = dlsym(RTLD_NEXT, "rename");
    real_renameat = dlsym(RTLD_NEXT, "renameat");
    real_readlink = dlsym(RTLD_NEXT, "readlink");
    real_readlinkat = dlsym(RTLD_NEXT, "readlinkat");
    real_symlink = dlsym(RTLD_NEXT, "symlink");
    real_symlinkat = dlsym(RTLD_NEXT, "symlinkat");
    real_link = dlsym(RTLD_NEXT, "link");
    real_linkat = dlsym(RTLD_NEXT, "linkat");
    real_utimensat = dlsym(RTLD_NEXT, "utimensat");
    real_utimes = dlsym(RTLD_NEXT, "utimes");
    real_lutimes = dlsym(RTLD_NEXT, "lutimes");
    real_mknod = dlsym(RTLD_NEXT, "mknod");
    real_mknodat = dlsym(RTLD_NEXT, "mknodat");
    real_mkfifo = dlsym(RTLD_NEXT, "mkfifo");
    real_mkfifoat = dlsym(RTLD_NEXT, "mkfifoat");
    real_dlopen = dlsym(RTLD_NEXT, "dlopen");
    real_opendir = dlsym(RTLD_NEXT, "opendir");
    __sync_synchronize();
    hook_initialized = 1;
    __sync_lock_release(&hook_initializing);
}

__attribute__((constructor))
static void init_hook() {
    do_init();
}

static void setup() {
    if (!hook_initialized) do_init();
}

static const char* strip_dot_slash(const char *path) {
    if (path && path[0] == '.' && path[1] == '/') {
        return path + 2;
    }
    return path;
}

/*
 * "/data/data/com.termux/files/<x>" other than files/usr: the same <x> next to our
 * prefix (files/home, files/apps …). It used to become the prefix itself, so Termux's
 * profile sourcing /data/data/com.termux/files/home/.bashrc read a directory
 * ("-bash: .: …/.bashrc: is a directory" in the app terminal's login shell).
 * Returns NULL when hook_prefix does not end in /usr.
 */
static const char* rewrite_files_path(const char *rest, char *buf, size_t buf_size) {
    size_t prefix_len = strlen(hook_prefix);
    if (prefix_len < 4 || strcmp(hook_prefix + prefix_len - 4, "/usr") != 0) return NULL;
    snprintf(buf, buf_size, "%.*s/%s", (int) (prefix_len - 4), hook_prefix, rest);
    return buf;
}

static const char* rewrite_path(const char* path, char* buf, size_t buf_size) {
    if (!path) return path;

    const char *p = strip_dot_slash(path);

    size_t rel_len = strlen(REL_TERMUX_PREFIX);
    if (strncmp(p, REL_TERMUX_PREFIX, rel_len) == 0) {
        char next = p[rel_len];
        if (next == '/' || next == '\0') {
            snprintf(buf, buf_size, "%s%s", hook_prefix, p + rel_len);
            return buf;
        }
    }

    size_t base_len = strlen(REL_TERMUX_BASE);
    if (strncmp(p, REL_TERMUX_BASE, base_len) == 0) {
        char next = p[base_len];
        if (strncmp(p + base_len, "/files/", 7) == 0 && rewrite_files_path(p + base_len + 7, buf, buf_size))
            return buf;
        if (next == '/' || next == '\0') {
            snprintf(buf, buf_size, "%s", hook_prefix);
            return buf;
        }
    }

    size_t term_len = strlen(TERMUX_PREFIX);
    if (strncmp(path, TERMUX_PREFIX, term_len) == 0) {
        snprintf(buf, buf_size, "%s%s", hook_prefix, path + term_len);
        return buf;
    }

    size_t abs_base_len = strlen("/data/data/com.termux");
    if (strncmp(path, "/data/data/com.termux", abs_base_len) == 0) {
        char next = path[abs_base_len];
        if (strncmp(path + abs_base_len, "/files/", 7) == 0 &&
            rewrite_files_path(path + abs_base_len + 7, buf, buf_size))
            return buf;
        if (next == '/' || next == '\0') {
            snprintf(buf, buf_size, "%s", hook_prefix);
            return buf;
        }
    }

    const char *tmpdir = getenv("TMPDIR");
    const char *fhs_prefixes[] = {"/usr/", "/bin/", "/lib/", "/etc/", "/var/", "/tmp/"};
    const char *subdirs[] = {"usr", "bin", "lib", "etc", "var", "tmp"};
    for (int i = 0; i < 6; i++) {
        size_t len = strlen(fhs_prefixes[i]);
        if (strncmp(path, fhs_prefixes[i], len) == 0) {
            if (i == 5 && tmpdir) {
                snprintf(buf, buf_size, "%s/%s", tmpdir, path + len);
            } else {
                snprintf(buf, buf_size, "%s/%s%s", hook_prefix, subdirs[i], path + len);
            }
            return buf;
        }
    }

    return path;
}

/* Helper: rewrite a path if dirfd refers to the current working directory. */
static const char* rewrite_at_path(int dirfd, const char* path, char* buf, size_t buf_size) {
    if (dirfd == AT_FDCWD) {
        return rewrite_path(path, buf, buf_size);
    }
    return path;
}

/*
 * Rewrites a Unix socket address the same way file paths are rewritten, so that
 * bind() and connect() of one program agree (e.g. LibreOffice's OSL_PIPE single-
 * instance socket). sun_path holds at most 107 bytes and our prefix is longer
 * than Termux's, so a rewritten path that no longer fits moves to the abstract
 * namespace under its original name; that is deterministic for both sides and
 * leaves no stale socket file behind. Returns 0 when the address is unchanged.
 */
static socklen_t rewrite_unix_addr(const struct sockaddr *addr, socklen_t addrlen, struct sockaddr_un *un) {
    if (!addr || addr->sa_family != AF_UNIX || addrlen <= offsetof(struct sockaddr_un, sun_path)) return 0;
    memset(un, 0, sizeof(*un));
    memcpy(un, addr, addrlen > sizeof(*un) ? sizeof(*un) : addrlen);
    un->sun_path[sizeof(un->sun_path) - 1] = '\0';
    if (un->sun_path[0] == '\0') return 0; /* already abstract */

    char original[sizeof(un->sun_path)];
    strcpy(original, un->sun_path);
    char buf[1024];
    const char *new_path = NULL;

    /* The X server listens in $TMPDIR, not in $PREFIX/tmp. */
    const char *termux_x11 = "/data/data/com.termux/files/usr/tmp/.X11-unix/X0";
    const char *tmp_x11 = "/tmp/.X11-unix/X0";
    if (strcmp(original, termux_x11) == 0 || strcmp(original, tmp_x11) == 0) {
        const char *tmpdir = getenv("TMPDIR");
        if (tmpdir) snprintf(buf, sizeof(buf), "%s/.X11-unix/X0", tmpdir);
        else snprintf(buf, sizeof(buf), "%s/tmp/.X11-unix/X0", hook_prefix);
        new_path = buf;
    } else {
        new_path = rewrite_path(original, buf, sizeof(buf));
        if (new_path == original) return 0;
    }

    if (strlen(new_path) < sizeof(un->sun_path)) {
        memset(un->sun_path, 0, sizeof(un->sun_path));
        strcpy(un->sun_path, new_path);
        return offsetof(struct sockaddr_un, sun_path) + strlen(new_path) + 1;
    }
    memset(un->sun_path, 0, sizeof(un->sun_path));
    memcpy(un->sun_path + 1, original, strlen(original));
    return offsetof(struct sockaddr_un, sun_path) + 1 + strlen(original);
}

int connect(int sockfd, const struct sockaddr *addr, socklen_t addrlen) {
    setup();
    struct sockaddr_un un;
    socklen_t len = rewrite_unix_addr(addr, addrlen, &un);
    if (len) return real_connect(sockfd, (struct sockaddr *)&un, len);
    return real_connect(sockfd, addr, addrlen);
}

int bind(int sockfd, const struct sockaddr *addr, socklen_t addrlen) {
    setup();
    struct sockaddr_un un;
    socklen_t len = rewrite_unix_addr(addr, addrlen, &un);
    if (len) return real_bind(sockfd, (struct sockaddr *)&un, len);
    return real_bind(sockfd, addr, addrlen);
}

int open(const char *pathname, int flags, ...) {
    setup();
    char buf[1024];
    pathname = rewrite_path(pathname, buf, sizeof(buf));
    if (flags & O_CREAT) {
        va_list args;
        va_start(args, flags);
        mode_t mode = va_arg(args, int);
        va_end(args);
        return real_open(pathname, flags, mode);
    }
    return real_open(pathname, flags);
}

int openat(int dirfd, const char *pathname, int flags, ...) {
    setup();
    char buf[1024];
    pathname = rewrite_at_path(dirfd, pathname, buf, sizeof(buf));
    if (flags & O_CREAT) {
        va_list args;
        va_start(args, flags);
        mode_t mode = va_arg(args, int);
        va_end(args);
        return real_openat(dirfd, pathname, flags, mode);
    }
    return real_openat(dirfd, pathname, flags);
}

FILE *fopen(const char *pathname, const char *mode) {
    setup();
    char buf[1024];
    return real_fopen(rewrite_path(pathname, buf, sizeof(buf)), mode);
}

int stat(const char *pathname, struct stat *statbuf) {
    setup();
    char buf[1024];
    return real_stat(rewrite_path(pathname, buf, sizeof(buf)), statbuf);
}

int lstat(const char *pathname, struct stat *statbuf) {
    setup();
    char buf[1024];
    return real_lstat(rewrite_path(pathname, buf, sizeof(buf)), statbuf);
}

int open64(const char *pathname, int flags, ...) {
    setup();
    char buf[1024];
    pathname = rewrite_path(pathname, buf, sizeof(buf));
    if (flags & O_CREAT) {
        va_list args;
        va_start(args, flags);
        mode_t mode = va_arg(args, int);
        va_end(args);
        if (real_open64) return real_open64(pathname, flags, mode);
        return real_open(pathname, flags, mode);
    }
    if (real_open64) return real_open64(pathname, flags);
    return real_open(pathname, flags);
}

int openat64(int dirfd, const char *pathname, int flags, ...) {
    setup();
    char buf[1024];
    pathname = rewrite_at_path(dirfd, pathname, buf, sizeof(buf));
    if (flags & O_CREAT) {
        va_list args;
        va_start(args, flags);
        mode_t mode = va_arg(args, int);
        va_end(args);
        if (real_openat64) return real_openat64(dirfd, pathname, flags, mode);
        return real_openat(dirfd, pathname, flags, mode);
    }
    if (real_openat64) return real_openat64(dirfd, pathname, flags);
    return real_openat(dirfd, pathname, flags);
}

FILE *fopen64(const char *pathname, const char *mode) {
    setup();
    char buf[1024];
    if (real_fopen64) return real_fopen64(rewrite_path(pathname, buf, sizeof(buf)), mode);
    return real_fopen(rewrite_path(pathname, buf, sizeof(buf)), mode);
}

int stat64(const char *pathname, struct stat64 *statbuf) {
    setup();
    char buf[1024];
    if (real_stat64) return real_stat64(rewrite_path(pathname, buf, sizeof(buf)), statbuf);
    return real_stat(rewrite_path(pathname, buf, sizeof(buf)), (struct stat*)statbuf);
}

int lstat64(const char *pathname, struct stat64 *statbuf) {
    setup();
    char buf[1024];
    if (real_lstat64) return real_lstat64(rewrite_path(pathname, buf, sizeof(buf)), statbuf);
    return real_lstat(rewrite_path(pathname, buf, sizeof(buf)), (struct stat*)statbuf);
}

int fstatat(int dirfd, const char *pathname, struct stat *statbuf, int flags) {
    setup();
    char buf[1024];
    return real_fstatat(dirfd, rewrite_at_path(dirfd, pathname, buf, sizeof(buf)), statbuf, flags);
}

int fstatat64(int dirfd, const char *pathname, struct stat64 *statbuf, int flags) {
    setup();
    char buf[1024];
    if (real_fstatat64) return real_fstatat64(dirfd, rewrite_at_path(dirfd, pathname, buf, sizeof(buf)), statbuf, flags);
    return real_fstatat(dirfd, rewrite_at_path(dirfd, pathname, buf, sizeof(buf)), (struct stat*)statbuf, flags);
}

int access(const char *pathname, int mode) {
    setup();
    char buf[1024];
    return real_access(rewrite_path(pathname, buf, sizeof(buf)), mode);
}

int faccessat(int dirfd, const char *pathname, int mode, int flags) {
    setup();
    char buf[1024];
    return real_faccessat(dirfd, rewrite_at_path(dirfd, pathname, buf, sizeof(buf)), mode, flags);
}

int mkdir(const char *pathname, mode_t mode) {
    setup();
    char buf[1024];
    return real_mkdir(rewrite_path(pathname, buf, sizeof(buf)), mode);
}

int mkdirat(int dirfd, const char *pathname, mode_t mode) {
    setup();
    char buf[1024];
    return real_mkdirat(dirfd, rewrite_at_path(dirfd, pathname, buf, sizeof(buf)), mode);
}

int chmod(const char *pathname, mode_t mode) {
    setup();
    char buf[1024];
    return real_chmod(rewrite_path(pathname, buf, sizeof(buf)), mode);
}

int fchmodat(int dirfd, const char *pathname, mode_t mode, int flags) {
    setup();
    char buf[1024];
    return real_fchmodat(dirfd, rewrite_at_path(dirfd, pathname, buf, sizeof(buf)), mode, flags);
}

int chown(const char *pathname, uid_t owner, gid_t group) {
    setup();
    char buf[1024];
    return real_chown(rewrite_path(pathname, buf, sizeof(buf)), owner, group);
}

int lchown(const char *pathname, uid_t owner, gid_t group) {
    setup();
    char buf[1024];
    return real_lchown(rewrite_path(pathname, buf, sizeof(buf)), owner, group);
}

int fchownat(int dirfd, const char *pathname, uid_t owner, gid_t group, int flags) {
    setup();
    char buf[1024];
    return real_fchownat(dirfd, rewrite_at_path(dirfd, pathname, buf, sizeof(buf)), owner, group, flags);
}

int unlink(const char *pathname) {
    setup();
    char buf[1024];
    return real_unlink(rewrite_path(pathname, buf, sizeof(buf)));
}

int unlinkat(int dirfd, const char *pathname, int flags) {
    setup();
    char buf[1024];
    return real_unlinkat(dirfd, rewrite_at_path(dirfd, pathname, buf, sizeof(buf)), flags);
}

int rmdir(const char *pathname) {
    setup();
    char buf[1024];
    return real_rmdir(rewrite_path(pathname, buf, sizeof(buf)));
}

int rename(const char *oldpath, const char *newpath) {
    setup();
    char oldbuf[1024], newbuf[1024];
    return real_rename(rewrite_path(oldpath, oldbuf, sizeof(oldbuf)),
                       rewrite_path(newpath, newbuf, sizeof(newbuf)));
}

int renameat(int olddirfd, const char *oldpath, int newdirfd, const char *newpath) {
    setup();
    char oldbuf[1024], newbuf[1024];
    const char *rold = (olddirfd == AT_FDCWD) ? rewrite_path(oldpath, oldbuf, sizeof(oldbuf)) : oldpath;
    const char *rnew = (newdirfd == AT_FDCWD) ? rewrite_path(newpath, newbuf, sizeof(newbuf)) : newpath;
    return real_renameat(olddirfd, rold, newdirfd, rnew);
}

static int is_self_exe_link(const char *path);
static ssize_t copy_self_exe(char *buf, size_t bufsiz);
static char self_exe[1024]; /* identity_fix (tentative definition, set there) */

ssize_t readlink(const char *pathname, char *buf, size_t bufsiz) {
    setup();
    if (is_self_exe_link(pathname)) return copy_self_exe(buf, bufsiz);
    char pathbuf[1024];
    return real_readlink(rewrite_path(pathname, pathbuf, sizeof(pathbuf)), buf, bufsiz);
}

ssize_t readlinkat(int dirfd, const char *pathname, char *buf, size_t bufsiz) {
    setup();
    if (pathname && pathname[0] == '/' && is_self_exe_link(pathname)) return copy_self_exe(buf, bufsiz);
    char pathbuf[1024];
    return real_readlinkat(dirfd, rewrite_at_path(dirfd, pathname, pathbuf, sizeof(pathbuf)), buf, bufsiz);
}

/* realpath("/proc/self/exe"): bionic resolves it through the open file, which is linker64. */
char *realpath(const char *path, char *resolved) {
    static char *(*real_realpath)(const char *, char *) = NULL;
    if (!real_realpath) real_realpath = dlsym(RTLD_NEXT, "realpath");
    if (is_self_exe_link(path)) {
        if (resolved) {
            snprintf(resolved, PATH_MAX, "%s", self_exe);
            return resolved;
        }
        return strdup(self_exe);
    }
    return real_realpath ? real_realpath(path, resolved) : NULL;
}

int symlink(const char *target, const char *linkpath) {
    setup();
    char linkbuf[1024];
    char targetbuf[1024];
    const char *new_target = target;
    size_t term_len = strlen(TERMUX_PREFIX);
    if (target && strncmp(target, TERMUX_PREFIX, term_len) == 0) {
        snprintf(targetbuf, sizeof(targetbuf), "%s%s", hook_prefix, target + term_len);
        new_target = targetbuf;
    }
    return real_symlink(new_target, rewrite_path(linkpath, linkbuf, sizeof(linkbuf)));
}

int symlinkat(const char *target, int dirfd, const char *linkpath) {
    setup();
    char linkbuf[1024];
    char targetbuf[1024];
    const char *new_target = target;
    size_t term_len = strlen(TERMUX_PREFIX);
    if (target && strncmp(target, TERMUX_PREFIX, term_len) == 0) {
        snprintf(targetbuf, sizeof(targetbuf), "%s%s", hook_prefix, target + term_len);
        new_target = targetbuf;
    }
    return real_symlinkat(new_target, dirfd, rewrite_at_path(dirfd, linkpath, linkbuf, sizeof(linkbuf)));
}

int link(const char *oldpath, const char *newpath) {
    setup();
    char oldbuf[1024], newbuf[1024];
    return real_link(rewrite_path(oldpath, oldbuf, sizeof(oldbuf)),
                     rewrite_path(newpath, newbuf, sizeof(newbuf)));
}

int linkat(int olddirfd, const char *oldpath, int newdirfd, const char *newpath, int flags) {
    setup();
    char oldbuf[1024], newbuf[1024];
    const char *rold = (olddirfd == AT_FDCWD) ? rewrite_path(oldpath, oldbuf, sizeof(oldbuf)) : oldpath;
    const char *rnew = (newdirfd == AT_FDCWD) ? rewrite_path(newpath, newbuf, sizeof(newbuf)) : newpath;
    return real_linkat(olddirfd, rold, newdirfd, rnew, flags);
}

int utimensat(int dirfd, const char *pathname, const struct timespec times[2], int flags) {
    setup();
    char buf[1024];
    return real_utimensat(dirfd, rewrite_at_path(dirfd, pathname, buf, sizeof(buf)), times, flags);
}

int utimes(const char *pathname, const struct timeval times[2]) {
    setup();
    char buf[1024];
    return real_utimes(rewrite_path(pathname, buf, sizeof(buf)), times);
}

int lutimes(const char *pathname, const struct timeval times[2]) {
    setup();
    char buf[1024];
    return real_lutimes(rewrite_path(pathname, buf, sizeof(buf)), times);
}

int mknod(const char *pathname, mode_t mode, dev_t dev) {
    setup();
    char buf[1024];
    return real_mknod(rewrite_path(pathname, buf, sizeof(buf)), mode, dev);
}

int mknodat(int dirfd, const char *pathname, mode_t mode, dev_t dev) {
    setup();
    char buf[1024];
    return real_mknodat(dirfd, rewrite_at_path(dirfd, pathname, buf, sizeof(buf)), mode, dev);
}

int mkfifo(const char *pathname, mode_t mode) {
    setup();
    char buf[1024];
    return real_mkfifo(rewrite_path(pathname, buf, sizeof(buf)), mode);
}

int mkfifoat(int dirfd, const char *pathname, mode_t mode) {
    setup();
    char buf[1024];
    return real_mkfifoat(dirfd, rewrite_at_path(dirfd, pathname, buf, sizeof(buf)), mode);
}

/*
 * bionic's opendir() calls open() inside libc, past this hook, so directory
 * listings of compiled-in com.termux paths failed while open/stat worked:
 * tumblerd found no thumbnailer plugins (g_dir_open on lib/tumbler-1/plugins).
 */
DIR *opendir(const char *name) {
    setup();
    char buf[1024];
    return real_opendir(rewrite_path(name, buf, sizeof(buf)));
}

/*
 * The log line below reads dlerror(), which clears it, so the caller's own dlerror() got NULL:
 * Chromium copies it into a std::string and crashed in strlen(NULL) on a failed optional
 * library (optimization_guide_internal, Fold 7). The message is kept per thread and handed
 * out once by the dlerror() below, as libdl would.
 *
 * Per thread through a pthread key, not __thread: ELF TLS needs Android 10, and on Android 9
 * (minSdk 28) a preloaded library with a TLS segment crashed every program at start.
 */
struct dl_error_slot {
    int pending;
    char message[512];
};
static pthread_key_t dl_error_key;
static pthread_once_t dl_error_once = PTHREAD_ONCE_INIT;
static char *(*real_dlerror)(void) = NULL;

static void dl_error_key_init(void) {
    pthread_key_create(&dl_error_key, free);
}

static struct dl_error_slot *dl_error_slot(int create) {
    pthread_once(&dl_error_once, dl_error_key_init);
    struct dl_error_slot *slot = pthread_getspecific(dl_error_key);
    if (!slot && create) {
        slot = calloc(1, sizeof(*slot));
        if (slot) pthread_setspecific(dl_error_key, slot);
    }
    return slot;
}

void *dlopen(const char *filename, int flag) {
    setup();
    char buf[1024];
    const char *new_path = rewrite_path(filename, buf, sizeof(buf));
    void *ret = real_dlopen(new_path, flag);
    if (!real_dlerror) real_dlerror = dlsym(RTLD_NEXT, "dlerror");
    if (!ret) {
        const char *error = real_dlerror ? real_dlerror() : NULL;
        struct dl_error_slot *slot = dl_error_slot(1);
        if (slot) {
            snprintf(slot->message, sizeof(slot->message), "%s", error ? error : "dlopen failed");
            slot->pending = 1;
        }
        __android_log_print(ANDROID_LOG_ERROR, "LorieNative Hook", "dlopen failed for %s -> %s: %s",
                            filename, new_path, slot ? slot->message : (error ? error : "?"));
    } else {
        struct dl_error_slot *slot = dl_error_slot(0);
        if (slot) slot->pending = 0;
    }
    return ret;
}

char *dlerror(void) {
    if (!real_dlerror) real_dlerror = dlsym(RTLD_NEXT, "dlerror");
    struct dl_error_slot *slot = dl_error_slot(0);
    /* An error libdl recorded after the saved one (a failed dlsym) is the newer one. */
    char *newer = real_dlerror ? real_dlerror() : NULL;
    if (newer) {
        if (slot) slot->pending = 0;
        return newer;
    }
    if (slot && slot->pending) {
        slot->pending = 0;
        return slot->message;
    }
    return NULL;
}

/*
 * Program paths compiled into Termux packages (bash.bashrc's command-not-found
 * handler, scripts calling $PREFIX/bin/... absolutely) point at com.termux,
 * which does not exist here. stat/access above already redirect, so "-x" tests
 * pass and the exec itself then fails with ENOENT. Only com.termux paths are
 * rewritten: they cannot work unmodified, while FHS paths such as /bin/sh
 * resolve through Android's own symlinks and keep their current behaviour.
 */
static const char* rewrite_exec_path(const char* path, char* buf, size_t buf_size) {
    if (path && strncmp(path, "/data/data/com.termux/", strlen("/data/data/com.termux/")) == 0) {
        return rewrite_path(path, buf, buf_size);
    }
    return path;
}

static int (*real_execve)(const char *, char *const [], char *const []) = NULL;

static int exec_planned(const char *path, char *const argv[], char *const envp[]);
static int (*real_execvp)(const char *, char *const []) = NULL;
static int (*real_execvpe)(const char *, char *const [], char *const []) = NULL;

extern char **environ;

/*
 * A script whose "#!" line names Termux's prefix cannot be started by the
 * kernel: the interpreter path does not exist here. dpkg runs maintainer
 * scripts (postinst …) right after unpacking them, before the wrapper's
 * shebang relocation pass, so the first configure of such packages failed
 * (cups, openjdk, dbus, python … on a fresh install). Such a script is
 * started through the relocated interpreter instead, as the kernel would:
 * interpreter [optional argument] script args…. Returns -1 with errno
 * untouched when the file is not such a script.
 */
static int exec_termux_script(const char *path, char *const argv[], char *const envp[]) {
    if (!path || !real_execve) return -1;
    setup();
    int fd = real_open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return -1;
    char head[256];
    ssize_t n = read(fd, head, sizeof(head) - 1);
    close(fd);
    if (n < 4 || head[0] != '#' || head[1] != '!') return -1;
    head[n] = '\0';
    char *line_end = strchr(head, '\n');
    if (!line_end) return -1;
    *line_end = '\0';
    char *interp = head + 2;
    while (*interp == ' ' || *interp == '\t') interp++;
    if (strncmp(interp, TERMUX_PREFIX, strlen(TERMUX_PREFIX)) != 0) return -1;
    char *arg = interp;
    while (*arg && *arg != ' ' && *arg != '\t') arg++;
    if (*arg) {
        *arg++ = '\0';
        while (*arg == ' ' || *arg == '\t') arg++;
        char *end = arg + strlen(arg);
        while (end > arg && (end[-1] == ' ' || end[-1] == '\t' || end[-1] == '\r')) *--end = '\0';
    }
    char interp_buf[1024];
    const char *new_interp = rewrite_path(interp, interp_buf, sizeof(interp_buf));
    int argc = 0;
    while (argv && argv[argc]) argc++;
    char **new_argv = calloc((size_t) argc + 4, sizeof(char *));
    if (!new_argv) return -1;
    int i = 0;
    new_argv[i++] = (char *) new_interp;
    if (*arg) new_argv[i++] = arg;
    new_argv[i++] = (char *) path;
    for (int k = 1; k < argc; k++) new_argv[i++] = argv[k];
    new_argv[i] = NULL;
    int ret = exec_planned(new_interp, new_argv, envp);
    int saved = errno;
    free(new_argv);
    errno = saved;
    return ret;
}

/*
 * dpkg maintainer scripts also name Termux's prefix in their body (openssh:
 * mkdir -p "/data/data/com.termux/files/usr/var/empty"; mariadb). Absolute
 * calls are redirected, but GNU mkdir -p walks the path component by component
 * with relative names ("com.termux" inside /data/data), which the hook cannot
 * map: "cannot create directory '/data/data/com.termux': Permission denied".
 * Such a script runs from a copy with the prefix replaced, through the
 * relocated interpreter. Only maintainer scripts (…/var/lib/dpkg/info/…),
 * so ordinary scripts keep their $0. Returns -1 when not applicable.
 *
 * The copy is a regular file in $TMPDIR (droiddesk-maintscript-*, removed at
 * the next session start): an in-memory copy run as /proc/self/fd/N was
 * refused on Android 16 ("cannot open /proc/self/fd/8: Permission denied").
 */
#define MAX_RELOCATED_SCRIPT (1024 * 1024)
static int exec_relocated_maintainer_script(const char *path, char *const argv[], char *const envp[]) {
    if (!path || !strstr(path, "/var/lib/dpkg/info/") || !real_execve) return -1;
    setup();
    int fd = real_open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return -1;
    char *text = malloc(MAX_RELOCATED_SCRIPT + 1);
    if (!text) { close(fd); return -1; }
    size_t len = 0;
    ssize_t n;
    while (len < MAX_RELOCATED_SCRIPT && (n = read(fd, text + len, MAX_RELOCATED_SCRIPT - len)) > 0) len += (size_t) n;
    close(fd);
    text[len] = '\0';
    if (len < 4 || len >= MAX_RELOCATED_SCRIPT || text[0] != '#' || text[1] != '!' ||
        memchr(text, '\0', len) || !strstr(text, TERMUX_PREFIX)) {
        free(text);
        return -1;
    }
    char script_path[1024];
    const char *tmpdir = getenv("TMPDIR");
    if (tmpdir && *tmpdir) snprintf(script_path, sizeof(script_path), "%s/droiddesk-maintscript-XXXXXX", tmpdir);
    else snprintf(script_path, sizeof(script_path), "%s/../tmp/droiddesk-maintscript-XXXXXX", hook_prefix);
    int mem = mkstemp(script_path);
    if (mem < 0) { free(text); return -1; }
    fchmod(mem, 0700);
    size_t old_len = strlen(TERMUX_PREFIX), new_len = strlen(hook_prefix);
    const char *at = text;
    const char *hit;
    int ok = 1;
    while (ok && (hit = strstr(at, TERMUX_PREFIX)) != NULL) {
        ok = write(mem, at, (size_t) (hit - at)) == hit - at && write(mem, hook_prefix, new_len) == (ssize_t) new_len;
        at = hit + old_len;
    }
    if (ok) ok = write(mem, at, strlen(at)) == (ssize_t) strlen(at);
    /* The interpreter of the relocated copy. */
    char *line_end = strchr(text, '\n');
    close(mem);
    if (!ok || !line_end) { unlink(script_path); free(text); return -1; }
    *line_end = '\0';
    char *interp = text + 2;
    while (*interp == ' ' || *interp == '\t') interp++;
    char *arg = interp;
    while (*arg && *arg != ' ' && *arg != '\t') arg++;
    if (*arg) {
        *arg++ = '\0';
        while (*arg == ' ' || *arg == '\t') arg++;
        char *end = arg + strlen(arg);
        while (end > arg && (end[-1] == ' ' || end[-1] == '\t' || end[-1] == '\r')) *--end = '\0';
    }
    char interp_buf[1024];
    const char *new_interp = rewrite_path(interp, interp_buf, sizeof(interp_buf));
    int argc = 0;
    while (argv && argv[argc]) argc++;
    char **new_argv = calloc((size_t) argc + 4, sizeof(char *));
    if (!new_argv) { unlink(script_path); free(text); return -1; }
    int i = 0;
    new_argv[i++] = (char *) new_interp;
    if (*arg) new_argv[i++] = arg;
    new_argv[i++] = script_path;
    for (int k = 1; k < argc; k++) new_argv[i++] = argv[k];
    new_argv[i] = NULL;
    int ret = exec_planned(new_interp, new_argv, envp);
    int saved = errno;
    free(new_argv);
    unlink(script_path);
    free(text);
    errno = saved;
    return ret;
}

/*
 * targetSdk >= 29 (DROIDDESK_LINKER_EXEC=1): SELinux refuses to exec files in the app's data
 * dir (W^X), but /system/bin/linker64 still loads them (exec-probe, Galaxy A16, Android 16).
 * Every exec of such a file goes through linker64; a "#!" script goes through its interpreter,
 * which may itself be in the data dir. Plans are built in fixed buffers before any fork
 * (bionic's posix_spawn may vfork). Without the variable nothing here changes behaviour.
 */
#define LINKER64 "/system/bin/linker64"
#define PLAN_ARGS 512
#define PLAN_DEPTH 4

struct exec_plan {
    const char *path;                  /* what is really exec'd */
    char *argv[PLAN_ARGS];
    char interp[PLAN_DEPTH][1024];
    char arg[PLAN_DEPTH][256];
    char found[1024];                  /* PATH search result */
};

static int linker_exec_enabled(void) {
    static int state = -1;
    if (state < 0) {
        const char *v = getenv("DROIDDESK_LINKER_EXEC");
        state = v && v[0] == '1';
    }
    return state;
}

static int under_app_data(const char *path) {
    return path && (strncmp(path, "/data/user/", 11) == 0 || strncmp(path, "/data/data/", 11) == 0);
}

/* A Go program (PT_NOTE "Go" build ID). Go starts programs with raw syscalls, past this hook,
 * so at targetSdk >= 29 its children in app data got EACCES (gh aliases, gh repo clone -> git,
 * fzf's preview). */
static int is_go_elf(int fd, uint64_t phoff, uint16_t phentsize, uint16_t phnum) {
    for (uint16_t i = 0; i < phnum && i < 64; i++) {
        unsigned char ph[56];
        if (phentsize < 56 ||
            pread(fd, ph, sizeof(ph), (off_t) (phoff + (uint64_t) i * phentsize)) != (ssize_t) sizeof(ph)) return 0;
        uint32_t type;
        memcpy(&type, ph, 4);
        if (type != 4) continue; /* PT_NOTE */
        uint64_t off, size;
        memcpy(&off, ph + 8, 8);
        memcpy(&size, ph + 32, 8);
        unsigned char note[512];
        ssize_t got = pread(fd, note, size < sizeof(note) ? size : sizeof(note), (off_t) off);
        for (ssize_t p = 0; p + 12 <= got;) {
            uint32_t namesz, descsz, ntype;
            memcpy(&namesz, note + p, 4);
            memcpy(&descsz, note + p + 4, 4);
            memcpy(&ntype, note + p + 8, 4);
            if (namesz == 3 || namesz == 4) {
                if (p + 12 + 2 <= got && memcmp(note + p + 12, "Go", 2) == 0 && ntype == 4) return 1;
            }
            p += 12 + ((namesz + 3) & ~3u) + ((descsz + 3) & ~3u);
        }
    }
    return 0;
}

/* Already under ptrace (proot): a second proot cannot attach, and the first one handles exec. */
static int traced(void) {
    int fd = real_open("/proc/self/status", O_RDONLY | O_CLOEXEC);
    if (fd < 0) return 0;
    char buf[1024];
    ssize_t n = read(fd, buf, sizeof(buf) - 1);
    close(fd);
    if (n <= 0) return 0;
    buf[n] = '\0';
    const char *t = strstr(buf, "TracerPid:");
    if (!t) return 0;
    t += 10;
    while (*t == ' ' || *t == '\t') t++;
    return *t != '0';
}

/* 1: dynamic bionic ELF (PT_INTERP names linker64), 2: other ELF, 3: "#!" script, 0: other,
 * 4: ELF whose PT_INTERP is in app data (glibc-native mirrors: $PLIB/ld.so), copied to interp_out,
 * 5: dynamic bionic Go program, 6: static program (no PT_INTERP), 7: text without "#!". */
static int exec_kind(int fd, char *head, size_t head_size, char *interp_out, size_t interp_size) {
    ssize_t n = pread(fd, head, head_size - 1, 0);
    if (n < 0) return 0;
    head[n] = '\0';
    if (n >= 2 && head[0] == '#' && head[1] == '!') return 3;
    if (n < 4 || memcmp(head, "\177ELF", 4) != 0) return memchr(head, '\0', (size_t) n) ? 0 : 7;
    if (n < 64 || head[4] != 2) return 0;
    uint64_t phoff;
    uint16_t phentsize, phnum;
    memcpy(&phoff, head + 32, 8);
    memcpy(&phentsize, head + 54, 2);
    memcpy(&phnum, head + 56, 2);
    for (uint16_t i = 0; i < phnum && i < 64; i++) {
        unsigned char ph[56];
        if (phentsize < 56 ||
            pread(fd, ph, sizeof(ph), (off_t) (phoff + (uint64_t) i * phentsize)) != (ssize_t) sizeof(ph)) break;
        uint32_t type;
        memcpy(&type, ph, 4);
        if (type != 3) continue; /* PT_INTERP */
        uint64_t off, size;
        memcpy(&off, ph + 8, 8);
        memcpy(&size, ph + 32, 8);
        char interp[256];
        if (size == 0 || size >= sizeof(interp) || pread(fd, interp, size, (off_t) off) != (ssize_t) size) return 2;
        interp[size] = '\0';
        if (strstr(interp, "linker64")) return is_go_elf(fd, phoff, phentsize, phnum) ? 5 : 1;
        if (under_app_data(interp) && interp_out && strlen(interp) < interp_size) {
            strcpy(interp_out, interp);
            return 4;
        }
        return 2;
    }
    /* No PT_INTERP: a static program (Go/musl/Linux downloads). Only an executable one (ET_EXEC or
       PIE ET_DYN); shared libraries never get here through exec. */
    return 6;
}

/*
 * Fills plan with the exec that works for path/argv. Returns 0 when the plan differs from a
 * plain exec of path, -1 when path is exec'd unchanged.
 */
static int make_exec_plan(const char *path, char *const argv[], struct exec_plan *plan) {
    plan->path = path;
    if (!linker_exec_enabled() || !path) return -1;
    setup();
    int argc = 0;
    while (argv && argv[argc]) argc++;
    if (argc + 2 * PLAN_DEPTH + 3 >= PLAN_ARGS) return -1;
    char *cur[PLAN_ARGS];
    for (int i = 0; i < argc; i++) cur[i] = argv[i];
    cur[argc] = NULL;
    const char *cur_path = path;
    /* execve("/proc/self/exe"): Chromium and Electron start their zygote and renderers this way.
       Under linker64 the kernel's /proc/self/exe is the linker itself, which would take the first
       switch as its program; the real program is self_exe (identity_fix). */
    int changed = 0;
    if (is_self_exe_link(path)) { cur_path = self_exe; changed = 1; }
    for (int depth = 0; depth < PLAN_DEPTH; depth++) {
        if (!under_app_data(cur_path)) break;
        int fd = real_open(cur_path, O_RDONLY | O_CLOEXEC);
        if (fd < 0) break;
        char head[512];
        int kind = exec_kind(fd, head, sizeof(head), plan->interp[depth], sizeof(plan->interp[depth]));
        close(fd);
        if (kind == 4) {
            /* LOADER --argv0 ARGV0 PROGRAM ARGS…, what the kernel would do with PT_INTERP; the
               loader is a link into nativeLibraryDir, which Android lets apps execute. */
            int k = 0;
            plan->argv[k++] = plan->interp[depth];
            plan->argv[k++] = (char *) "--argv0";
            plan->argv[k++] = cur[0] ? cur[0] : (char *) cur_path;
            plan->argv[k++] = (char *) cur_path;
            for (int i = 1; i < PLAN_ARGS - 4 && cur[0] && cur[i]; i++) plan->argv[k++] = cur[i];
            plan->argv[k] = NULL;
            plan->path = plan->interp[depth];
            return 0;
        }
        if (kind == 5 || kind == 6) {
            /* sh proot-lexona PROGRAM ARGS…: proot (ptrace) also catches the raw execve of Go,
               starting its children through the loader, and its loader maps static programs,
               which neither the kernel (app data) nor linker64 run here. Plain linker64 for Go
               when proot is missing or already tracing this process (proot runs a static
               program's execve itself then). */
            if (!traced() &&
                snprintf(plan->interp[depth], sizeof(plan->interp[depth]), "%s/bin/proot-lexona", hook_prefix) <
                    (int) sizeof(plan->interp[depth]) &&
                real_access(plan->interp[depth], R_OK) == 0) {
                int k = 0;
                plan->argv[k++] = (char *) "sh";
                plan->argv[k++] = plan->interp[depth];
                plan->argv[k++] = (char *) cur_path;
                for (int i = 1; i < PLAN_ARGS - 3 && cur[0] && cur[i]; i++) plan->argv[k++] = cur[i];
                plan->argv[k] = NULL;
                plan->path = "/system/bin/sh";
                return 0;
            }
            if (kind == 6) break;
            kind = 1;
        }
        if (kind == 1) {
            /* linker64 [original argv0] path args…: the started program finds the original
               argv0 in /proc/self/cmdline (identity_fix below). */
            int k = 0;
            plan->argv[k++] = cur[0] ? cur[0] : (char *) cur_path;
            plan->argv[k++] = (char *) cur_path;
            for (int i = 1; i < PLAN_ARGS - 2 && cur[0] && cur[i]; i++) plan->argv[k++] = cur[i];
            plan->argv[k] = NULL;
            plan->path = LINKER64;
            return 0;
        }
        if (kind == 7) {
            /* A shell script without "#!" (openjdk-21's preinst): execve gives ENOEXEC and
               execvp falls back to /system/bin/sh, which then cannot open a file it may not
               exec from app data. POSIX shells run it themselves; Termux's sh does it here. */
            if (snprintf(plan->interp[depth], sizeof(plan->interp[depth]), "%s/bin/sh", hook_prefix) >=
                    (int) sizeof(plan->interp[depth]) ||
                real_access(plan->interp[depth], R_OK) != 0) break;
            char *next[PLAN_ARGS];
            int k = 0;
            next[k++] = plan->interp[depth];
            next[k++] = (char *) cur_path;
            for (int i = 1; cur[0] && cur[i] && k < PLAN_ARGS - 1; i++) next[k++] = cur[i];
            next[k] = NULL;
            memcpy(cur, next, sizeof(char *) * (size_t) (k + 1));
            cur_path = plan->interp[depth];
            changed = 1;
            continue;
        }
        if (kind != 3) break;
        char *line_end = strchr(head, '\n');
        if (!line_end) break;
        *line_end = '\0';
        char *interp = head + 2;
        while (*interp == ' ' || *interp == '\t') interp++;
        char *arg = interp;
        while (*arg && *arg != ' ' && *arg != '\t') arg++;
        if (*arg) {
            *arg++ = '\0';
            while (*arg == ' ' || *arg == '\t') arg++;
            char *end = arg + strlen(arg);
            while (end > arg && (end[-1] == ' ' || end[-1] == '\t' || end[-1] == '\r')) *--end = '\0';
        }
        char rebuf[1024];
        const char *real_interp;
        /* "#!/usr/bin/env python3" and friends: Android has no /usr, Termux's programs live in
           $PREFIX/bin (what termux-exec does). The FHS rewrite below would give $PREFIX/usr/bin. */
        if (strncmp(interp, "/usr/bin/", 9) == 0 &&
            snprintf(rebuf, sizeof(rebuf), "%s/bin/%s", hook_prefix, interp + 9) < (int) sizeof(rebuf) &&
            access(rebuf, X_OK) == 0) {
            real_interp = rebuf;
        } else {
            real_interp = rewrite_path(interp, rebuf, sizeof(rebuf));
        }
        snprintf(plan->interp[depth], sizeof(plan->interp[depth]), "%s", real_interp);
        snprintf(plan->arg[depth], sizeof(plan->arg[depth]), "%s", arg);
        /* interpreter [arg] script args…, as the kernel does it */
        char *next[PLAN_ARGS];
        int k = 0;
        next[k++] = plan->interp[depth];
        if (plan->arg[depth][0]) next[k++] = plan->arg[depth];
        next[k++] = (char *) cur_path;
        for (int i = 1; cur[0] && cur[i] && k < PLAN_ARGS - 1; i++) next[k++] = cur[i];
        next[k] = NULL;
        memcpy(cur, next, sizeof(char *) * (size_t) (k + 1));
        cur_path = plan->interp[depth];
        changed = 1;
    }
    if (!changed) return -1;
    int k = 0;
    for (; cur[k]; k++) plan->argv[k] = cur[k];
    plan->argv[k] = NULL;
    plan->path = cur_path;
    return 0;
}

/* A bare command name searched in PATH, as execvp does. NULL when not found. */
static const char *search_path(const char *file, char *out, size_t out_size) {
    const char *path_env = getenv("PATH");
    if (!path_env || !*path_env) path_env = "/system/bin";
    const char *p = path_env;
    while (*p) {
        const char *colon = strchr(p, ':');
        size_t dir_len = colon ? (size_t) (colon - p) : strlen(p);
        if (dir_len > 0 && dir_len + strlen(file) + 2 < out_size) {
            memcpy(out, p, dir_len);
            out[dir_len] = '/';
            strcpy(out + dir_len + 1, file);
            struct stat st;
            if (real_stat(out, &st) == 0 && S_ISREG(st.st_mode) && real_access(out, X_OK) == 0) return out;
        }
        if (!colon) break;
        p = colon + 1;
    }
    return NULL;
}

static int exec_planned(const char *path, char *const argv[], char *const envp[]) {
    if (!real_execve) real_execve = dlsym(RTLD_NEXT, "execve");
    static __thread struct exec_plan plan;
    if (make_exec_plan(path, argv, &plan) == 0) return real_execve(plan.path, plan.argv, envp);
    return real_execve(path, argv, envp);
}

int execve(const char *pathname, char *const argv[], char *const envp[]) {
    if (!real_execve) real_execve = dlsym(RTLD_NEXT, "execve");
    char buf[1024];
    const char *path = rewrite_exec_path(pathname, buf, sizeof(buf));
    {
        int saved = errno;
        if (exec_relocated_maintainer_script(path, argv, envp) < 0) errno = saved;
    }
    if (linker_exec_enabled()) return exec_planned(path, argv, envp);
    int ret = real_execve(path, argv, envp);
    if (errno == ENOENT || errno == EACCES) {
        int saved = errno;
        if (exec_termux_script(path, argv, envp) < 0) errno = saved;
    }
    return ret;
}

int execv(const char *pathname, char *const argv[]) {
    return execve(pathname, argv, environ);
}

int execvp(const char *file, char *const argv[]) {
    if (!real_execvp) real_execvp = dlsym(RTLD_NEXT, "execvp");
    if (!real_execve) real_execve = dlsym(RTLD_NEXT, "execve");
    char buf[1024];
    const char *path = rewrite_exec_path(file, buf, sizeof(buf));
    // A path (dpkg passes maintainer scripts this way) does not use the PATH search.
    if (path && strchr(path, '/')) return execve(path, argv, environ);
    if (linker_exec_enabled() && path && *path) {
        char found[1024];
        setup();
        if (search_path(path, found, sizeof(found))) return execve(found, argv, environ);
        errno = ENOENT;
        return -1;
    }
    return real_execvp(path, argv);
}

int execvpe(const char *file, char *const argv[], char *const envp[]) {
    if (!real_execvpe) real_execvpe = dlsym(RTLD_NEXT, "execvpe");
    char buf[1024];
    const char *path = rewrite_exec_path(file, buf, sizeof(buf));
    if (path && strchr(path, '/')) return execve(path, argv, envp);
    if (linker_exec_enabled() && path && *path) {
        char found[1024];
        setup();
        if (search_path(path, found, sizeof(found))) return execve(found, argv, envp);
        errno = ENOENT;
        return -1;
    }
    return real_execvpe(path, argv, envp);
}

/* The execl family: collect the arguments, then the matching execv*. */
#define COLLECT_ARGS(first, list, out, count, max)                     \
    do {                                                               \
        (out)[0] = (char *) (first);                                   \
        (count) = 1;                                                   \
        char *next_arg;                                                \
        while ((next_arg = va_arg(list, char *)) != NULL && (count) < (max) - 1) \
            (out)[(count)++] = next_arg;                               \
        (out)[(count)] = NULL;                                         \
    } while (0)

int execl(const char *path, const char *arg, ...) {
    char *argv[PLAN_ARGS];
    int argc;
    va_list ap;
    va_start(ap, arg);
    COLLECT_ARGS(arg, ap, argv, argc, PLAN_ARGS);
    va_end(ap);
    return execve(path, argv, environ);
}

int execlp(const char *file, const char *arg, ...) {
    char *argv[PLAN_ARGS];
    int argc;
    va_list ap;
    va_start(ap, arg);
    COLLECT_ARGS(arg, ap, argv, argc, PLAN_ARGS);
    va_end(ap);
    return execvp(file, argv);
}

int execle(const char *path, const char *arg, ...) {
    char *argv[PLAN_ARGS];
    int argc;
    va_list ap;
    va_start(ap, arg);
    COLLECT_ARGS(arg, ap, argv, argc, PLAN_ARGS);
    char *const *envp = va_arg(ap, char *const *);
    va_end(ap);
    return execve(path, argv, envp);
}

/* fexecve: the fd's path through the same plan (a data-dir fd cannot be exec'd either). */
static int (*real_fexecve)(int, char *const [], char *const []) = NULL;
int fexecve(int fd, char *const argv[], char *const envp[]) {
    if (!real_fexecve) real_fexecve = dlsym(RTLD_NEXT, "fexecve");
    if (linker_exec_enabled()) {
        char link[64], target[1024];
        snprintf(link, sizeof(link), "/proc/self/fd/%d", fd);
        if (!real_readlink) setup();
        ssize_t n = real_readlink(link, target, sizeof(target) - 1);
        if (n > 0) {
            target[n] = '\0';
            if (under_app_data(target)) return execve(target, argv, envp);
        }
    }
    return real_fexecve(fd, argv, envp);
}

/* posix_spawn(p): the plan is made here, in the parent, before libc forks. */
static int (*real_posix_spawn)(pid_t *, const char *, const posix_spawn_file_actions_t *,
                               const posix_spawnattr_t *, char *const [], char *const []) = NULL;
static int (*real_posix_spawnp)(pid_t *, const char *, const posix_spawn_file_actions_t *,
                                const posix_spawnattr_t *, char *const [], char *const []) = NULL;

int posix_spawn(pid_t *pid, const char *path, const posix_spawn_file_actions_t *actions,
                const posix_spawnattr_t *attr, char *const argv[], char *const envp[]) {
    if (!real_posix_spawn) real_posix_spawn = dlsym(RTLD_NEXT, "posix_spawn");
    if (linker_exec_enabled()) {
        char buf[1024];
        const char *p = rewrite_exec_path(path, buf, sizeof(buf));
        struct exec_plan *plan = malloc(sizeof(*plan));
        if (plan) {
            int rc = make_exec_plan(p, argv, plan) == 0
                ? real_posix_spawn(pid, plan->path, actions, attr, plan->argv, envp)
                : real_posix_spawn(pid, p, actions, attr, argv, envp);
            free(plan);
            return rc;
        }
    }
    return real_posix_spawn(pid, path, actions, attr, argv, envp);
}

int posix_spawnp(pid_t *pid, const char *file, const posix_spawn_file_actions_t *actions,
                 const posix_spawnattr_t *attr, char *const argv[], char *const envp[]) {
    if (!real_posix_spawnp) real_posix_spawnp = dlsym(RTLD_NEXT, "posix_spawnp");
    if (linker_exec_enabled() && file && *file) {
        if (strchr(file, '/')) return posix_spawn(pid, file, actions, attr, argv, envp);
        char found[1024];
        setup();
        if (search_path(file, found, sizeof(found))) return posix_spawn(pid, found, actions, attr, argv, envp);
        return ENOENT;
    }
    return real_posix_spawnp(pid, file, actions, attr, argv, envp);
}

/*
 * Identity of a program started as "linker64 argv0 path args…": the kernel sees linker64
 * (comm "linker64", /proc/self/exe the APEX linker) and the program gets argv[0] = path.
 * Restored here: argv[0] (login shells, multi-call programs), comm (pgrep/pkill -x) and what
 * readlink("/proc/self/exe") returns (node, Python, Chromium/Firefox re-exec).
 */
static char self_exe[1024];
static char self_argv0[512];

__attribute__((constructor)) static void identity_fix(int argc, char **argv) {
    if (!linker_exec_enabled()) return;
    char exe[256];
    ssize_t n = syscall(SYS_readlinkat, AT_FDCWD, "/proc/self/exe", exe, sizeof(exe) - 1);
    if (n <= 0) return;
    exe[n] = '\0';
    size_t len = (size_t) n;
    if (len < 9 || strcmp(exe + len - 9, "/linker64") != 0) return;
    int fd = (int) syscall(SYS_openat, AT_FDCWD, "/proc/self/cmdline", O_RDONLY | O_CLOEXEC);
    if (fd < 0) return;
    char cmd[2048];
    ssize_t got = read(fd, cmd, sizeof(cmd) - 1);
    close(fd);
    if (got <= 0) return;
    cmd[got] = '\0';
    const char *orig_argv0 = cmd;
    size_t first = strlen(cmd);
    if ((ssize_t) first + 1 >= got) return;
    const char *program = cmd + first + 1;
    snprintf(self_exe, sizeof(self_exe), "%s", program);
    /* The kernel's /proc/self/exe has no symlinks in it: Termux's bin/firefox links to
     * lib/firefox/firefox, and Firefox looks for libxul.so next to /proc/self/exe ("Couldn't
     * load XPCOM", Galaxy A16). Raw syscalls: this runs before setup(). */
    int pfd = (int) syscall(SYS_openat, AT_FDCWD, program, O_PATH | O_CLOEXEC);
    if (pfd >= 0) {
        char fdlink[64], real[1024];
        snprintf(fdlink, sizeof(fdlink), "/proc/self/fd/%d", pfd);
        ssize_t rn = syscall(SYS_readlinkat, AT_FDCWD, fdlink, real, sizeof(real) - 1);
        if (rn > 0 && real[0] == '/') {
            real[rn] = '\0';
            snprintf(self_exe, sizeof(self_exe), "%s", real);
        }
        close(pfd);
    }
    /* Started by the app (ProcessBuilder's argv[0] is linker64 itself): argv0 is the program. */
    size_t orig_len = strlen(orig_argv0);
    if (orig_len >= 8 && strcmp(orig_argv0 + orig_len - 8, "linker64") == 0) orig_argv0 = program;
    snprintf(self_argv0, sizeof(self_argv0), "%s", orig_argv0);
    if (argc > 0 && argv && argv[0] && strcmp(argv[0], program) == 0) argv[0] = self_argv0;
    const char *base = strrchr(program, '/');
    prctl(PR_SET_NAME, base ? base + 1 : program, 0, 0, 0);
}

static int is_self_exe_link(const char *path) {
    if (!self_exe[0] || !path) return 0;
    if (strcmp(path, "/proc/self/exe") == 0 || strcmp(path, "/proc/thread-self/exe") == 0) return 1;
    char mine[64];
    snprintf(mine, sizeof(mine), "/proc/%d/exe", getpid());
    return strcmp(path, mine) == 0;
}

static ssize_t copy_self_exe(char *buf, size_t bufsiz) {
    size_t len = strlen(self_exe);
    if (len > bufsiz) len = bufsiz;
    memcpy(buf, self_exe, len);
    return (ssize_t) len;
}
