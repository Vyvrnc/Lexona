import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:droiddesk/theme/lexona_theme.dart';
import 'package:droiddesk/state/app_state.dart';
import 'package:droiddesk/services/platform_bridge.dart';

/// Android 12+ stops an app's oldest child processes once all apps together run more than 32
/// ("phantom processes"). Two ways out: turn the limit off (Developer options, Wireless
/// debugging from the phone itself, or adb from a computer), or run a leaner desktop.
class ProcessLimitScreen extends StatefulWidget {
  const ProcessLimitScreen({super.key});

  @override
  State<ProcessLimitScreen> createState() => _ProcessLimitScreenState();
}

class _ProcessLimitScreenState extends State<ProcessLimitScreen> with WidgetsBindingObserver {
  static const _adb =
      'adb shell settings put global settings_enable_monitor_phantom_procs false\n'
      'adb shell device_config set_sync_disabled_for_tests persistent\n'
      'adb shell device_config put activity_manager max_phantom_processes 2147483647';

  Map<String, dynamic> _status = {};
  List<Map<String, dynamic>> _lean = [];
  bool _leanChanged = false;

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
    // Back from Settings or from the terminal: the limit may be off now.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final status = await DroidDeskPlatform.phantomStatus();
    final lean = await DroidDeskPlatform.getLeanOptions();
    if (!mounted) return;
    setState(() {
      _status = status;
      _lean = lean;
    });
    context.read<AppState>().refreshStatus();
  }

  @override
  Widget build(BuildContext context) {
    final limitOn = _status['limitOn'] == true;
    final processes = _status['processes'] is int ? _status['processes'] as int : -1;
    final devOn = _status['developerOptions'] == true;

    return Scaffold(
      backgroundColor: LexonaTheme.background,
      appBar: AppBar(
        backgroundColor: LexonaTheme.background,
        foregroundColor: LexonaTheme.textPrimary,
        elevation: 0,
        title: const Text('Process limit'),
      ),
      body: ListView(
        // Edge to edge: keep the last button above the navigation bar.
        padding: EdgeInsets.fromLTRB(24, 8, 24, 32 + MediaQuery.of(context).viewPadding.bottom),
        children: [
          _card(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(limitOn ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded,
                    color: limitOn ? LexonaTheme.warning : LexonaTheme.success),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(limitOn ? 'The limit is on' : 'The limit is off',
                      style: LexonaTheme.heading),
                ),
              ]),
              const SizedBox(height: 12),
              Text(
                'Android 12 and newer stop the oldest programs of apps once all apps together run '
                'more than 32 of them. Lexona\'s desktop is such a set of programs; a browser or a '
                'few terminals on top are enough for Android to close Linux programs every few '
                'minutes.',
                style: LexonaTheme.body.copyWith(color: LexonaTheme.textSecondary),
              ),
              if (processes >= 0) ...[
                const SizedBox(height: 12),
                Text('Lexona runs $processes Linux programs now.',
                    style: LexonaTheme.body.copyWith(
                        color: processes > 24 && limitOn ? LexonaTheme.warning : LexonaTheme.textPrimary)),
              ],
            ],
          )),
          const SizedBox(height: 16),
          Text('Turn the limit off', style: LexonaTheme.subheading),
          const SizedBox(height: 8),
          _card(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('1. In Developer options (Android 14 and newer)', style: LexonaTheme.subheading),
              const SizedBox(height: 6),
              Text(
                devOn
                    ? 'Turn on "Disable child process restrictions". On some Samsung phones this '
                        'switch alone is not enough; if the warning stays, use step 2.'
                    : 'Developer options are off. Turn them on by tapping Build number 7 times '
                        '(About phone > Software information), then turn on "Disable child '
                        'process restrictions".',
                style: LexonaTheme.body.copyWith(color: LexonaTheme.textSecondary),
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: () => DroidDeskPlatform.openDeveloperOptions(),
                child: Text(devOn ? 'Open Developer options' : 'Open About phone'),
              ),
              Divider(height: 32, color: LexonaTheme.border),
              Text('2. Without a computer (Wireless debugging)', style: LexonaTheme.subheading),
              const SizedBox(height: 6),
              Text(
                'Lexona pairs with the phone over Wireless debugging and sets the limit off, as '
                'adb from a computer would. Needs Wi-Fi and Developer options; the terminal '
                'guides you. Undo: lexona-unlimit --undo.',
                style: LexonaTheme.body.copyWith(color: LexonaTheme.textSecondary),
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: () => DroidDeskPlatform.openTerminal('unlimit'),
                child: const Text('Start in the terminal'),
              ),
              Divider(height: 32, color: LexonaTheme.border),
              Text('3. From a computer', style: LexonaTheme.subheading),
              const SizedBox(height: 6),
              SelectableText(_adb, style: LexonaTheme.mono.copyWith(fontSize: 12)),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  Clipboard.setData(const ClipboardData(text: _adb));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Commands copied')),
                  );
                },
                child: const Text('Copy commands'),
              ),
            ],
          )),
          if (_lean.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Or run a leaner desktop', style: LexonaTheme.subheading),
            const SizedBox(height: 4),
            Text(
              'Parts of the desktop that most people do not need on Android. Each one off means '
              'fewer programs. Applies when the desktop starts next time.',
              style: LexonaTheme.caption.copyWith(color: LexonaTheme.textSecondary),
            ),
            const SizedBox(height: 8),
            _card(Column(
              children: [
                for (var i = 0; i < _lean.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: LexonaTheme.border),
                  _leanRow(_lean[i]),
                ],
              ],
            )),
            if (_leanChanged) ...[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () async {
                  final ok = await context.read<AppState>().restartDesktop();
                  if (!mounted) return;
                  setState(() => _leanChanged = !ok);
                  _refresh();
                },
                child: const Text('Restart the desktop now'),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _leanRow(Map<String, dynamic> option) {
    final saves = option['processes'] is int ? option['processes'] as int : 0;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      // On = the part runs, as everywhere else in Android; off saves its programs.
      value: option['off'] != true,
      title: Text(option['title']?.toString() ?? '', style: LexonaTheme.body),
      subtitle: Text(
        '${option['detail'] ?? ''}${saves > 0 ? '\nOff: $saves fewer program${saves == 1 ? '' : 's'}' : ''}',
        style: LexonaTheme.caption.copyWith(color: LexonaTheme.textSecondary),
      ),
      onChanged: (on) async {
        await DroidDeskPlatform.setLeanOption(option['id'].toString(), !on);
        if (!mounted) return;
        setState(() => _leanChanged = true);
        _refresh();
      },
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
