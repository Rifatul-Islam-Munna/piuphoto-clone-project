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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 78,
        actions: [
          if (widget.onViewHistory != null)
            IconButton(
              onPressed: widget.onViewHistory,
              tooltip: 'All event transfers',
              icon: const Icon(Icons.history),
            ),
          if (widget.onShareGuestQr != null)
            IconButton(
              onPressed: widget.onShareGuestQr,
              tooltip: 'Share guest QR',
              icon: const Icon(Icons.qr_code_2),
            ),
        ],
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Camera transfers'),
            const SizedBox(height: 3),
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
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                              itemCount: items.isEmpty ? 2 : items.length + 1,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 16),
                              itemBuilder: (context, index) {
                                if (index == 0) {
                                  return _SessionHeader(
                                    session: session,
                                    items: items,
                                    stopping: _stopping,
                                    onStop: widget.onStop == null
                                        ? null
                                        : _stop,
                                    connectionDetails: widget
                                        .connectionDetailsBuilder
                                        ?.call(context),
                                  );
                                }
                                if (items.isEmpty) {
                                  return _EmptyTransfers(session: session);
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
    required this.connectionDetails,
  });

  final CameraTransferSessionStatus session;
  final List<TransferLedgerItem> items;
  final bool stopping;
  final VoidCallback? onStop;
  final Widget? connectionDetails;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final uploaded = items.where((item) => item.isUploaded).length;
    final cancelled = items
        .where((item) => item.status == TransferLedgerStatus.cancelled)
        .length;
    final pending = items.length - uploaded - cancelled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (session.isConnecting || stopping)
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  else
                    Icon(
                      session.isActive
                          ? Icons.camera_alt_outlined
                          : Icons.link_off,
                      color: session.isActive
                          ? colors.primary
                          : colors.onSurfaceVariant,
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      stopping
                          ? 'Stopping connection…'
                          : session.connectionLabel,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                session.message,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (onStop != null &&
                  (session.isActive || session.isConnecting)) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: stopping ? null : onStop,
                    icon: const Icon(Icons.stop_circle_outlined, size: 20),
                    label: const Text('Stop receiving'),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (connectionDetails != null) ...[
          const SizedBox(height: 12),
          connectionDetails!,
        ],
        const SizedBox(height: 18),
        Text(
          'This session',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            Text('${items.length} received'),
            Text('$uploaded uploaded'),
            Text('$pending pending'),
            if (cancelled > 0) Text('$cancelled cancelled'),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Received photos start uploading to cloud automatically. Tap × while an upload is cancellable.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _EmptyTransfers extends StatelessWidget {
  const _EmptyTransfers({required this.session});

  final CameraTransferSessionStatus session;

  @override
  Widget build(BuildContext context) {
    final waiting = session.isActive;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 44),
      child: Column(
        children: [
          Icon(
            Icons.add_a_photo_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            waiting ? 'Waiting for camera photos' : 'No photos received yet',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            waiting
                ? 'Received photos upload to your cloud event automatically. Their previews, filenames, sizes and progress appear here. You can keep taking photos on your camera.'
                : 'Photos will appear here when your camera connection is ready.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
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
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 4 / 3,
                child: _PhotoPreview(item: item),
              ),
              if (onCancel != null || cancelling)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Material(
                    color: colors.surface,
                    elevation: 2,
                    shape: const CircleBorder(),
                    child: cancelling
                        ? const SizedBox(
                            width: 48,
                            height: 48,
                            child: Padding(
                              padding: EdgeInsets.all(14),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            key: ValueKey('cancel-${item.id}'),
                            tooltip: 'Cancel upload of ${item.filename}',
                            onPressed: onCancel,
                            icon: const Icon(Icons.close),
                          ),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.filename,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 5),
                Text(
                  fileSize > 0
                      ? _formatBytes(fileSize.toDouble())
                      : 'Size unavailable',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      cancelled
                          ? Icons.cancel_outlined
                          : item.isUploaded
                          ? Icons.check_circle_outline
                          : item.waitingForConnection && failed
                          ? Icons.cloud_off_outlined
                          : failed
                          ? Icons.error_outline
                          : Icons.cloud_upload_outlined,
                      size: 19,
                      color: statusColor,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        status,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (uploading && progress != null && !cancelling)
                      Text('${(progress * 100).round()}%'),
                  ],
                ),
                if ((uploading || finishing) && !cancelling) ...[
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: uploading ? progress : null,
                    minHeight: 5,
                    borderRadius: BorderRadius.circular(3),
                    semanticsLabel: 'Upload progress for ${item.filename}',
                  ),
                  if (uploading && item.bytesPerSecond > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${_formatBytes(item.bytesPerSecond)}/s',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
                if (failed && item.error?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text(
                    item.waitingForConnection
                        ? 'The cloud could not be reached. Keep AirPix open; it will retry automatically.'
                        : item.error!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: colors.error),
                  ),
                  if (queued?.nextRetryAt != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      onCancel != null
                          ? 'A retry is scheduled. You can still cancel this photo.'
                          : 'Cloud confirmation is pending. AirPix will retry automatically.',
                    ),
                  ],
                ],
              ],
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
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.image_outlined,
                size: 44,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(height: 10),
              Text(
                previewable
                    ? 'Preview unavailable'
                    : 'RAW / file preview unavailable',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    Widget networkOrPlaceholder() {
      if (!previewable || item.imageUrl?.isNotEmpty != true) {
        return placeholder();
      }
      return Image.network(
        item.imageUrl!,
        fit: BoxFit.contain,
        cacheWidth: 1024,
        errorBuilder: (_, _, _) => placeholder(),
      );
    }

    final Widget preview;
    if (previewable && item.localPath?.isNotEmpty == true) {
      preview = Image.file(
        File(item.localPath!),
        fit: BoxFit.contain,
        cacheWidth: 1024,
        // A completed upload may remove the local queue file. The remote image
        // is then used without synchronously probing the filesystem on build.
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
