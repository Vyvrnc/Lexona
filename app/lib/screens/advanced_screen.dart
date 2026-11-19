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
    final switches = await DroidDeskPlatform.shellSwitches();
    if (!mounted) return;
    setState(() {
      _shizuku = shizuku;
      _switches = switches;
    });
    if (shizuku == 'granted') {
      final bg = await DroidDeskPlatform.shizukuBackground();
      if (!mounted) return;
      setState(() => _background = bg['state'] as String? ?? 'unknown');
      _loadApps();
    }
  }

  // ── Android apps while on Linux (Gitea #10) ──
  bool _psEnabled = false;
  bool _psLoading = false;
  List<Map<String, dynamic>> _psApps = [];
  final Set<String> _psStopping = {};

  Future<void> _loadApps() async {
    if (_psLoading) return;
    setState(() => _psLoading = true);
    final r = await DroidDeskPlatform.powerSave();
    if (!mounted) return;
    setState(() {
      _psLoading = false;
      _psEnabled = r['enabled'] as bool? ?? false;
      _psApps = ((r['apps'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    });
  }

  Widget _powerSaveCard(bool granted) {
    final total = _psApps.fold<int>(0, (sum, a) => sum + (a['mb'] as int? ?? 0));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Android apps while on Linux', style: LexonaTheme.subheading),
        const SizedBox(height: 6),
        Text(
          'Apps you also use on the desktop (Slack, Gmail, Element…) take memory on Android too. '
          'Pick them below: while the desktop runs they are stopped and may not run in the '
          'background, so they free memory and send no notifications. When the desktop stops, '
          'they get their earlier setting back, also after Lexona was closed.',
          style: LexonaTheme.body.copyWith(color: LexonaTheme.textSecondary),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _psEnabled,
          onChanged: !granted && !_psEnabled
              ? null
              : (on) async {
                  setState(() => _psEnabled = on);
                  await DroidDeskPlatform.powerSaveSet(enabled: on);
                },
          title: Text('Put the picked apps to sleep while the desktop runs', style: LexonaTheme.body),
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                _psApps.isEmpty
                    ? (_psLoading ? 'Reading running apps…' : 'Running apps appear here.')
                    : 'Running now: ${_psApps.length} apps, $total MB',
                style: LexonaTheme.caption.copyWith(color: LexonaTheme.textSecondary),
              ),
            ),
            if (_psLoading)
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            else
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: granted ? _loadApps : null,
              ),
          ],
        ),
        for (final a in _psApps) _appRow(a, granted),
      ],
    );
  }

  Widget _appRow(Map<String, dynamic> a, bool granted) {
    final pkg = a['package'] as String;
    final selected = a['selected'] as bool? ?? false;
    final sleeping = a['sleeping'] as bool? ?? false;
    return Row(
      children: [
        Checkbox(
          value: selected,
          onChanged: !granted
              ? null
              : (on) async {
                  setState(() => a['selected'] = on ?? false);
                  await DroidDeskPlatform.powerSaveSet(package: pkg, selected: on ?? false);
                },
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(a['label'] as String? ?? pkg, style: LexonaTheme.body, overflow: TextOverflow.ellipsis),
              Text(
                sleeping ? '$pkg · asleep' : pkg,
                style: LexonaTheme.caption.copyWith(color: LexonaTheme.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        Text('${a['mb']} MB', style: LexonaTheme.body),
        IconButton(
          tooltip: 'Stop now',
          icon: _psStopping.contains(pkg)
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.stop_circle_outlined),
          onPressed: !granted || _psStopping.contains(pkg)
              ? null
              : () async {
                  setState(() => _psStopping.add(pkg));
                  await DroidDeskPlatform.powerSaveStop(pkg);
                  if (!mounted) return;
                  setState(() => _psStopping.remove(pkg));
                  _loadApps();
                },
        ),
      ],
    );
  }

  Map<String, bool> _switches = {};
  String _background = 'unknown';
  String? _backgroundMessage;

  static const _tools = [
    (
      'apk',
      'Install apps from Linux',
      'lexona-apk-install app.apk, or "Install on Android" on an .apk file in the file manager. '
          'Installs without asking, also split APKs (.apks, .xapk).',
    ),
    ('logcat', 'Android logs', 'lexona-logcat: the logs of every app, as adb logcat.'),
    (
      'screen',
      'Screen and input',
      'lexona-screenshot takes a picture of the phone\'s screen, lexona-input taps, swipes and types '
          'as adb shell input.',
    ),
    (
      'adb',
      'Full Android shell',
      'lexona-adb: a shell as the adb user, or one command. Any program in Linux can then do '
          'what adb can: install and remove apps, change settings, read other apps\' logs. '
          'Turn it on only while you need it.',
    ),
  ];

  Widget _toolsCard(bool granted) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Linux tools with Android shell rights', style: LexonaTheme.subheading),
        const SizedBox(height: 6),
        Text(
          'Commands for the terminal and the desktop. Each group stays off until you turn it on; '
          'programs in Linux run as Lexona, so whatever you allow here, they all may do.',
          style: LexonaTheme.body.copyWith(color: LexonaTheme.textSecondary),
        ),
        for (final t in _tools)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _switches[t.$1] ?? false,
            onChanged: !granted && !(_switches[t.$1] ?? false)
                ? null
                : (on) async {
                    await DroidDeskPlatform.setShellSwitch(t.$1, on);
                    final switches = await DroidDeskPlatform.shellSwitches();
                    if (!mounted) return;
                    setState(() => _switches = switches);
                  },
            title: Text(t.$2, style: LexonaTheme.body),
            subtitle: Text(t.$3, style: LexonaTheme.caption.copyWith(color: LexonaTheme.textSecondary)),
          ),
      ],
    );
  }

  Widget _backgroundCard(bool granted) {
    final on = _background == 'unrestricted';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Keep Lexona running in the background', style: LexonaTheme.subheading),
        const SizedBox(height: 6),
        Text(
          on
              ? 'Lexona is unrestricted: Android does not put it to sleep or stop its background work.'
              : 'Android may put Lexona to sleep when the screen is off, which stops Linux programs. '
                  'One tap sets battery use to Unrestricted and allows background work.',
          style: LexonaTheme.body.copyWith(color: LexonaTheme.textSecondary),
        ),
        if (_backgroundMessage != null) ...[
          const SizedBox(height: 6),
          Text(_backgroundMessage!, style: LexonaTheme.caption.copyWith(color: LexonaTheme.textSecondary)),
        ],
        const SizedBox(height: 8),
        FilledButton.tonal(
          onPressed: !granted || _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  final r = await DroidDeskPlatform.shizukuBackground(unrestricted: !on);
                  if (!mounted) return;
                  final state = r['state'] as String? ?? 'unknown';
                  setState(() {
                    _busy = false;
                    _background = state;
                    _backgroundMessage = (state == 'unrestricted') == !on
                        ? null
                        : 'Did not work: ${(r['message'] as String? ?? '').trim().split('\n').last}';
                  });
                },
          child: Text(on ? 'Put Android\'s default back' : 'Keep Lexona running'),
        ),
      ],
    );
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
                'desktop\'s file manager: Thunar shows them as "Android data". Lasts until Lexona '
                'stops; tap again after that.',
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
          const SizedBox(height: 16),
          _card(_backgroundCard(granted)),
          const SizedBox(height: 16),
          _card(_powerSaveCard(granted)),
          const SizedBox(height: 16),
          _card(_toolsCard(granted)),
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
