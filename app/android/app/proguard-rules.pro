-keep class com.termux.x11.** { *; }

# Shizuku starts the UserService by class name (reflection, no-arg constructor) as shell.
-keep class com.orailnoor.droiddesk.runtime.ShellFilesService { *; }
-keep class com.orailnoor.droiddesk.IShellFiles** { *; }
