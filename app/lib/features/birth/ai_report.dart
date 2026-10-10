import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/widgets/kid_dialogs.dart';
import '../../data/app_state.dart';
import '../../data/backend/backend_api.dart';

/// One report of an AI-suggested name / move name (Google Play AI-generated
/// content policy). Always logged on the device; sent to the server
/// (`reportAiSuggestion`) when the parent allowed cloud judging and the
/// server is reachable, otherwise kept and retried with the next report.
class AiReportEntry {
  const AiReportEntry({
    required this.kind,
    required this.text,
    required this.reason,
    required this.atMs,
    this.sent = false,
  });

  final AiSuggestionKind kind;
  final String text;
  final AiReportReason reason;
  final int atMs;
  final bool sent;

  AiReportEntry markSent() => AiReportEntry(
    kind: kind,
    text: text,
    reason: reason,
    atMs: atMs,
    sent: true,
  );

  Map<String, Object?> toJson() => {
    'kind': kind.code,
    'text': text,
    'reason': reason.code,
    'atMs': atMs,
    'sent': sent,
  };

  static AiReportEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final kind = AiSuggestionKind.values
        .where((k) => k.code == raw['kind'])
        .firstOrNull;
    final reason = AiReportReason.values
        .where((r) => r.code == raw['reason'])
        .firstOrNull;
    final text = raw['text'];
    if (kind == null || reason == null || text is! String) return null;
    return AiReportEntry(
      kind: kind,
      text: text,
      reason: reason,
      atMs: (raw['atMs'] as num?)?.toInt() ?? 0,
      sent: raw['sent'] == true,
    );
  }
}

/// Local log of AI-suggestion reports (newest 100 kept).
abstract interface class AiReportStore {
  Future<List<AiReportEntry>> load();
  Future<void> save(List<AiReportEntry> entries);
}

class MemoryAiReportStore implements AiReportStore {
  List<AiReportEntry> entries = [];
  @override
  Future<List<AiReportEntry>> load() async => List.of(entries);
  @override
  Future<void> save(List<AiReportEntry> e) async => entries = List.of(e);
}

/// `<documents>/ai_reports.json`.
class FileAiReportStore implements AiReportStore {
  FileAiReportStore(Directory dir)
    : _file = File('${dir.path}/ai_reports.json');
  final File _file;

  @override
  Future<List<AiReportEntry>> load() async {
    try {
      final raw = jsonDecode(await _file.readAsString());
      return [
        for (final e in (raw as List?) ?? const []) ?AiReportEntry.fromJson(e),
      ];
    } on Object {
      return [];
    }
  }

  @override
  Future<void> save(List<AiReportEntry> entries) async {
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode([for (final e in entries) e.toJson()]));
    await tmp.rename(_file.path);
  }
}

final aiReportStoreProvider = Provider<AiReportStore>(
  (_) => MemoryAiReportStore(),
);

/// Logs the report locally, then sends every unsent report if allowed.
/// Returns true when this report reached the server.
Future<bool> reportAiSuggestion(
  WidgetRef ref,
  AiSuggestionKind kind,
  String text,
  AiReportReason reason,
) async {
  final store = ref.read(aiReportStoreProvider);
  final entries = [
    ...await store.load(),
    AiReportEntry(
      kind: kind,
      text: text,
      reason: reason,
      atMs: ref.read(clockProvider)().millisecondsSinceEpoch,
    ),
  ];
  final settings = await ref.read(settingsProvider.future);
  final backend = ref.read(backendApiProvider);
  if (settings.consents.cloudJudge && backend.isAvailable) {
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      if (e.sent) continue;
      try {
        await backend.reportAiSuggestion(e.kind, e.text, e.reason);
        entries[i] = e.markSent();
      } on BackendException {
        break; // offline: keep the rest for later
      }
    }
  }
  final kept = entries.length > 100
      ? entries.sublist(entries.length - 100)
      : entries;
  await store.save(kept);
  return kept.last.sent;
}

/// Bottom sheet: pick the AI suggestion and a preset reason. Returns the
/// reported (kind, text) or null when cancelled.
Future<(AiSuggestionKind, String)?> showAiReportSheet(
  BuildContext context,
  WidgetRef ref,
  List<(AiSuggestionKind, String)> suggestions,
) async {
  if (suggestions.isEmpty) return null;
  final target = suggestions.length == 1
      ? suggestions.single
      : await showModalBottomSheet<(AiSuggestionKind, String)>(
          context: context,
          showDragHandle: true,
          builder: (context) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                const _SheetTitle('どの ことばが いやだった？'),
                for (final s in suggestions)
                  ListTile(
                    key: Key('ai-report-target-${s.$2}'),
                    minTileHeight: 56,
                    leading: Icon(
                      s.$1 == AiSuggestionKind.name
                          ? Icons.badge
                          : Icons.flash_on,
                    ),
                    title: Text(s.$2, style: const TextStyle(fontSize: 20)),
                    onTap: () => Navigator.of(context).pop(s),
                  ),
              ],
            ),
          ),
        );
  if (target == null || !context.mounted) return null;
  final reason = await showModalBottomSheet<AiReportReason>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          _SheetTitle('「${target.$2}」は どうして いやだった？'),
          for (final r in AiReportReason.values)
            ListTile(
              key: Key('ai-report-${r.code}'),
              minTileHeight: 56,
              title: Text(r.label, style: const TextStyle(fontSize: 20)),
              onTap: () => Navigator.of(context).pop(r),
            ),
        ],
      ),
    ),
  );
  if (reason == null || !context.mounted) return null;
  await reportAiSuggestion(ref, target.$1, target.$2, reason);
  if (context.mounted) {
    await showKidMessage(
      context,
      'おしえて くれて ありがとう！ この ことばは もう ださないよ',
      icon: Icons.flag,
    );
  }
  return target;
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
    ),
  );
}
