import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// A QR code image that reports correct intrinsic dimensions.
///
/// qr_flutter's [QrImageView] internally wraps its painter in a
/// [LayoutBuilder], which throws
/// "LayoutBuilder does not support returning intrinsic dimensions" when it is
/// placed inside widgets that query intrinsic sizes (e.g. an [AlertDialog]
/// sizes itself via [IntrinsicWidth] before laying out its children).
///
/// This widget paints the QR directly with [QrPainter] (no LayoutBuilder) and
/// exposes all intrinsic sizes, so it is safe to use inside dialogs, menus,
/// tooltips and overflow menus.
class IntrinsicQrImage extends StatelessWidget {
  const IntrinsicQrImage({
    required this.data,
    super.key,
    this.size,
    this.padding = const EdgeInsets.all(10),
    this.backgroundColor,
    this.errorCorrectionLevel = QrErrorCorrectLevel.L,
    this.eyeStyle = const QrEyeStyle(
      eyeShape: QrEyeShape.square,
      color: Colors.black,
    ),
    this.dataModuleStyle = const QrDataModuleStyle(
      dataModuleShape: QrDataModuleShape.square,
      color: Colors.black,
    ),
    this.gapless = true,
    this.semanticsLabel = 'qr code',
  });

  /// The data to encode in the QR code.
  final String data;

  /// Edge length of the square QR image, padding included. Falls back to
  /// 230 when null.
  final double? size;

  /// Padding around the painted QR modules.
  final EdgeInsetsGeometry padding;

  /// Background color painted behind the QR code.
  final Color? backgroundColor;

  final int errorCorrectionLevel;

  final QrEyeStyle eyeStyle;

  final QrDataModuleStyle dataModuleStyle;

  final bool gapless;

  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final validationResult = QrValidator.validate(
      data: data,
      version: QrVersions.auto,
      errorCorrectionLevel: errorCorrectionLevel,
    );

    final double edgeLength = size ?? 230;

    Widget buildPlaceholder() {
      return SizedBox.square(
        dimension: edgeLength,
        child: const ColoredBox(
          color: Colors.white,
          child: Center(
            child: Icon(Icons.qr_code, size: 48, color: Colors.black26),
          ),
        ),
      );
    }

    if (!validationResult.isValid || validationResult.qrCode == null) {
      return buildPlaceholder();
    }

    final QrPainter painter;
    try {
      // The validator can still hand back a QrCode that overflows version 40
      // capacity; the real failure only surfaces when the image is built.
      painter = QrPainter.withQr(
        qr: validationResult.qrCode!,
        gapless: gapless,
        eyeStyle: eyeStyle,
        dataModuleStyle: dataModuleStyle,
      );
    } catch (_) {
      return buildPlaceholder();
    }

    return Semantics(
      label: semanticsLabel,
      child: Padding(
        padding: padding,
        child: CustomPaint(
          size: Size.square(edgeLength - padding.horizontal),
          painter: painter,
        ),
      ),
    );
  }
}
