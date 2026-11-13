import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:droiddesk/theme/lexona_theme.dart';
import 'package:droiddesk/state/app_state.dart';

/// System updates without a terminal: runs lexona-update (Termux and Debian) and reads its
/// "LXU ..." lines. Check first, then install; existing configuration files are kept.
class SystemUpdateScreen extends StatefulWidget {
  const SystemUpdateScreen({super.key});

  @override
  State<SystemUpdateScreen> createState() => _SystemUpdateScreenState();
}

class _Pkg {
  final String side, name, from, to;
  final bool security;
  const _Pkg(this.side, this.name, this.from, this.to, this.security);
}

class _Result {
  final Map<String, int> counts = {};
  int security = 0;
  final List<_Pkg> packages = [];
  bool? ok;
  String failed = '';
  String step = '';
}

_Result _parse(String text) {
  final r = _Result();
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (!line.startsWith('LXU ')) continue;
    final p = line.split(RegExp(r'\s+'));
    switch (p.length > 1 ? p[1] : '') {
      case 'COUNT':
        if (p.length >= 4) r.counts[p[2]] = int.tryParse(p[3]) ?? 0;
      case 'SECURITY':
        if (p.length >= 4) r.security = int.tryParse(p[3]) ?? 0;
      case 'PKG':
        if (p.length >= 6) r.packages.add(_Pkg(p[2], p[3], p[4], p[5], p.length > 6 && p[6] == 'security'));
      case 'STEP':
        r.step = p.skip(2).join(' ');
      case 'DONE':
        r.ok = p.length > 2 && p[2] == 'ok';
        r.failed = p.skip(3).join(' ');
    }
  }
  return r;
}

class _SystemUpdateScreenState extends State<SystemUpdateScreen> {
  _Result? _check;
  _Result? _install;
  bool _showLog = false;

  Future<void> _run({required bool check}) async {
    final state = context.read<AppState>();
    setState(() {
      if (check) _check = null;
      _install = null;
      _showLog = !check;
    });
    final output = await state.runSystemUpdate(check: check);
    if (!mounted) return;
    final parsed = _parse('${state.systemUpdateLog}\n$output');
    setState(() {
      if (check) {
        _check = parsed;
      } else {
        _install = parsed;
        _check = null;
      }
    });
    if (!check) state.refreshStatus();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final running = state.systemUpdateRunning;
    final live = running ? _parse(state.systemUpdateLog) : null;
    final check = _check;
    final total = check == null ? 0 : (check.counts['termux'] ?? 0) + (check.counts['debian'] ?? 0);

    return Scaffold(
      backgroundColor: LexonaTheme.background,
      appBar: AppBar(
        backgroundColor: LexonaTheme.background,
        foregroundColor: LexonaTheme.textPrimary,
        elevation: 0,
        title: const Text('System updates'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(24, 8, 24, 32 + MediaQuery.of(context).viewPadding.bottom),
        children: [
          _card(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_headline(running, live, check, total), style: LexonaTheme.heading),
              const SizedBox(height: 8),
              Text(
                'Updates the Linux system: the desktop and its programs (Termux) and Debian. '
                'Security fixes come this way. Your settings are kept.',
                style: LexonaTheme.body.copyWith(color: LexonaTheme.textSecondary),
              ),
              if (running) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
              if (!running && check != null && check.ok == false) ...[
                const SizedBox(height: 12),
                Text(
                  _listsWarning(check.failed),
                  style: LexonaTheme.body.copyWith(color: LexonaTheme.warning),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(spacing: 12, runSpacing: 8, children: [
                FilledButton.tonal(
                  onPressed: running ? null : () => _run(check: true),
                  child: const Text('Check for updates'),
                ),
                if (check != null && total > 0)
                  FilledButton(
                    onPressed: running ? null : () => _run(check: false),
                    child: Text('Install $total update${total == 1 ? '' : 's'}'),
                  ),
              ]),
            ],
          )),
          if (_install != null) ...[
            const SizedBox(height: 16),
            _card(Row(children: [
              Icon(_install!.ok == true ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
                  color: _install!.ok == true ? LexonaTheme.success : LexonaTheme.error),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _install!.ok == true
                      ? 'Updates installed. Restart the desktop so running programs use them.'
                      : 'Some updates failed (${_install!.failed.isEmpty ? 'see the log' : _install!.failed}). '
                          'Check the internet connection and try again.',
                  style: LexonaTheme.body,
                ),
              ),
            ])),
            if (_install!.ok == true && state.isRunning) ...[
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: () => state.restartDesktop(),
                child: const Text('Restart the desktop'),
              ),
            ],
          ],
          if (check != null && total > 0) ...[
            const SizedBox(height: 24),
            for (final side in const ['termux', 'debian'])
              if (check.packages.any((p) => p.side == side)) ...[
                Text(side == 'termux' ? 'Desktop and programs (Termux)' : 'Debian',
                    style: LexonaTheme.subheading),
                const SizedBox(height: 8),
                _card(Column(children: [
                  for (final p in check.packages.where((p) => p.side == side))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        Expanded(child: Text(p.name, style: LexonaTheme.body)),
                        if (p.security)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text('security', style: LexonaTheme.caption.copyWith(color: LexonaTheme.warning)),
                          ),
                        Flexible(
                          child: Text('${p.from} → ${p.to}',
                              textAlign: TextAlign.right,
                              overflow: TextOverflow.ellipsis,
                              style: LexonaTheme.monoSm.copyWith(color: LexonaTheme.textSecondary)),
                        ),
                      ]),
                    ),
                ])),
                const SizedBox(height: 16),
              ],
          ],
          if (state.systemUpdateLog.isNotEmpty) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() => _showLog = !_showLog),
              child: Text(_showLog ? 'Hide details' : 'Show details'),
            ),
            if (_showLog)
              _card(SelectableText(
                _tail(state.systemUpdateLog),
                style: LexonaTheme.monoSm.copyWith(color: LexonaTheme.textSecondary),
              )),
          ],
        ],
      ),
    );
  }

  String _headline(bool running, _Result? live, _Result? check, int total) {
    if (running) return live?.step.isNotEmpty == true ? '${live!.step}…' : 'Working…';
    if (check == null) return _install == null ? 'Not checked yet' : 'Done';
    if (total == 0) return check.ok == false ? 'No updates found' : 'Everything is up to date';
    final sec = check.security > 0 ? ', ${check.security} security' : '';
    return '$total update${total == 1 ? '' : 's'} available$sec';
  }

  /// Which package server did not answer completely, in words; usually a mirror mid-sync.
  String _listsWarning(String failed) {
    final parts = <String>[
      if (failed.contains('termux')) 'the desktop and its programs (Termux)',
      if (failed.contains('debian')) 'Debian',
    ];
    final which = parts.isEmpty ? 'a package server' : 'the package server for ${parts.join(' and ')}';
    return 'Could not reach $which completely (it is often in the middle of an update, or the '
        'connection dropped). The list may be incomplete: check again in a few minutes.';
  }

  /// The last lines of the log, without the app's own LXU lines.
  String _tail(String log) {
    final lines = log.split('\n').where((l) => !l.startsWith('LXU ')).toList();
    return lines.length > 200 ? lines.sublist(lines.length - 200).join('\n') : lines.join('\n');
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
