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
    this.onShareFaceQr,
    this.onPreviewGallery,
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
  final VoidCallback? onShareFaceQr;
  final VoidCallback? onPreviewGallery;
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

enum _TransferFilter { all, notUploaded, uploading, uploaded, failed }

bool _transferMatches(TransferLedgerItem item, _TransferFilter filter) {
  final activeUpload =
      item.status == TransferLedgerStatus.uploading ||
      (item.status == TransferLedgerStatus.processing && !item.isUploaded);
  return switch (filter) {
    _TransferFilter.all => true,
    _TransferFilter.uploaded => item.isUploaded,
    _TransferFilter.uploading => activeUpload,
    _TransferFilter.failed => item.status == TransferLedgerStatus.failed,
    _TransferFilter.notUploaded =>
      !item.isUploaded &&
          !activeUpload &&
          item.status != TransferLedgerStatus.failed,
  };
}

String _filterTitle(_TransferFilter filter) => switch (filter) {
  _TransferFilter.all => 'All',
  _TransferFilter.notUploaded => 'Not uploaded',
  _TransferFilter.uploading => 'Uploading',
  _TransferFilter.uploaded => 'Uploaded',
  _TransferFilter.failed => 'Failed',
};

String _statusDescription(TransferLedgerItem item) => switch (item.status) {
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

class _CameraTransferPageState extends State<CameraTransferPage> {
  final Set<String> _cancelling = {};
  bool _stopping = false;
  bool _showGrid = true;
  _TransferFilter _filter = _TransferFilter.all;
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

  Future<void> _showPhotoDetails(TransferLedgerItem item) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                item.filename,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: MediaQuery.sizeOf(sheetContext).height * .45,
                  child: _PhotoPreview(item: item, cacheWidth: 1024),
                ),
              ),
              const SizedBox(height: 12),
              Text(_statusDescription(item)),
              const SizedBox(height: 3),
              Text(
                'Event: ${widget.eventTitle} · ${_formatBytes((item.fileSize > 0 ? item.fileSize : item.bytesTotal).toDouble())}',
              ),
              if (item.error?.isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    item.error!,
                    style: TextStyle(
                      color: Theme.of(sheetContext).colorScheme.error,
                    ),
                  ),
                ),
              if (item.status == TransferLedgerStatus.failed &&
                  !item.registrationStarted)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      unawaited(UploadQueueService.retryNow(item.id));
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry upload'),
                  ),
                ),
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
                case 'preview':
                  widget.onPreviewGallery?.call();
                case 'view-grid':
                  setState(() => _showGrid = true);
                case 'view-list':
                  setState(() => _showGrid = false);
                case 'qr':
                  widget.onShareGuestQr?.call();
                case 'face-qr':
                  widget.onShareFaceQr?.call();
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
              if (widget.onPreviewGallery != null)
                const PopupMenuItem(
                  value: 'preview',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.preview_outlined),
                    title: Text('Preview Photo Live'),
                  ),
                ),
              PopupMenuItem(
                value: _showGrid ? 'view-list' : 'view-grid',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _showGrid
                        ? Icons.view_list_rounded
                        : Icons.grid_view_rounded,
                  ),
                  title: Text(_showGrid ? 'List view' : 'Grid view'),
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
                    title: Text('Share gallery QR'),
                  ),
                ),
              if (widget.onShareFaceQr != null)
                const PopupMenuItem(
                  value: 'face-qr',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.face_retouching_natural_outlined),
                    title: Text('Share face-delivery QR'),
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
                            final filtered = items
                                .where(
                                  (item) => _transferMatches(item, _filter),
                                )
                                .toList(growable: false);
                            return CustomScrollView(
                              key: PageStorageKey(
                                'camera-transfers-${widget.eventId}-$since',
                              ),
                              slivers: [
                                SliverPadding(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    8,
                                    12,
                                    10,
                                  ),
                                  sliver: SliverToBoxAdapter(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _SessionHeader(
                                          session: session,
                                          items: items,
                                          stopping: _stopping,
                                          onStop: widget.onStop == null
                                              ? null
                                              : _stop,
                                        ),
                                        const SizedBox(height: 12),
                                        SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: Row(
                                            children: [
                                              for (final filter
                                                  in _TransferFilter.values)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        right: 6,
                                                      ),
                                                  child: ChoiceChip(
                                                    key: ValueKey(
                                                      'filter-${filter.name}',
                                                    ),
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                    label: Text(
                                                      '${_filterTitle(filter)} ${items.where((item) => _transferMatches(item, filter)).length}',
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                    selected: _filter == filter,
                                                    onSelected: (_) => setState(
                                                      () => _filter = filter,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          _showGrid
                                              ? 'Tap a photo to inspect it · updates live'
                                              : 'Photo transfer details',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (items.isEmpty)
                                  SliverToBoxAdapter(
                                    child: _EmptyTransfers(
                                      session: session,
                                      onCameraSetupHelp:
                                          widget.onCameraSetupHelp,
                                    ),
                                  )
                                else if (filtered.isEmpty)
                                  SliverToBoxAdapter(
                                    child: Padding(
                                      padding: const EdgeInsets.all(32),
                                      child: Center(
                                        child: Text(
                                          'No ${_filterTitle(_filter).toLowerCase()} photos',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodyMedium,
                                        ),
                                      ),
                                    ),
                                  )
                                else if (_showGrid)
                                  SliverPadding(
                                    padding: const EdgeInsets.fromLTRB(
                                      10,
                                      0,
                                      10,
                                      24,
                                    ),
                                    sliver: SliverLayoutBuilder(
                                      builder: (context, constraints) {
                                        final columns =
                                            constraints.crossAxisExtent < 480
                                            ? 3
                                            : constraints.crossAxisExtent < 650
                                            ? 4
                                            : 5;
                                        return SliverGrid(
                                          gridDelegate:
                                              SliverGridDelegateWithFixedCrossAxisCount(
                                                crossAxisCount: columns,
                                                crossAxisSpacing: 7,
                                                mainAxisSpacing: 8,
                                                childAspectRatio: 0.63,
                                              ),
                                          delegate: SliverChildBuilderDelegate((
                                            context,
                                            index,
                                          ) {
                                            final item = filtered[index];
                                            return _TransferGridTile(
                                              key: ValueKey('grid-${item.id}'),
                                              item: item,
                                              queued: queueById[item.id],
                                              cancelling: _cancelling.contains(
                                                item.id,
                                              ),
                                              onCancel: canCancel(item)
                                                  ? () => _cancel(item)
                                                  : null,
                                              onTap: () =>
                                                  _showPhotoDetails(item),
                                            );
                                          }, childCount: filtered.length),
                                        );
                                      },
                                    ),
                                  )
                                else
                                  SliverPadding(
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      0,
                                      12,
                                      24,
                                    ),
                                    sliver: SliverList(
                                      delegate: SliverChildBuilderDelegate((
                                        context,
                                        index,
                                      ) {
                                        final item = filtered[index];
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          child: _TransferPhotoCard(
                                            key: ValueKey(item.id),
                                            item: item,
                                            queued: queueById[item.id],
                                            cancelling: _cancelling.contains(
                                              item.id,
                                            ),
                                            onCancel: canCancel(item)
                                                ? () => _cancel(item)
                                                : null,
                                          ),
                                        );
                                      }, childCount: filtered.length),
                                    ),
                                  ),
                              ],
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

/// Compact, live-updating photo card inspired by the camera upload monitor.
/// The persistent transfer ledger is the single source of truth for statuses.
class _TransferGridTile extends StatelessWidget {
  const _TransferGridTile({
    super.key,
    required this.item,
    required this.queued,
    required this.cancelling,
    required this.onCancel,
    required this.onTap,
  });

  final TransferLedgerItem item;
  final PendingUploadItem? queued;
  final bool cancelling;
  final VoidCallback? onCancel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final uploaded = item.isUploaded;
    final failed = item.status == TransferLedgerStatus.failed;
    final uploading = _transferMatches(item, _TransferFilter.uploading);
    final cancelled = item.status == TransferLedgerStatus.cancelled;
    final delay =
        ((queued?.uploadAfter ?? 0) - DateTime.now().millisecondsSinceEpoch) /
        1000;
    final status = cancelling
        ? 'Cancelling upload…'
        : delay > 0 && item.status == TransferLedgerStatus.queued
        ? 'Uploads in ${delay.ceil()} s'
        : _statusDescription(item);
    final label = cancelled
        ? 'Cancelled'
        : failed
        ? item.waitingForConnection
              ? 'Waiting'
              : 'Failed'
        : uploaded
        ? 'Uploaded'
        : uploading
        ? 'Uploading'
        : 'Not uploaded';
    final badgeColor = failed && !item.waitingForConnection
        ? colors.error
        : uploaded
        ? const Color(0xFF16834A)
        : uploading
        ? colors.primary
        : Colors.black87;
    final size = item.fileSize > 0 ? item.fileSize : item.bytesTotal;
    final progress = item.bytesTotal > 0
        ? (item.bytesSent / item.bytesTotal).clamp(0.0, 1.0)
        : (item.progress / 100).clamp(0.0, 1.0);

    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(11),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: colors.outlineVariant),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _PhotoPreview(item: item),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: badgeColor,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          label,
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    if (uploading && !uploaded)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: item.status == TransferLedgerStatus.uploading
                              ? progress
                              : null,
                          minHeight: 4,
                          semanticsLabel:
                              'Upload progress for ${item.filename}',
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(5, 5, 5, 0),
                child: Text(
                  item.filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Text(
                  size > 0 ? _formatBytes(size.toDouble()) : 'Size unknown',
                  maxLines: 1,
                  style: TextStyle(fontSize: 9, color: colors.onSurfaceVariant),
                ),
              ),
              SizedBox(
                height: 30,
                child: Padding(
                  padding: const EdgeInsets.only(left: 5, right: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          status,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: failed && !item.waitingForConnection
                                ? colors.error
                                : colors.primary,
                          ),
                        ),
                      ),
                      if (uploading && !cancelling)
                        Text(
                          '${(progress * 100).round()}%',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      if (onCancel != null || cancelling)
                        SizedBox(
                          height: 27,
                          width: 27,
                          child: cancelling
                              ? const Padding(
                                  padding: EdgeInsets.all(6),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : IconButton(
                                  key: ValueKey('cancel-${item.id}'),
                                  tooltip: 'Cancel upload of ${item.filename}',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 26,
                                    minHeight: 26,
                                  ),
                                  iconSize: 16,
                                  onPressed: onCancel,
                                  icon: const Icon(Icons.close_rounded),
                                ),
                        ),
                    ],
                  ),
                ),
              ),
              if (failed && item.error?.isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.fromLTRB(5, 0, 5, 3),
                  child: Text(
                    item.registrationStarted
                        ? 'Cloud confirmation is pending. AirPix will retry automatically.'
                        : item.waitingForConnection
                        ? 'The cloud could not be reached. AirPix will retry automatically.'
                        : item.error!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 8, color: colors.error),
                  ),
                ),
            ],
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
                            ? 'Connection prepared — test shutter'
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
  const _PhotoPreview({required this.item, this.cacheWidth = 256});

  final TransferLedgerItem item;
  final int cacheWidth;

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
        cacheWidth: cacheWidth,
        errorBuilder: (_, _, _) => placeholder(),
      );
    }

    final Widget preview;
    if (previewable && item.localPath?.isNotEmpty == true) {
      preview = Image.file(
        File(item.localPath!),
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
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
