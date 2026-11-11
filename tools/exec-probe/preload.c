// libpreload.so for the exec probe: the smallest version of the targetSdk 36 exec hook.
// Loaded through LD_PRELOAD into bionic programs started as `/system/bin/linker64 PROGRAM`.
//  - constructor: logs that it ran, with argc/argv[0] as bionic hands them over;
//  - execve/execv/posix_spawn: an ELF under the app's data dir is started through linker64
//    (argv: [original argv0, path, args...]), everything else unchanged.
// It answers: does linker64 load an app-data preload in the app process at targetSdk 36, and
// can a hooked child start a grandchild?
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define LINKER "/system/bin/linker64"
#define MAX_ARGS 64

static int under_data(const char *path) {
    return path && (strncmp(path, "/data/user/", 11) == 0 || strncmp(path, "/data/data/", 11) == 0);
}

// Builds [argv0, path, argv1...] into out; returns 0 or -1 when it does not fit.
static int linker_argv(const char *path, char *const argv[], char *out[]) {
    int n = 0;
    out[n++] = (char *) (argv && argv[0] ? argv[0] : path);
    out[n++] = (char *) path;
    for (int i = 1; argv && argv[i]; i++) {
        if (n >= MAX_ARGS - 1) return -1;
        out[n++] = argv[i];
    }
    out[n] = NULL;
    return 0;
}

__attribute__((constructor)) static void probe_ctor(int argc, char **argv) {
    fprintf(stderr, "[preload ctor pid=%d argc=%d argv0=%s]\n", getpid(), argc,
            argc > 0 && argv ? argv[0] : "?");
}

int execve(const char *path, char *const argv[], char *const envp[]) {
    static int (*real)(const char *, char *const[], char *const[]);
    if (!real) real = dlsym(RTLD_NEXT, "execve");
    if (under_data(path)) {
        char *args[MAX_ARGS];
        if (linker_argv(path, argv, args) == 0) return real(LINKER, args, envp);
    }
    return real(path, argv, envp);
}

int execv(const char *path, char *const argv[]) {
    extern char **environ;
    return execve(path, argv, environ);
}

int posix_spawn(pid_t *pid, const char *path, const posix_spawn_file_actions_t *actions,
                const posix_spawnattr_t *attr, char *const argv[], char *const envp[]) {
    static int (*real)(pid_t *, const char *, const posix_spawn_file_actions_t *,
                       const posix_spawnattr_t *, char *const[], char *const[]);
    if (!real) real = dlsym(RTLD_NEXT, "posix_spawn");
    if (under_data(path)) {
        // Prepared before libc forks (bionic may vfork): no allocation in the child.
        char *args[MAX_ARGS];
        if (linker_argv(path, argv, args) == 0) return real(pid, LINKER, actions, attr, args, envp);
    }
    return real(pid, path, actions, attr, argv, envp);
}
