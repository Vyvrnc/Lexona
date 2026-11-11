import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:droiddesk/theme/lexona_theme.dart';
import 'package:droiddesk/state/app_state.dart';
import 'package:droiddesk/services/platform_bridge.dart';
import 'package:droiddesk/widgets/linux_language_picker.dart';

class DEInstallScreen extends StatefulWidget {
  const DEInstallScreen({super.key});

  @override
  State<DEInstallScreen> createState() => _DEInstallScreenState();
}


class _DEInstallScreenState extends State<DEInstallScreen> {
  bool _started = false;
  String? _language;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // The language comes first: the install sets it up in Debian.
    DroidDeskPlatform.getDesktopLanguage().then((locale) {
      if (!mounted) return;
      setState(() => _language = linuxLanguages.containsKey(locale) ? locale : 'en_US.UTF-8');
    });
  }

  Future<void> _startInstall() async {
    if (_started) return;
    final language = _language;
    if (language != null) await DroidDeskPlatform.setDesktopLanguage(language);
    if (!mounted) return;
    setState(() => _started = true);
    context.read<AppState>().installDesktopEnvironment();
  }

  Widget _buildLanguageStep() {
    return Scaffold(
      backgroundColor: LexonaTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Language',
                style: LexonaTheme.title,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Language of the Linux apps: Firefox, LibreOffice, Claude Code and the '
                'terminal tools. The XFCE desktop itself stays in English.',
                style: LexonaTheme.body,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Expanded(
                child: _language == null
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        children: [
                          for (final entry in linuxLanguages.entries)
                            RadioListTile<String>(
                              value: entry.key,
                              groupValue: _language,
                              onChanged: (value) => setState(() => _language = value),
                              title: Text(
                                entry.value,
                                style: LexonaTheme.body.copyWith(color: LexonaTheme.textPrimary),
                              ),
                              activeColor: LexonaTheme.primary,
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _language == null ? null : _startInstall,
                // Teal fill and onPrimary text come from the theme.
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: const Text('Start installation'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _launchUrl() async {
    final url = Uri.parse('https://www.youtube.com/orailnoor');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_started) return _buildLanguageStep();
    final state = context.watch<AppState>();

    // Auto-scroll terminal
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });

    final isDone = state.isDEInstalled;
    final hasError = state.errorMessage != null;

    return Scaffold(
      backgroundColor: LexonaTheme.background,
      body: Stack(
        children: [
          // Background: the theme's screen colour (dark and light).
          Positioned.fill(
            child: Container(
              color: LexonaTheme.background,
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Header ──
                  Text(
                    isDone
                        ? 'Installation complete'
                        : hasError
                        ? 'Installation failed'
                        : 'Configuring\nLinux workstation',
                    style: LexonaTheme.title,
                    textAlign: TextAlign.center,
                  ).animate().fadeIn(duration: 500.ms).slideY(begin: -0.2),

                  const SizedBox(height: 8),
                  Text(
                    isDone
                        ? 'Your Linux environment is ready.'
                        : 'Downloading and configuring system packages.',
                    style: LexonaTheme.body,
                    textAlign: TextAlign.center,
                  ).animate().fadeIn(delay: 200.ms),

                  const Spacer(flex: 1),

                  // ── Terminal Output Window ──
                  if (!isDone)
                    Expanded(
                      flex: 3,
                      child: Container(
                        decoration: BoxDecoration(
                          // Terminal/log view: opaque background colour, 1 px border.
                          color: LexonaTheme.background,
                          borderRadius: BorderRadius.circular(LexonaTheme.radiusMd),
                          border: Border.all(color: LexonaTheme.border),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(LexonaTheme.radiusMd),
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(12),
                            itemCount: state.terminalOutput.length,
                            itemBuilder: (context, index) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Text(
                                  state.terminalOutput[index],
                                  style: LexonaTheme.monoSm.copyWith(
                                    color: LexonaTheme.textSecondary,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ).animate().fadeIn(delay: 400.ms),

                  const SizedBox(height: 24),

                  // ── Progress Bar ──
                  if (!isDone && !hasError)
                    Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: state.extractProgress.clamp(0.0, 1.0),
                            backgroundColor: LexonaTheme.surfaceRaised,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              LexonaTheme.primary,
                            ),
                            minHeight: 8,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          state.extractStatus.isNotEmpty
                              ? state.extractStatus
                              : 'Extracting packages...',
                          style: LexonaTheme.monoSm.copyWith(
                            color: LexonaTheme.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),

                  // ── Completion / Error Buttons ──
                  if (isDone)
                    ElevatedButton(
                      onPressed: () {
                        state.refreshStatus();
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      child: const Text('Return to home'),
                    ).animate().fadeIn(duration: 350.ms).scale(
                      begin: const Offset(0.95, 0.95),
                      curve: Curves.easeOut,
                      duration: 350.ms,
                    ),

                  if (hasError)
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      // Going back is not destructive: the screen's one teal button.
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      child: const Text('Go back'),
                    ),

                  const Spacer(flex: 1),

                  // ── Footer ──
                  if (!isDone)
                    Center(
                      child: OutlinedButton.icon(
                        onPressed: _launchUrl,
                        icon: const Icon(
                          Icons.code_rounded,
                          size: 18,
                        ),
                        // Teal outline and teal text come from the theme.
                        label: const Text('Support open source'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
