import 'dart:async';

import 'package:flutter/material.dart';

/// Prepares guest sharing while owning only the temporary loading dialog.
///
/// The caller can belong to a page below the visible transfer page. The dialog,
/// rather than the caller's route, must still be current before sharing can
/// continue. Back, navigation, or disposal cancels displaying the final QR.
Future<bool> runGuestQrPreparation({
  required BuildContext context,
  required Future<bool> Function() prepare,
}) async {
  if (!context.mounted) return false;

  final navigator = Navigator.of(context, rootNavigator: true);
  final dialog = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
    builder: (_) => const AlertDialog(
      key: ValueKey('guest-qr-preparation-dialog'),
      content: Row(
        children: [
          CircularProgressIndicator(),
          SizedBox(width: 18),
          Expanded(child: Text('Preparing guest QR...')),
        ],
      ),
    ),
  );
  var dismissed = false;
  unawaited(
    navigator.push<void>(dialog).then<void>((_) {
      dismissed = true;
    }),
  );

  try {
    final ready = await prepare();
    return ready &&
        context.mounted &&
        navigator.mounted &&
        !dismissed &&
        dialog.isActive &&
        dialog.isCurrent;
  } finally {
    // A bare pop could close the transfer page after Back, or a different page
    // opened while the request was pending. Remove this exact route instead.
    if (navigator.mounted && dialog.isActive) {
      navigator.removeRoute(dialog);
    }
  }
}
