import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:droiddesk/theme/lexona_theme.dart';
import 'package:droiddesk/state/app_state.dart';
import 'package:droiddesk/services/platform_bridge.dart';
import 'package:droiddesk/screens/setup/de_install_screen.dart';
import 'package:droiddesk/screens/apps/app_catalog_screen.dart';
import 'package:droiddesk/screens/desktop_tools_screen.dart';
import 'package:droiddesk/screens/gpu_support_screen.dart';

/// Home dashboard — shown after setup is complete.
/// Central hub for launching the desktop, terminal, and managing the environment.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isDark = state.isDarkMode;

    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        body: Container(
        decoration: BoxDecoration(
          gradient: LexonaTheme.backgroundGradient,
        ),
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              // ── App Bar ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.asset(
                            'assets/icons/logo.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Lexona', style: LexonaTheme.subheading),
                          Text(
                            state.isRunning ? 'Desktop running' : 'Ready',
                            style: LexonaTheme.bodySm.copyWith(
                              color: state.isRunning
                                  ? LexonaTheme.success
                                  : LexonaTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => state.toggleThemeMode(),
                        tooltip: state.isDarkMode
                            ? 'Switch to light theme'
                            : 'Switch to dark theme',
                        icon: Icon(
                          state.isDarkMode
                              ? Icons.light_mode_rounded
                              : Icons.dark_mode_rounded,
                          color: LexonaTheme.textMuted,
                        ),
                      ),
                      IconButton(
                        onPressed: () => _showSettings(context),
                        icon: Icon(
                          Icons.settings_rounded,
                          color: LexonaTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Status Card ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: _buildStatusCard(state)
                      .animate()
                      .fadeIn(duration: 500.ms)
                      .slideY(begin: 0.05, duration: 500.ms),
                ),
              ),

              if (state.errorMessage != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: LexonaTheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: LexonaTheme.error),
                      ),
                      child: ListTile(
                        leading: Icon(
                          Icons.error_outline_rounded,
                          color: LexonaTheme.error,
                        ),
                        title: Text(
                          state.errorMessage!,
                          style: LexonaTheme.bodySm,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close_rounded),
                          tooltip: 'Dismiss error',
                          onPressed: state.clearError,
                        ),
                      ),
                    ),
                  ),
                ),

              // ── Quick Actions ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                  child: Text(
                    'QUICK ACTIONS',
                    style: LexonaTheme.label,
                  ).animate().fadeIn(delay: 200.ms, duration: 400.ms),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: Column(
                    children: [
                      // Installation is only actionable when setup is missing.
                      // Do not show an "Installed" card that can reinstall the DE.
                      if (!state.isDEInstalled) ...[
                        _ActionCard(
                          icon: Icons.download_rounded,
                          title: 'Install ${state.selectedDE.toUpperCase()}',
                          subtitle:
                              'Install desktop environment packages (one-time setup)',
                          color: LexonaTheme.primaryText,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const DEInstallScreen(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                      ],

                      // ── Launch Desktop / Reconnect ──
                      if (state.isRunning)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ActionCard(
                            icon: Icons.fullscreen_rounded,
                            title: 'Return to desktop',
                            subtitle:
                                '${state.selectedDE.toUpperCase()} is currently running in background',
                            color: LexonaTheme.primaryText,
                            gradient: LexonaTheme.primaryGradient,
                            onTap: () {
                              state.launchDesktopActivity();
                            },
                          ),
                        ),

                      // ── Stop only the desktop: terminals and Claude Code keep running ──
                      if (!state.hasRoot && state.isRunning)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ActionCard(
                            icon: Icons.desktop_access_disabled_rounded,
                            title: 'Stop desktop',
                            subtitle:
                                'Ends XFCE to save power; the terminal and Claude Code keep running',
                            color: LexonaTheme.primaryText,
                            busyText: state.busyAction == 'stop-desktop'
                                ? 'Stopping the desktop…'
                                : null,
                            onTap: () async {
                              final ok = await state.stopDesktop();
                              if (context.mounted) {
                                _notice(context, ok ? 'Desktop stopped' : 'The desktop could not be stopped', error: !ok);
                              }
                            },
                          ),
                        ),

                      // ── Restart only the desktop (XFCE), apps stay ──
                      if (!state.hasRoot &&
                          (state.isRunning || state.desktopEnded))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ActionCard(
                            icon: Icons.restart_alt_rounded,
                            title: 'Restart desktop',
                            subtitle: state.desktopEnded
                                ? 'The desktop ended. Starts XFCE again; app windows stay'
                                : 'Restarts the panel, desktop and window manager; app windows stay',
                            color: LexonaTheme.primaryText,
                            busyText: state.busyAction == 'restart-desktop'
                                ? 'Restarting the desktop…'
                                : null,
                            onTap: () async {
                              final ok = await state.restartDesktop();
                              if (context.mounted) {
                                _notice(context, ok ? 'Desktop restarted' : 'The desktop could not be restarted', error: !ok);
                              }
                            },
                          ),
                        ),

                      _ActionCard(
                        icon: state.isRunning
                            ? Icons.stop_circle_rounded
                            : Icons.desktop_mac_rounded,
                        title: state.isRunning
                            ? 'Stop server'
                            : 'Launch desktop',
                        subtitle: state.isRunning
                            ? 'Shutdown Linux environment'
                            : 'Start ${state.selectedDE.toUpperCase()} desktop environment',
                        color: state.isRunning
                            ? LexonaTheme.error
                            : LexonaTheme.primaryText,
                        gradient: state.isRunning
                            ? null
                            : LexonaTheme.primaryGradient,
                        busyText: state.busyAction == 'stop-server'
                            ? 'Stopping Linux: desktop, terminals, background programs…'
                            : null,
                        onTap: () async {
                          if (state.isRunning) {
                            await _stopServer(context, state);
                          } else {
                            if (!state.isDEInstalled) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'No desktop environment installed. Please complete setup first.',
                                  ),
                                  // Opaque theme surface; the error shows as a 1 px border next to the word.
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(LexonaTheme.radiusMd),
                                    side: BorderSide(color: LexonaTheme.error),
                                  ),
                                ),
                              );
                              return;
                            }
                            await state.startLinux(mode: 'x11');
                          }
                        },
                      ),

                      if (!state.hasRoot &&
                          !state.isRunning &&
                          state.serverRunning) ...[
                        const SizedBox(height: 12),
                        _ActionCard(
                          icon: Icons.stop_circle_rounded,
                          title: 'Stop server',
                          subtitle:
                              'The desktop is not running; ends the whole Linux environment, terminals included',
                          color: LexonaTheme.error,
                          busyText: state.busyAction == 'stop-server'
                              ? 'Stopping Linux: terminals and background programs…'
                              : null,
                          onTap: () => _stopServer(context, state),
                        ),
                      ],

                      const SizedBox(height: 12),

                      // ── Terminal ──
                      _ActionCard(
                        icon: Icons.terminal_rounded,
                        title: 'Terminal',
                        subtitle:
                            'Open a Linux shell in the ${state.hasRoot ? 'Ubuntu chroot' : 'native Termux'} environment',
                        color: LexonaTheme.primaryText,
                        onTap: () {
                          if (state.hasRoot) {
                            state.useNativeTerminal();
                            _showTerminal(context, state);
                          } else {
                            DroidDeskPlatform.openTerminal('shell');
                          }
                        },
                      ),

                      if (!state.hasRoot &&
                          state.optionalApps['claude_code'] == true) ...[
                        const SizedBox(height: 12),
                        _ActionCard(
                          icon: Icons.auto_awesome_rounded,
                          image: 'assets/icons/claude.png',
                          title: 'Claude Code',
                          subtitle: 'Claude Code in a terminal, without the desktop',
                          color: const Color(0xFFD97757),
                          onTap: () => DroidDeskPlatform.openTerminal('claude'),
                        ),
                      ],

                      if (!state.hasRoot &&
                          state.optionalApps['codex'] == true) ...[
                        const SizedBox(height: 12),
                        _ActionCard(
                          icon: Icons.code_rounded,
                          title: 'Codex',
                          subtitle: 'OpenAI Codex CLI in a terminal, without the desktop',
                          color: const Color(0xFF10A37F),
                          onTap: () => DroidDeskPlatform.openTerminal('codex'),
                        ),
                      ],

                      if (!state.hasRoot &&
                          state.optionalApps['proot_debian'] == true) ...[
                        const SizedBox(height: 12),
                        _ActionCard(
                          icon: Icons.inventory_2_rounded,
                          title: 'Debian shell',
                          subtitle:
                              'Open the optional minimal PRoot compatibility environment',
                          color: const Color(0xFFD70A53),
                          onTap: () => DroidDeskPlatform.openTerminal('debian'),
                        ),
                      ],

                      const SizedBox(height: 12),

                      _ActionCard(
                        icon: Icons.apps_rounded,
                        title: 'Add applications',
                        subtitle:
                            'Install applications or optional Debian compatibility',
                        color: LexonaTheme.primaryText,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const AppCatalogScreen(),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 12),
                    ].animate(interval: 80.ms).fadeIn(delay: 300.ms, duration: 400.ms).slideY(begin: 0.05, duration: 400.ms),
                  ),
                ),
              ),

              // ── System Info ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: Text(
                    'SYSTEM',
                    style: LexonaTheme.label,
                  ).animate().fadeIn(delay: 500.ms, duration: 400.ms),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: LexonaTheme.cardBg,
                      borderRadius: BorderRadius.circular(LexonaTheme.radiusMd),
                      border: Border.all(color: LexonaTheme.surfaceBorder),
                    ),
                    child: Column(
                      children: [
                        _infoRow(
                          'Distribution',
                          _distroLabel(state.installedDistro),
                        ),
                        _divider(),
                        _infoRow('Desktop', state.selectedDE.toUpperCase()),
                        _divider(),
                        InkWell(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const GpuSupportScreen()),
                          ),
                          child: Row(
                            children: [
                              Expanded(child: _infoRow('GPU', state.gpuType)),
                              const SizedBox(width: 6),
                              Icon(Icons.chevron_right_rounded, size: 18, color: LexonaTheme.textMuted),
                            ],
                          ),
                        ),
                        _divider(),
                        _infoRow(
                          'Renderer',
                          state.deviceInfo['graphicsMode']?.toString() ??
                              'Automatic',
                        ),
                        _divider(),
                        _infoRow(
                          'Device',
                          '${state.deviceInfo['brand'] ?? ''} ${state.deviceInfo['model'] ?? ''}',
                        ),
                        _divider(),
                        _infoRow(
                          'Android',
                          '${state.deviceInfo['androidVersion'] ?? ''} (SDK ${state.deviceInfo['sdkVersion'] ?? ''})',
                        ),
                        _divider(),
                        _infoRow(
                          'RAM',
                          '${state.deviceInfo['totalRamMB'] ?? 'N/A'} MB',
                        ),
                        _divider(),
                        _infoRow(
                          'Storage free',
                          '${state.deviceInfo['availableStorageMB'] ?? 'N/A'} MB',
                        ),
                        if (state.deviceInfo['phantomLimit'] == true) ...[
                          _divider(),
                          InkWell(
                            onTap: () => _showPhantomLimitHelp(context),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                children: [
                                  Icon(Icons.warning_amber_rounded, size: 18, color: LexonaTheme.warning),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Child process limit is on: Android may stop Linux programs',
                                      style: LexonaTheme.body.copyWith(color: LexonaTheme.warning),
                                    ),
                                  ),
                                  Icon(Icons.chevron_right_rounded, size: 18, color: LexonaTheme.textMuted),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ).animate().fadeIn(delay: 600.ms, duration: 400.ms),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

  // ── Status Card ──

  Widget _buildStatusCard(AppState state) {
    final activeBorderColor = LexonaTheme.success;
    final activeTitleColor = LexonaTheme.success;
    final activeSubtitleColor = LexonaTheme.textSecondary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: LexonaTheme.surface,
        borderRadius: BorderRadius.circular(LexonaTheme.radiusMd),
        border: Border.all(
          color: state.isRunning ? activeBorderColor : LexonaTheme.border,
        ),
      ),
      child: Row(
        children: [
          // Status indicator
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: state.isRunning
                  ? LexonaTheme.success
                  : LexonaTheme.textMuted,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.isRunning ? 'Desktop active' : 'Desktop idle',
                  style: LexonaTheme.subheading.copyWith(
                    color: state.isRunning
                        ? activeTitleColor
                        : LexonaTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  state.isRunning
                      ? '${state.selectedDE.toUpperCase()} · ${_distroLabel(state.installedDistro)}'
                      : 'Tap "Launch desktop" to start',
                  style: LexonaTheme.bodySm.copyWith(
                    color: state.isRunning
                        ? activeSubtitleColor
                        : LexonaTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ──

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(label, style: LexonaTheme.bodySm),
          const Spacer(),
          Text(
            value,
            style: LexonaTheme.monoSm.copyWith(color: LexonaTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  static const _phantomAdb =
      'adb shell settings put global settings_enable_monitor_phantom_procs false\n'
      'adb shell device_config set_sync_disabled_for_tests persistent\n'
      'adb shell device_config put activity_manager max_phantom_processes 2147483647';

  void _showPhantomLimitHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded, color: LexonaTheme.warning),
        title: const Text('Android limits child processes'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Android 12 and newer stop the oldest programs of an app once it runs more than '
                '32 of them. The desktop alone uses about 27, so a browser or a few terminals '
                'are enough for Android to close Linux programs every few minutes.\n\n'
                'To turn the limit off: Settings > Developer options > Disable child process '
                'restrictions (Android 14 and newer). Or once from a computer:',
              ),
              const SizedBox(height: 12),
              SelectableText(
                _phantomAdb,
                style: LexonaTheme.mono.copyWith(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(const ClipboardData(text: _phantomAdb));
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Copy commands'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return Divider(
      height: 1,
      color: LexonaTheme.border,
    );
  }

  String _distroLabel(String distro) {
    switch (distro) {
      case 'ubuntu-chroot':
        return 'Ubuntu 24.04 (chroot)';
      case 'ubuntu':
        return 'Ubuntu 24.04';
      case 'alpine':
        return 'Alpine Linux 3.20';
      case 'kali':
        return 'Kali Linux';
      case 'termux-native':
        return 'Termux native';
      default:
        return distro;
    }
  }

  // ── Dialogs ──

  void _showSettings(BuildContext pageContext) {
    showModalBottomSheet(
      context: pageContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Consumer<AppState>(
        builder: (context, state, _) {
          return Container(
            decoration: BoxDecoration(
              color: LexonaTheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(LexonaTheme.radiusLg)),
              border: Border.all(color: LexonaTheme.surfaceBorder),
            ),
            padding: EdgeInsets.fromLTRB(
              24,
              24,
              24,
              24 + MediaQuery.of(sheetContext).padding.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Settings', style: LexonaTheme.title),
                  const SizedBox(height: 20),

                  // App Theme Section
                  Row(
                    children: [
                      Icon(
                        state.isDarkMode
                            ? Icons.dark_mode_rounded
                            : Icons.light_mode_rounded,
                        color: LexonaTheme.primaryText,
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('App theme', style: LexonaTheme.subheading),
                          Text(
                            state.themeMode == ThemeMode.system
                                ? 'System default'
                                : state.isDarkMode
                                    ? 'Dark theme'
                                    : 'Light theme',
                            style: LexonaTheme.bodySm,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.dark,
                          label: Text('Dark'),
                          icon: Icon(Icons.dark_mode_outlined, size: 16),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          label: Text('Light'),
                          icon: Icon(Icons.light_mode_outlined, size: 16),
                        ),
                        ButtonSegment(
                          value: ThemeMode.system,
                          label: Text('System'),
                          icon: Icon(Icons.brightness_auto_outlined, size: 16),
                        ),
                      ],
                      selected: {state.themeMode},
                      onSelectionChanged: (Set<ThemeMode> selection) {
                        state.setThemeMode(selection.first);
                      },
                    ),
                  ),
                  const Divider(height: 28),

                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.battery_charging_full,
                      color: LexonaTheme.warning,
                    ),
                    title: const Text('Battery optimization'),
                    subtitle: const Text('Disable to prevent session killing'),
                    onTap: () {
                      DroidDeskPlatform.requestBatteryOptimization();
                      Navigator.pop(sheetContext);
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.home_rounded,
                      color: LexonaTheme.primaryText,
                    ),
                    title: const Text('Set as default launcher'),
                    subtitle: const Text(
                      'Open the Linux desktop when the phone starts',
                    ),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      DroidDeskPlatform.requestDefaultLauncher();
                    },
                  ),
                  FutureBuilder<bool>(
                    future: DroidDeskPlatform.isDefaultLauncher(),
                    builder: (_, snapshot) {
                      if (snapshot.data != true) return const SizedBox.shrink();
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.home_outlined,
                          color: LexonaTheme.error,
                        ),
                        title: const Text('Stop using as default launcher'),
                        subtitle: const Text('Choose another Home app directly'),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _confirmUnsetLauncher(pageContext);
                        },
                      );
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.auto_awesome_rounded,
                      color: LexonaTheme.primaryText,
                    ),
                    title: const Text('Desktop tools'),
                    subtitle: const Text('Manage dock apps and desktop backups'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      Navigator.of(pageContext).push(
                        MaterialPageRoute(builder: (_) => const DesktopToolsScreen()),
                      );
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.refresh, color: LexonaTheme.primaryText),
                    title: const Text('Reinstall Linux'),
                    subtitle: const Text('Re-download and set up rootfs'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmUnsetLauncher(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change default launcher?'),
        content: const Text(
          'Lexona will stop opening automatically as your Home app. Android will ask you to choose another launcher.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Change launcher'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await DroidDeskPlatform.unsetDefaultLauncher();
    }
  }

  void _showTerminal(BuildContext context, AppState state) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _TerminalSheet(state: state),
    );
  }

  void _showDebianTerminal(BuildContext context, AppState state) {
    _showTerminal(context, state);
    Future<void>.delayed(const Duration(milliseconds: 150), () {
      state.startDebianShell();
    });
  }
}

/// Simple terminal bottom sheet with command execution.
class _TerminalSheet extends StatefulWidget {
  final AppState state;
  const _TerminalSheet({required this.state});

  @override
  State<_TerminalSheet> createState() => _TerminalSheetState();
}

class _TerminalSheetState extends State<_TerminalSheet> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Auto-scroll when new output arrives via state listener
    widget.state.addListener(_onStateChanged);
  }

  void _onStateChanged() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    widget.state.removeListener(_onStateChanged);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _runCommand() async {
    final cmd = _controller.text.trim();
    if (cmd.isEmpty) return;

    _controller.clear();

    // Execute command and stream output (handled globally by AppState)
    await widget.state.executeCommand(cmd);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        return Container(
          decoration: BoxDecoration(
            color: LexonaTheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(LexonaTheme.radiusLg)),
            border: Border.all(color: LexonaTheme.surfaceBorder),
          ),
          child: DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.3,
            maxChildSize: 0.95,
            expand: false,
            builder: (context, scrollCtrl) {
              return Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  children: [
                    // Handle bar
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: LexonaTheme.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),

                    // Header
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.terminal,
                            size: 18,
                            color: LexonaTheme.primaryText,
                          ),
                          const SizedBox(width: 8),
                          Text('Terminal', style: LexonaTheme.subheading),
                          const Spacer(),
                          // Stop Command Button
                          IconButton(
                            icon: Icon(
                              Icons.stop_circle_rounded,
                              color: LexonaTheme.error,
                              size: 20,
                            ),
                            onPressed: () {
                              widget.state.interruptCommand();
                              widget.state.appendTerminalOutput(
                                '\n^C (Command interrupted)\n',
                              );
                            },
                            tooltip: 'Interrupt command (Ctrl+C)',
                            splashRadius: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            widget.state.isProotTerminal
                                ? 'compat · Debian PRoot'
                                : widget.state.hasRoot
                                ? 'chroot · ${_distroLabel(widget.state.installedDistro)}'
                                : 'native · Termux/TUR',
                            style: LexonaTheme.monoSm,
                          ),
                        ],
                      ),
                    ),

                    Divider(color: LexonaTheme.surfaceBorder, height: 1),

                    // Output viewport: terminal/log view on the background colour.
                    Expanded(
                      child: Container(
                        color: LexonaTheme.background,
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(12),
                          itemCount: widget.state.terminalOutput.length,
                          itemBuilder: (context, index) {
                            final line = widget.state.terminalOutput[index];
                            final isCommand = line.startsWith('\$');
                            return SelectableText(
                              line,
                              style: LexonaTheme.monoSm.copyWith(
                                color: isCommand
                                    ? LexonaTheme.primaryText
                                    : LexonaTheme.textSecondary,
                                height: 1.4,
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                    // Input Bar
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 8, 8, 16),
                      decoration: BoxDecoration(
                        color: LexonaTheme.surface,
                        border: Border(
                          top: BorderSide(color: LexonaTheme.surfaceBorder),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            '\$ ',
                            style: LexonaTheme.mono.copyWith(
                              color: LexonaTheme.primaryText,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              style: LexonaTheme.mono.copyWith(
                                fontSize: 13,
                                color: LexonaTheme.textPrimary,
                              ),
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                hintText: 'Enter command...',
                                hintStyle: TextStyle(color: LexonaTheme.textMuted),
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              onSubmitted: (_) => _runCommand(),
                              autofocus: true,
                            ),
                          ),
                          IconButton(
                            onPressed: _runCommand,
                            icon: const Icon(Icons.send_rounded, size: 20),
                            color: LexonaTheme.primaryText,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  String _distroLabel(String distro) {
    switch (distro) {
      case 'ubuntu-chroot':
        return 'Ubuntu 24.04';
      case 'termux-native':
        return 'Termux';
      default:
        return distro;
    }
  }
}

// ── Small Action Card widget ──

/// A short result line at the bottom; errors get the 1 px error border (design language).
void _notice(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(text),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LexonaTheme.radiusMd),
        side: BorderSide(color: error ? LexonaTheme.error : LexonaTheme.border),
      ),
    ),
  );
}

/// Stop server with visible progress (the card's spinner) and a result line.
Future<void> _stopServer(BuildContext context, AppState state) async {
  final ended = await state.stopLinux();
  if (!context.mounted) return;
  if (ended < 0) {
    _notice(context, 'Linux could not be stopped', error: true);
  } else {
    _notice(context, ended > 0 ? 'Linux stopped ($ended programs ended)' : 'Linux stopped');
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Gradient? gradient;
  final VoidCallback onTap;

  /// Shown while this card's action runs: spinner instead of the chevron, taps ignored.
  final String? busyText;

  /// An asset image (an app's own logo) instead of the icon.
  final String? image;

  const _ActionCard({
    required this.icon,
    this.image,
    required this.title,
    required this.subtitle,
    required this.color,
    this.gradient,
    required this.onTap,
    this.busyText,
  });

  @override
  Widget build(BuildContext context) {
    final busy = busyText != null;
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          // Opaque card; the highlighted (main) action gets a teal 1 px border.
          color: LexonaTheme.surface,
          borderRadius: BorderRadius.circular(LexonaTheme.radiusMd),
          border: Border.all(
            color: gradient != null ? LexonaTheme.primary : LexonaTheme.border,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: LexonaTheme.surfaceRaised,
                borderRadius: BorderRadius.circular(LexonaTheme.radiusSm),
              ),
              child: image != null
                  ? Padding(padding: const EdgeInsets.all(8), child: Image.asset(image!))
                  : Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: LexonaTheme.subheading),
                  Text(
                    busyText ?? subtitle,
                    style: busy ? LexonaTheme.caption.copyWith(color: color) : LexonaTheme.caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (busy)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            else
              Icon(Icons.chevron_right_rounded, color: LexonaTheme.textMuted),
          ],
        ),
      ),
    );
  }
}
