import 'package:flutter/material.dart';

/// AI status is independent of upload completion and gallery publication.
class AiRetouchBadge extends StatelessWidget {
  const AiRetouchBadge({super.key, required this.label, this.message});
  final String label;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final original = label == 'Original';
    final pending = label == 'AI processing';
    final failed = label == 'AI failed';
    final skipped = label == 'AI skipped';
    return Tooltip(
      message:
          message ??
          (label == 'AI copy ready'
              ? 'The original is uploaded; its separate AI-enhanced copy is ready.'
              : label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        decoration: BoxDecoration(
          color: failed
              ? const Color(0xFF9F2727)
              : original || skipped
              ? Colors.black.withValues(alpha: .65)
              : pending
              ? const Color(0xFF3C4D80)
              : const Color(0xFF6339A8),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!original) ...[
              Icon(
                failed
                    ? Icons.error_outline_rounded
                    : skipped
                    ? Icons.info_outline_rounded
                    : pending
                    ? Icons.auto_awesome_outlined
                    : Icons.auto_awesome_rounded,
                color: Colors.white,
                size: 11,
              ),
              const SizedBox(width: 3),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
