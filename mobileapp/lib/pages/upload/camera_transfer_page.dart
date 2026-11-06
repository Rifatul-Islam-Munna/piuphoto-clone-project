import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobileapp/core/upload/transfer_ledger_storage.dart';
import 'package:mobileapp/core/upload/upload_queue_service.dart';
import 'package:mobileapp/core/upload/upload_queue_storage.dart';

@immutable
class CameraTransferSessionStatus {
  const CameraTransferSessionStatus({
    required this.connectionLabel,
    required this.message,
    required this.isActive,
    this.isConnecting = false,
  });

  final String connectionLabel;
  final String message;
  final bool isActive;
  final bool isConnecting;
}

/// A view of the receiving session. The caller owns the camera connection so
/// opening or leaving this page never stops a transfer in progress.
class CameraTransferPage extends StatefulWidget {
  const CameraTransferPage({
    super.key,
    required this.eventId,
    required this.eventTitle,
    required this.session,
    this.startedAt,
    this.onStop,
    this.onShareGuestQr,
    this.onViewHistory,
    this.onCameraSetupHelp,
    this.connectionDetailsBuilder,
    this.transfers,
    this.queue,
    this.cancelUpload,
    this.canCancel,
  });

  final String eventId;
  final String eventTitle;
  final ValueListenable<CameraTransferSessionStatus> session;
  final DateTime? startedAt;
  final Future<void> Function()? onStop;
  final VoidCallback? onShareGuestQr;
  final VoidCallback? onViewHistory;
  final VoidCallback? onCameraSetupHelp;
  final WidgetBuilder? connectionDetailsBuilder;

  // Optional inputs keep the screen testable without opening a camera or
  // sending a request. Production callers use the persistent transfer stores.
  final ValueListenable<List<TransferLedgerItem>>? transfers;
  final ValueListenable<List<PendingUploadItem>>? queue;
  final Future<UploadCancellationResult> Function(String id)? cancelUpload;
  final bool Function(TransferLedgerItem item)? canCancel;

  @override
  State<CameraTransferPage> createState() => _CameraTransferPageState();
}

class _CameraTransferPageState extends State<CameraTransferPage> {
  final Set<String> _cancelling = {};
  bool _stopping = false;
  Timer? _countdownTimer;

  ValueListenable<List<TransferLedgerItem>> get _transfers =>
      widget.transfers ?? TransferLedgerStorage.items;
  ValueListenable<List<PendingUploadItem>> get _queue =>
      widget.queue ?? UploadQueueStorage.items;

  @override
  void initState() {
    super.initState();
    _queue.addListener(_syncCountdown);
    _syncCountdown();
  }

  @override
  void didUpdateWidget(covariant CameraTransferPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldQueue = oldWidget.queue ?? UploadQueueStorage.items;
    if (!identical(oldQueue, _queue)) {
      oldQueue.removeListener(_syncCountdown);
      _queue.addListener(_syncCountdown);
    }
    _syncCountdown();
  }

  @override
  void dispose() {
    _queue.removeListener(_syncCountdown);
    _countdownTimer?.cancel();
    // The parent remains responsible for stopping the receiving session.
    super.dispose();
  }

  void _syncCountdown() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final needsTimer = _queue.value.any(
      (item) => item.eventId == widget.eventId && (item.uploadAfter ?? 0) > now,
    );
    if (!needsTimer) {
      _countdownTimer?.cancel();
      _countdownTimer = null;
      return;
    }
    _countdownTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      _syncCountdown();
    });
  }

  Future<void> _cancel(TransferLedgerItem item) async {
    if (_cancelling.contains(item.id)) return;
    setState(() => _cancelling.add(item.id));
    try {
      final result =
          await (widget.cancelUpload ?? UploadQueueService.cancelUpload)(
            item.id,
          );
      if (!mounted) return;
      final message = switch (result) {
        UploadCancellationResult.cancelled =>
          'Upload cancelled for ${item.filename}.',
        UploadCancellationResult.alreadyCompleted =>
          '${item.filename} has already uploaded.',
        UploadCancellationResult.finishing =>
          '${item.filename} is finishing its upload and can no longer be cancelled.',
        UploadCancellationResult.notFound =>
          'This photo is no longer waiting to upload.',
      };
      _showMessage(message);
    } catch (_) {
      if (mounted) {
        _showMessage('Could not cancel this upload. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _cancelling.remove(item.id));
    }
  }

  Future<void> _stop() async {
    if (_stopping || widget.onStop == null) return;
    setState(() => _stopping = true);
    try {
      await widget.onStop!();
    } catch (_) {
      if (mounted) {
        _showMessage('Could not stop this connection. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _stopping = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showConnectionDetails() async {
    final builder = widget.connectionDetailsBuilder;
    if (builder == null || !mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Connection details',
                style: Theme.of(
                  sheetContext,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              builder(sheetContext),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More camera transfer actions',
            onSelected: (value) {
              switch (value) {
                case 'details':
                  _showConnectionDetails();
                case 'history':
                  widget.onViewHistory?.call();
                case 'qr':
                  widget.onShareGuestQr?.call();
              }
            },
            itemBuilder: (context) => [
              if (widget.connectionDetailsBuilder != null)
                const PopupMenuItem(
                  value: 'details',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.usb_rounded),
                    title: Text('Connection details'),
                  ),
                ),
              if (widget.onViewHistory != null)
                const PopupMenuItem(
                  value: 'history',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.history),
                    title: Text('Transfer history'),
                  ),
                ),
              if (widget.onShareGuestQr != null)
                const PopupMenuItem(
                  value: 'qr',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.qr_code_2),
                    title: Text('Share guest QR'),
                  ),
                ),
            ],
            icon: const Icon(Icons.more_vert_rounded),
          ),
        ],
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Camera transfers'),
            Text(
              widget.eventTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ValueListenableBuilder<CameraTransferSessionStatus>(
              valueListenable: widget.session,
              builder: (context, session, _) =>
                  ValueListenableBuilder<List<TransferLedgerItem>>(
                    valueListenable: _transfers,
                    builder: (context, allItems, _) =>
                        ValueListenableBuilder<List<PendingUploadItem>>(
                          valueListenable: _queue,
                          builder: (context, queued, _) {
                            final since =
                                widget.startedAt?.millisecondsSinceEpoch;
                            final items =
                                allItems
                                    .where(
                                      (item) =>
                                          item.eventId == widget.eventId &&
                                          (since == null ||
                                              item.createdAt >= since),
                                    )
                                    .toList()
                                  ..sort((a, b) {
                                    final byCreated = b.createdAt.compareTo(
                                      a.createdAt,
                                    );
                                    return byCreated != 0
                                        ? byCreated
                                        : a.id.compareTo(b.id);
                                  });
                            final queueById = {
                              for (final item in queued) item.id: item,
                            };
                            final canCancel =
                                widget.canCancel ??
                                UploadQueueService.canCancel;
                            return ListView.separated(
                              key: PageStorageKey(
                                'camera-transfers-${widget.eventId}-$since',
                              ),
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
                              itemCount: items.isEmpty ? 2 : items.length + 1,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                if (index == 0) {
                                  return _SessionHeader(
                                    session: session,
                                    items: items,
                                    stopping: _stopping,
                                    onStop: widget.onStop == null
                                        ? null
                                        : _stop,
                                  );
                                }
                                if (items.isEmpty) {
                                  return _EmptyTransfers(
                                    session: session,
                                    onCameraSetupHelp: widget.onCameraSetupHelp,
                                  );
                                }
                                final item = items[index - 1];
                                return _TransferPhotoCard(
                                  key: ValueKey(item.id),
                                  item: item,
                                  queued: queueById[item.id],
                                  cancelling: _cancelling.contains(item.id),
                                  onCancel: canCancel(item)
                                      ? () => _cancel(item)
                                      : null,
                                );
                              },
                            );
                          },
                        ),
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SessionHeader extends StatelessWidget {
  const _SessionHeader({
    required this.session,
    required this.items,
    required this.stopping,
    required this.onStop,
  });

  final CameraTransferSessionStatus session;
  final List<TransferLedgerItem> items;
  final bool stopping;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final uploaded = items.where((item) => item.isUploaded).length;
    final cancelled = items
        .where((item) => item.status == TransferLedgerStatus.cancelled)
        .length;
    final pending = items.length - uploaded - cancelled;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          if (session.isConnecting || stopping)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(
              session.isActive ? Icons.circle : Icons.circle_outlined,
              size: 12,
              color: session.isActive
                  ? colors.primary
                  : colors.onSurfaceVariant,
            ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stopping
                      ? 'Stopping…'
                      : session.isActive
                      ? items.isEmpty
                            ? 'Ready for a test shot'
                            : 'Receiving photos'
                      : 'Receiving stopped',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 8,
                  runSpacing: 2,
                  children: [
                    Text(
                      '${items.length} received',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      '$uploaded uploaded',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      '$pending pending',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (cancelled > 0)
                      Text(
                        '$cancelled cancelled',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (onStop != null && (session.isActive || session.isConnecting))
            TextButton.icon(
              onPressed: stopping ? null : onStop,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              ),
              icon: const Icon(Icons.stop_circle_outlined, size: 18),
              label: const Text('Stop receiving'),
            ),
        ],
      ),
    );
  }
}

class _EmptyTransfers extends StatelessWidget {
  const _EmptyTransfers({required this.session, this.onCameraSetupHelp});

  final CameraTransferSessionStatus session;
  final VoidCallback? onCameraSetupHelp;

  @override
  Widget build(BuildContext context) {
    final waiting = session.isActive;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        children: [
          Icon(
            Icons.add_a_photo_outlined,
            size: 32,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 10),
          Text(
            waiting ? 'Waiting for camera photos' : 'No photos received yet',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 5),
          Text(
            waiting
                ? 'Take a test photo with the camera’s physical shutter. '
                      'If its screen locks, stop and choose a shooting-capable '
                      'USB tether mode. New photos upload when received.'
                : session.message.trim().isNotEmpty
                ? session.message
                : 'Photos will appear here when the camera connection is ready.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (onCameraSetupHelp != null) ...[
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: onCameraSetupHelp,
              icon: const Icon(Icons.help_outline_rounded),
              label: const Text('Camera screen black? Stop and fix USB mode'),
            ),
          ],
        ],
      ),
    );
  }
}

class _TransferPhotoCard extends StatelessWidget {
  const _TransferPhotoCard({
    super.key,
    required this.item,
    required this.queued,
    required this.cancelling,
    required this.onCancel,
  });

  final TransferLedgerItem item;
  final PendingUploadItem? queued;
  final bool cancelling;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final cancelled = item.status == TransferLedgerStatus.cancelled;
    final failed = item.status == TransferLedgerStatus.failed;
    final uploading = item.status == TransferLedgerStatus.uploading;
    final finishing =
        item.status == TransferLedgerStatus.processing && !item.isUploaded;
    final delay =
        ((queued?.uploadAfter ?? 0) - DateTime.now().millisecondsSinceEpoch) /
        1000;
    final status = cancelling
        ? 'Cancelling upload…'
        : delay > 0 && item.status == TransferLedgerStatus.queued
        ? 'Uploads in ${delay.ceil()} s'
        : _statusLabel(item);
    final statusColor = failed && !item.waitingForConnection
        ? colors.error
        : cancelled
        ? colors.onSurfaceVariant
        : colors.primary;
    final fileSize = item.fileSize > 0 ? item.fileSize : item.bytesTotal;
    final progress = item.bytesTotal > 0
        ? (item.bytesSent / item.bytesTotal).clamp(0.0, 1.0)
        : null;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: SizedBox(
              width: 66,
              height: 66,
              child: _PhotoPreview(item: item),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      fileSize > 0
                          ? _formatBytes(fileSize.toDouble())
                          : 'Size unavailable',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (uploading && progress != null && !cancelling) ...[
                      const SizedBox(width: 6),
                      Text(
                        '${(progress * 100).round()}%',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
                if ((uploading || finishing) && !cancelling) ...[
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: uploading ? progress : null,
                    minHeight: 3,
                    borderRadius: BorderRadius.circular(3),
                    semanticsLabel: 'Upload progress for ${item.filename}',
                  ),
                ],
                if (failed && item.error?.isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.waitingForConnection
                        ? 'The cloud could not be reached. AirPix will retry automatically.'
                        : item.error!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.error,
                      fontSize: 10.5,
                    ),
                  ),
                  if (queued?.nextRetryAt != null)
                    Text(
                      onCancel != null
                          ? 'A retry is scheduled. You can still cancel this photo.'
                          : 'Cloud confirmation is pending. AirPix will retry automatically.',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(fontSize: 10.5),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 38,
            height: 38,
            child: cancelling
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : onCancel != null
                ? IconButton(
                    key: ValueKey('cancel-${item.id}'),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Cancel upload of ${item.filename}',
                    onPressed: onCancel,
                    icon: const Icon(Icons.close_rounded, size: 20),
                  )
                : Icon(
                    cancelled
                        ? Icons.cancel_outlined
                        : item.isUploaded
                        ? Icons.check_circle_rounded
                        : failed
                        ? Icons.error_outline_rounded
                        : Icons.cloud_upload_outlined,
                    size: 20,
                    color: statusColor,
                  ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(TransferLedgerItem item) => switch (item.status) {
    TransferLedgerStatus.detected => 'Receiving photo',
    TransferLedgerStatus.stored => 'Preparing cloud upload',
    TransferLedgerStatus.queued => 'Waiting for cloud upload',
    TransferLedgerStatus.uploading => 'Uploading to cloud',
    TransferLedgerStatus.processing =>
      item.isUploaded
          ? 'Uploaded to cloud · processing'
          : 'Finishing cloud upload',
    TransferLedgerStatus.published => 'Uploaded to cloud',
    TransferLedgerStatus.delivered => 'Uploaded to cloud',
    TransferLedgerStatus.failed =>
      item.waitingForConnection
          ? 'Waiting for cloud connection'
          : item.registrationStarted
          ? 'Waiting for cloud confirmation'
          : 'Cloud upload paused',
    TransferLedgerStatus.cancelled => 'Upload cancelled',
  };
}

class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({required this.item});

  final TransferLedgerItem item;

  @override
  Widget build(BuildContext context) {
    final lower = item.filename.toLowerCase();
    final previewable = const [
      '.jpg',
      '.jpeg',
      '.png',
      '.webp',
      '.heic',
      '.heif',
    ].any(lower.endsWith);
    final colors = Theme.of(context).colorScheme;

    Widget placeholder() => ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.image_outlined,
          size: 24,
          color: colors.onSurfaceVariant,
        ),
      ),
    );

    Widget networkOrPlaceholder() {
      if (!previewable || item.imageUrl?.isNotEmpty != true) {
        return placeholder();
      }
      return Image.network(
        item.imageUrl!,
        fit: BoxFit.cover,
        cacheWidth: 256,
        errorBuilder: (_, _, _) => placeholder(),
      );
    }

    final Widget preview;
    if (previewable && item.localPath?.isNotEmpty == true) {
      preview = Image.file(
        File(item.localPath!),
        fit: BoxFit.cover,
        cacheWidth: 256,
        errorBuilder: (_, _, _) => networkOrPlaceholder(),
      );
    } else {
      preview = networkOrPlaceholder();
    }
    return Semantics(
      image: true,
      label: 'Preview of ${item.filename}',
      child: ExcludeSemantics(
        child: ColoredBox(
          color: colors.surfaceContainerHighest,
          child: preview,
        ),
      ),
    );
  }
}

String _formatBytes(double bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${bytes.round()} B';
}
