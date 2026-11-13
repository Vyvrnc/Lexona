-keep class com.termux.x11.** { *; }

# Shizuku starts the UserService by class name (reflection, no-arg constructor) as shell.
-keep class com.orailnoor.droiddesk.runtime.ShellFilesService { *; }
-keep class com.orailnoor.droiddesk.IShellFiles** { *; }
# The shell-side service starts interactive shells through Termux's JNI by reflection.
-keep class com.termux.terminal.JNI { *; }
