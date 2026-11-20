/* Minimal config.h for building module-aaudio-sink on its own (PulseAudio 17.0, Termux aarch64). */
#define PACKAGE "pulseaudio"
#define PACKAGE_NAME "pulseaudio"
#define PACKAGE_VERSION "17.0-dirty"
#define GETTEXT_PACKAGE "pulseaudio"
#define HAVE_PTHREAD 1
#define HAVE_ATOMIC_BUILTINS 1
#define HAVE_ATOMIC_BUILTINS_MEMORY_MODEL 1
#define HAVE_FAST_64BIT_OPERATIONS 1
#define HAVE_CLOCK_GETTIME 1
#define HAVE_SYS_SYSCALL_H 1
#define OS_IS_ANDROID 1
