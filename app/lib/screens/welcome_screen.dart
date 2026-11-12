import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:droiddesk/theme/lexona_theme.dart';
import 'package:droiddesk/state/app_state.dart';
import 'package:droiddesk/screens/setup/setup_progress.dart';
import 'package:droiddesk/widgets/linux_language_picker.dart';

/// Welcome screen — first thing the user sees.
/// Premium, animated landing with the DroidDesk brand.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LexonaTheme.backgroundGradient,
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
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
                ),
                const Spacer(flex: 2),

                // ── Logo / Icon ──
                Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: Image.asset(
                          'assets/icons/logo.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    )
                    .animate()
                    .scale(
                      begin: const Offset(0.9, 0.9),
                      duration: 350.ms,
                      curve: Curves.easeOut,
                    )
                    .fadeIn(duration: 400.ms),

                const SizedBox(height: 32),

                // ── Title ──
                Text(
                      'Lexona',
                      style: LexonaTheme.display,
                    )
                    .animate()
                    .fadeIn(delay: 200.ms, duration: 500.ms)
                    .slideY(
                      begin: 0.3,
                      duration: 500.ms,
                      curve: Curves.easeOut,
                    ),

                const SizedBox(height: 12),

                // ── Tagline ──
                Text(
                      'Linux experience on Android',
                      style: LexonaTheme.bodyLg,
                    )
                    .animate()
                    .fadeIn(delay: 400.ms, duration: 500.ms)
                    .slideY(
                      begin: 0.3,
                      duration: 500.ms,
                      curve: Curves.easeOut,
                    ),

                const SizedBox(height: 8),

                Text(
                  'Debian · XFCE desktop · Single app',
                  style: LexonaTheme.caption.copyWith(
                    color: LexonaTheme.primaryText,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.5,
                  ),
                ).animate().fadeIn(delay: 600.ms, duration: 500.ms),

                const Spacer(flex: 1),

                // ── Feature chips ──
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children:
                      [
                            _featureChip(
                              Icons.storage_rounded,
                              'Containerized',
                            ),
                            _featureChip(
                              Icons.security_rounded,
                              'Root optional',
                            ),
                            _featureChip(
                              Icons.desktop_mac_rounded,
                              'Linux desktop',
                            ),
                            _featureChip(
                              Icons.offline_bolt_rounded,
                              'Local execution',
                            ),
                          ]
                          .animate(interval: 100.ms)
                          .fadeIn(delay: 800.ms, duration: 400.ms)
                          .slideX(begin: -0.1, duration: 400.ms),
                ),

                const Spacer(flex: 2),

                // ── Language of the Linux apps (set up by the install) ──
                const LinuxLanguagePicker(),
                const SizedBox(height: 16),

                // ── Get Started Button ──
                SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            PageRouteBuilder(
                              pageBuilder:
                                  (context, animation, secondaryAnimation) =>
                                      // The fork supports XFCE only (dock, Android menu,
                                      // USB disky and tweaks are built for it).
                                      const SetupProgressScreen(),
                              transitionsBuilder:
                                  (
                                    context,
                                    animation,
                                    secondaryAnimation,
                                    child,
                                  ) {
                                    return FadeTransition(
                                      opacity: animation,
                                      child: SlideTransition(
                                        position:
                                            Tween<Offset>(
                                              begin: const Offset(0, 0.05),
                                              end: Offset.zero,
                                            ).animate(
                                              CurvedAnimation(
                                                parent: animation,
                                                curve: Curves.easeOut,
                                              ),
                                            ),
                                        child: child,
                                      ),
                                    );
                                  },
                              transitionDuration: const Duration(
                                milliseconds: 400,
                              ),
                            ),
                          );
                        },
                        // Teal fill and onPrimary text come from the theme.
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('Set up desktop essentials'),
                            const SizedBox(width: 8),
                            const Icon(Icons.arrow_forward_rounded, size: 20),
                          ],
                        ),
                      ),
                    )
                    .animate()
                    .fadeIn(delay: 1200.ms, duration: 500.ms)
                    .slideY(
                      begin: 0.3,
                      duration: 500.ms,
                      curve: Curves.easeOut,
                    ),

                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _featureChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: LexonaTheme.surfaceRaised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: LexonaTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: LexonaTheme.primaryText),
          const SizedBox(width: 6),
          Text(
            label,
            style: LexonaTheme.caption.copyWith(
              color: LexonaTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
