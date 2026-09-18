import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:mobileapp/core/theme/app_theme.dart';
import 'package:mobileapp/core/upload/transfer_ledger_storage.dart';
import 'package:mobileapp/core/upload/upload_queue_service.dart';
import 'package:mobileapp/widgets/app_ui.dart';

enum TransferListFilter { all, uploaded, notUploaded }

@RoutePage()
class TransferListPage extends StatelessWidget {
  const TransferListPage({
    super.key,
    required this.eventId,
    required this.eventTitle,
    required this.filter,
  });

  final String eventId;
  final String eventTitle;
  final TransferListFilter filter;

  String get title => switch (filter) {
    TransferListFilter.all => 'All photos',
    TransferListFilter.uploaded => 'Uploaded',
    TransferListFilter.notUploaded => 'Not uploaded',
  };

  bool matches(TransferLedgerItem item) => switch (filter) {
    TransferListFilter.all => true,
    TransferListFilter.uploaded => item.isUploaded,
    TransferListFilter.notUploaded => !item.isUploaded,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 82,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title),
            const SizedBox(height: 3),
            Text(
              eventTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: AppColors.mutedForeground,
              ),
            ),
          ],
        ),
      ),
      body: ValueListenableBuilder<List<TransferLedgerItem>>(
        valueListenable: TransferLedgerStorage.items,
        builder: (context, allItems, _) {
          final items = allItems
              .where((item) => item.eventId == eventId && matches(item))
              .toList(growable: false);

          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: AppEmptyState(
                  icon: Icons.photo_library_outlined,
                  title: 'No $title yet',
                  message: eventTitle,
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final item = items[index];
              return Container(
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppColors.border),
                ),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  contentPadding: const EdgeInsets.all(10),
                  leading: _thumbnail(context, item),
                  title: Text(
                    item.filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 3),
                      Text('${_statusLabel(item.status)} · ${item.source}'),
                      if (item.error?.isNotEmpty == true)
                        Text(
                          item.error!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                    ],
                  ),
                  trailing: _statusWidget(context, item),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _thumbnail(BuildContext context, TransferLedgerItem item) {
    Widget fallback() => Container(
      height: 56,
      width: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(9),
      ),
      child: const Icon(Icons.image_outlined),
    );

    final lower = item.filename.toLowerCase();
    final previewable = const [
      '.jpg',
      '.jpeg',
      '.png',
      '.webp',
    ].any(lower.endsWith);
    if (previewable && item.localPath != null) {
      final file = File(item.localPath!);
      if (file.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: Image.file(
            file,
            height: 56,
            width: 56,
            fit: BoxFit.cover,
            cacheHeight: 180,
            errorBuilder: (_, _, _) => fallback(),
          ),
        );
      }
    }

    if (previewable && item.imageUrl?.isNotEmpty == true) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Image.network(
          item.imageUrl!,
          height: 56,
          width: 56,
          fit: BoxFit.cover,
          cacheHeight: 180,
          errorBuilder: (_, _, _) => fallback(),
        ),
      );
    }
    return fallback();
  }

  Widget _statusWidget(BuildContext context, TransferLedgerItem item) {
    if (item.status == TransferLedgerStatus.delivered ||
        item.status == TransferLedgerStatus.published) {
      return Icon(
        Icons.check_circle,
        color: Theme.of(context).colorScheme.primary,
      );
    }
    if (item.status == TransferLedgerStatus.failed) {
      return IconButton(
        tooltip: 'Retry now',
        onPressed: () => UploadQueueService.retryNow(item.id),
        icon: Icon(Icons.refresh, color: Theme.of(context).colorScheme.error),
      );
    }

    final value =
        item.status == TransferLedgerStatus.uploading && item.progress > 0
        ? item.progress / 100
        : null;
    return SizedBox(
      height: 27,
      width: 27,
      child: CircularProgressIndicator(value: value, strokeWidth: 2.6),
    );
  }

  String _statusLabel(TransferLedgerStatus status) => switch (status) {
    TransferLedgerStatus.detected => 'Detected',
    TransferLedgerStatus.stored => 'Stored',
    TransferLedgerStatus.queued => 'Queued',
    TransferLedgerStatus.uploading => 'Uploading',
    TransferLedgerStatus.processing => 'Processing',
    TransferLedgerStatus.published => 'Published',
    TransferLedgerStatus.delivered => 'Uploaded',
    TransferLedgerStatus.failed => 'Failed',
  };
}
