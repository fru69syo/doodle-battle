import 'package:flutter/material.dart';

/// Simple message for children with one big OK button.
Future<void> showKidMessage(
  BuildContext context,
  String message, {
  String? title,
  IconData icon = Icons.emoji_emotions,
  String okLabel = 'わかった',
}) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    icon: Icon(icon, size: 56),
    title: title == null ? null : Text(title, textAlign: TextAlign.center),
    content: Text(message, textAlign: TextAlign.center),
    actionsAlignment: MainAxisAlignment.center,
    actions: [
      FilledButton(
        key: const Key('kid-message-ok'),
        onPressed: () => Navigator.of(context).pop(),
        child: Text(okLabel),
      ),
    ],
  ),
);

/// Yes/no question for children. Returns true for [yesLabel].
Future<bool> askKid(
  BuildContext context,
  String message, {
  String? title,
  String yesLabel = 'はい',
  String noLabel = 'やめる',
  IconData icon = Icons.help_outline,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(icon, size: 56),
      title: title == null ? null : Text(title, textAlign: TextAlign.center),
      content: Text(message, textAlign: TextAlign.center),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        OutlinedButton(
          key: const Key('kid-ask-no'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(noLabel),
        ),
        FilledButton(
          key: const Key('kid-ask-yes'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(yesLabel),
        ),
      ],
    ),
  );
  return r ?? false;
}
