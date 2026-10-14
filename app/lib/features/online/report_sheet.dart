import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/widgets/kid_dialogs.dart';
import '../../data/backend/backend_api.dart';

/// Asks why the child wants to report the opponent (preset reasons only, no
/// free text; SPEC §9.4). Null when the sheet was closed.
Future<ReportReason?> pickReportReason(BuildContext context) =>
    showModalBottomSheet<ReportReason>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'どうして いやだった？',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
            ),
            for (final r in ReportReason.values)
              ListTile(
                key: Key('report-${r.code}'),
                minTileHeight: 56,
                title: Text(r.label, style: const TextStyle(fontSize: 20)),
                onTap: () => Navigator.of(context).pop(r),
              ),
          ],
        ),
      ),
    );

/// Thanks the child for a report (also when it is sent later).
Future<void> showReportThanks(BuildContext context) =>
    showKidMessage(context, 'おしえて くれて ありがとう！ おとなの ひとが たしかめるよ');

/// Report the opponent with a preset reason, right away (SPEC §9.4).
Future<void> showReportSheet(
  BuildContext context,
  WidgetRef ref,
  String snapshotId,
) async {
  final reason = await pickReportReason(context);
  if (reason == null || !context.mounted) return;
  try {
    await ref.read(backendApiProvider).reportCharacter(snapshotId, reason);
    if (context.mounted) await showReportThanks(context);
  } on BackendException {
    if (context.mounted) {
      await showKidMessage(context, 'いまは おくれなかったよ。あとで また ためしてね');
    }
  }
}
