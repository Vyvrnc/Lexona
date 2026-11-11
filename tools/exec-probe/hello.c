// hello-glibc / hello-bionic / libhello.so for the exec probe.
//   (no args)                     prints hello
//   spawn LOADER LIBPATH PROGRAM  starts PROGRAM through LOADER (the loader-in-nativeLibraryDir path)
//   spawn-direct PROGRAM [ARGS]   posix_spawns PROGRAM directly (fails at targetSdk >= 29
//                                 unless a preload rewrites it)
//   exec-direct PROGRAM [ARGS]    execv's PROGRAM directly (same, through execve)
//   info                          what the process sees of itself: argv0, /proc/self/exe,
//                                 comm, AT_EXECFN, LD_PRELOAD
#include <errno.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/auxv.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

#ifdef __BIONIC__
#define FLAVOR "bionic"
#else
#define FLAVOR "glibc"
#endif

static void info(char **argv) {
    char exe[512] = "?", comm[64] = "?";
    ssize_t n = readlink("/proc/self/exe", exe, sizeof exe - 1);
    if (n > 0) exe[n] = 0;
    FILE *f = fopen("/proc/self/comm", "r");
    if (f) {
        if (fgets(comm, sizeof comm, f)) comm[strcspn(comm, "\n")] = 0;
        fclose(f);
    }
    const char *execfn = (const char *) getauxval(AT_EXECFN);
    const char *pre = getenv("LD_PRELOAD");
    printf("info %s argv0=%s exe=%s comm=%s execfn=%s preload=%s\n", FLAVOR, argv[0], exe, comm,
           execfn ? execfn : "?", pre ? "yes" : "no");
}

int main(int argc, char **argv) {
    pid_t pid;
    int rc, status = 0;
    if (argc > 4 && !strcmp(argv[1], "spawn")) {
        char *args[] = {argv[2], "--library-path", argv[3], argv[4], NULL};
        rc = posix_spawn(&pid, argv[2], NULL, NULL, args, environ);
    } else if (argc > 2 && !strcmp(argv[1], "spawn-direct")) {
        rc = posix_spawn(&pid, argv[2], NULL, NULL, &argv[2], environ);
    } else if (argc > 2 && !strcmp(argv[1], "exec-direct")) {
        fflush(stdout);
        execv(argv[2], &argv[2]);
        printf("exec failed: %s\n", strerror(errno));
        return 1;
    } else if (argc > 1 && !strcmp(argv[1], "info")) {
        info(argv);
        return 0;
    } else {
        printf("hello %s\n", FLAVOR);
        return 0;
    }
    if (rc) { printf("spawn failed: %s\n", strerror(rc)); return 1; }
    fflush(stdout);
    waitpid(pid, &status, 0);
    printf("child exit=%d\n", WIFEXITED(status) ? WEXITSTATUS(status) : -1);
    return 0;
}
