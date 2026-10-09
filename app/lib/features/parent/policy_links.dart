import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';

/// Opens a URL outside the app (overridable in tests). Only used behind the
/// parental gate (おうちのひと / first-run setup).
final urlOpenerProvider = Provider<Future<bool> Function(Uri)>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// Opens [page] in the browser; tells the parent when that fails.
Future<void> openPolicyPage(
  BuildContext context,
  WidgetRef ref,
  PolicyPage page,
) async {
  var ok = false;
  try {
    ok = await ref.read(urlOpenerProvider)(page.uri);
  } on Object {
    ok = false;
  }
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('ページを開けませんでした: ${page.uri}')));
  }
}

/// List tiles for the policy / support pages (parent-facing).
class PolicyLinks extends ConsumerWidget {
  const PolicyLinks({super.key, this.pages = PolicyPage.values});

  final List<PolicyPage> pages;

  static IconData _icon(PolicyPage p) => switch (p) {
    PolicyPage.privacy => Icons.privacy_tip,
    PolicyPage.terms => Icons.gavel,
    PolicyPage.deletion => Icons.delete_outline,
    PolicyPage.support => Icons.help_outline,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    children: [
      for (final p in pages)
        ListTile(
          key: Key('policy-${p.name}'),
          leading: Icon(_icon(p)),
          title: Text(p.title),
          subtitle: Text(
            p.uri.toString(),
            style: const TextStyle(fontSize: 12),
          ),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => openPolicyPage(context, ref, p),
        ),
    ],
  );
}
