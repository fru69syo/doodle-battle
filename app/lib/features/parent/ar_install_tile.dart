import 'package:flutter/material.dart';

import '../ar/ar.dart';

/// Lets a parent (already past the gate) install Google Play Services for
/// AR. Children never see this prompt (SPEC §10).
class ArInstallTile extends StatefulWidget {
  const ArInstallTile({super.key});

  @override
  State<ArInstallTile> createState() => _ArInstallTileState();
}

class _ArInstallTileState extends State<ArInstallTile> {
  String? _status;
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    final support = await checkArSupport();
    String status;
    switch (support) {
      case ArSupport.supported:
        status = 'この端末ではすでに AR が使えます。';
      case ArSupport.unsupported:
      case ArSupport.unknown:
        status = 'この端末は ARCore に対応していないため、「かんたん AR」で遊べます。';
      case ArSupport.needsInstall:
        final r = await requestArCoreInstall();
        status = switch (r) {
          ArInstallResult.installed => 'AR の準備ができました。',
          ArInstallResult.requested => 'Play ストアでインストールを完了してください。',
          ArInstallResult.declined => 'インストールは行いませんでした（「かんたん AR」で遊べます）。',
          ArInstallResult.error => 'インストールを開始できませんでした。',
        };
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = status;
    });
  }

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.view_in_ar),
    title: const Text('AR の準備'),
    subtitle: Text(
      _status ??
          '対応端末では「Google Play 開発者サービス for AR」を入れると、床や机にキャラを置けます'
              '（Play ストアが開きます）。',
    ),
    trailing: _busy
        ? const CircularProgressIndicator()
        : OutlinedButton(
            key: const Key('ar-install'),
            onPressed: _run,
            child: const Text('確認'),
          ),
  );
}
