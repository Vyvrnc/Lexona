import 'package:flutter/material.dart';
import 'package:droiddesk/theme/lexona_theme.dart';
import 'package:droiddesk/services/platform_bridge.dart';

/// Advanced: optional features for power users. Most need Shizuku (shell rights without a
/// computer); without it the screen only explains how to get it.
class AdvancedScreen extends StatefulWidget {
  const AdvancedScreen({super.key});

  @override
  State<AdvancedScreen> createState() => _AdvancedScreenState();
}

class _AdvancedScreenState extends State<AdvancedScreen> with WidgetsBindingObserver {
  String _shizuku = 'missing';
  bool _busy = false;
  String? _dataMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the Shizuku app: it may run now.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final shizuku = await DroidDeskPlatform.shizukuState();
    if (!mounted) return;
    setState(() => _shizuku = shizuku);
  }

  @override
  Widget build(BuildContext context) {
    final granted = _shizuku == 'granted';
    return Scaffold(
      backgroundColor: LexonaTheme.background,
      appBar: AppBar(
        backgroundColor: LexonaTheme.background,
        foregroundColor: LexonaTheme.textPrimary,
        elevation: 0,
        title: const Text('Advanced'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(24, 8, 24, 32 + MediaQuery.of(context).viewPadding.bottom),
        children: [
          _card(_shizukuCard()),
          const SizedBox(height: 16),
          _card(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Android data in the file manager', style: LexonaTheme.subheading),
              const SizedBox(height: 6),
              Text(
                'Android/data and Android/obb (files of other apps, games\' data) open in the '
                'desktop\'s file manager: Thunar shows them as "Android data". Lasts until the '
                'phone restarts.',
                style: LexonaTheme.body.copyWith(color: LexonaTheme.textSecondary),
              ),
              if (_dataMessage != null) ...[
                const SizedBox(height: 6),
                Text(_dataMessage!, style: LexonaTheme.caption.copyWith(color: LexonaTheme.textSecondary)),
              ],
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: !granted || _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        final out = await DroidDeskPlatform.androidDataStart();
                        if (!mounted) return;
                        final url = RegExp(r'dav://\S+').firstMatch(out)?.group(0);
                        setState(() {
                          _busy = false;
                          _dataMessage = url != null
                              ? 'Ready: "Android data" in Thunar\'s side panel, or $url'
                              : 'Did not start: ${out.trim().split('\n').last}';
                        });
                      },
                child: const Text('Show Android data'),
              ),
            ],
          )),
        ],
      ),
    );
  }

  Widget _shizukuCard() {
    final text = switch (_shizuku) {
      'missing' => 'These features need Shizuku, an app that gives Lexona shell rights without '
          'a computer. Install a maintained one, for example Shizuku-Next, and start it.',
      'stopped' => 'Shizuku is installed but not running. Start it in the Shizuku app, then come back.',
      'denied' => 'Lexona needs your permission in Shizuku once.',
      'old' => 'This Shizuku is too old. Install a maintained one, for example Shizuku-Next.',
      _ => 'Shizuku is running and allows Lexona.',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(_shizuku == 'granted' ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
              color: _shizuku == 'granted' ? LexonaTheme.success : LexonaTheme.textSecondary),
          const SizedBox(width: 10),
          Expanded(child: Text('Shizuku', style: LexonaTheme.subheading)),
        ]),
        const SizedBox(height: 6),
        Text(text, style: LexonaTheme.body.copyWith(color: LexonaTheme.textSecondary)),
        if (_shizuku == 'denied') ...[
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    await DroidDeskPlatform.shizukuRequest();
                    _busy = false;
                    _refresh();
                  },
            child: const Text('Allow in Shizuku'),
          ),
        ],
      ],
    );
  }

  Widget _card(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: LexonaTheme.surface,
          borderRadius: BorderRadius.circular(LexonaTheme.radiusMd),
          border: Border.all(color: LexonaTheme.border),
        ),
        child: child,
      );
}
