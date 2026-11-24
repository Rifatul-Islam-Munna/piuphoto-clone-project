import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobileapp/core/utils/image_loader.dart';
import 'package:mobileapp/core/upload/transfer_ledger_storage.dart';
import 'package:mobileapp/core/upload/upload_queue_service.dart';
import 'package:mobileapp/core/upload/upload_queue_storage.dart';
import 'package:mobileapp/pages/upload/camera_upload_preferences_sheet.dart';
import 'package:mobileapp/pages/upload/manual_camera_staging.dart';
import 'package:mobileapp/core/theme/app_theme.dart';

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

@immutable
class PickedTransferPhoto {
  const PickedTransferPhoto({required this.path, required this.filename});

  final String path;
  final String filename;
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
    this.manualCaptureMode,
    this.manualInbox,
    this.onChangeManualMode,
    this.onUploadManual,
    this.onDiscardManual,
    this.onShareGallery,
    this.onShareGuestQr,
    this.onShareFaceQr,
    this.onPreviewGallery,
    this.onViewHistory,
    this.onCameraSetupHelp,
    this.onCameraOptions,
    this.onInvitePhotographers,
    this.onRepeatPickedSource,
    this.enhancementControl,
    this.onAddPickedPhotos,
    this.onClearPickedPhotos,
    this.onRemovePickedPhoto,
    this.onUploadPickedPhotos,
    this.pickedPhotos,
    this.pickedUploading,
    this.selectedSource,
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
  final ValueListenable<bool>? manualCaptureMode;
  final ValueListenable<List<ManualCameraPhoto>>? manualInbox;
  final Future<void> Function(bool manual)? onChangeManualMode;
  final Future<void> Function(List<String> ids)? onUploadManual;
  final Future<void> Function(List<String> ids)? onDiscardManual;
  final VoidCallback? onShareGallery;
  final VoidCallback? onShareGuestQr;
  final VoidCallback? onShareFaceQr;
  final VoidCallback? onPreviewGallery;
  final VoidCallback? onViewHistory;
  final VoidCallback? onCameraSetupHelp;
  final VoidCallback? onCameraOptions;
  final VoidCallback? onInvitePhotographers;
  final VoidCallback? onRepeatPickedSource;
  final Widget? enhancementControl;
  final VoidCallback? onAddPickedPhotos;
  final VoidCallback? onClearPickedPhotos;
  final ValueChanged<String>? onRemovePickedPhoto;
  final Future<void> Function()? onUploadPickedPhotos;
  final ValueListenable<List<PickedTransferPhoto>>? pickedPhotos;
  final ValueListenable<bool>? pickedUploading;
  final String? selectedSource;
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
  final Set<String> _selectedManualIds = {};
  bool _manualActionBusy = false;
  bool _stopping = false;
  bool _showGrid = true;
  _TransferFilter _filter = _TransferFilter.all;
  Timer? _countdownTimer;

  ValueListenable<List<TransferLedgerItem>> get _transfers =>
      widget.transfers ?? TransferLedgerStorage.items;
  ValueListenable<List<PendingUploadItem>> get _queue =>
      widget.queue ?? UploadQueueStorage.items;

  bool get _isSelectedPhotoSource => const {
    'phone',
    'phone-camera',
    'camera',
    'files',
  }.contains(widget.selectedSource);

  String get _repeatSourceLabel => switch (widget.selectedSource) {
    'phone' => 'Select more from gallery',
    'phone-camera' => 'Take another photo',
    'camera' => 'Select more camera photos',
    'files' => 'Select more files',
    _ => 'Add photos',
  };

  IconData get _repeatSourceIcon => switch (widget.selectedSource) {
    'phone' => Icons.photo_library_outlined,
    'phone-camera' => Icons.add_a_photo_outlined,
    'camera' => Icons.usb_rounded,
    'files' => Icons.sd_storage_outlined,
    _ => Icons.add_photo_alternate_outlined,
  };

  void _onPickedPhotosChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _queue.addListener(_syncCountdown);
    widget.pickedPhotos?.addListener(_onPickedPhotosChanged);
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
    if (!identical(oldWidget.pickedPhotos, widget.pickedPhotos)) {
      oldWidget.pickedPhotos?.removeListener(_onPickedPhotosChanged);
      widget.pickedPhotos?.addListener(_onPickedPhotosChanged);
    }
    _syncCountdown();
  }

  @override
  void dispose() {
    _queue.removeListener(_syncCountdown);
    widget.pickedPhotos?.removeListener(_onPickedPhotosChanged);
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

  Future<void> _showUploadPreferences() async {
    final mode = widget.manualCaptureMode;
    final update = widget.onChangeManualMode;
    if (mode == null || update == null) return;
    final selected = await showCameraUploadPreferencesSheet(
      context,
      manualSelection: mode.value,
    );
    if (selected != null && mounted) await update(selected);
  }

  Future<void> _uploadManualSelection(List<String> ids) async {
    final send = widget.onUploadManual;
    if (send == null || ids.isEmpty || _manualActionBusy) return;
    setState(() => _manualActionBusy = true);
    try {
      await send(ids);
      if (mounted) setState(() => _selectedManualIds.removeAll(ids));
    } finally {
      if (mounted) setState(() => _manualActionBusy = false);
    }
  }

  Future<void> _discardManualSelection(List<String> ids) async {
    final discard = widget.onDiscardManual;
    if (discard == null || ids.isEmpty || _manualActionBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove local copies?'),
        content: Text(
          'Remove ${ids.length} selected photos from this phone review queue? Original photos on the camera will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _manualActionBusy = true);
    try {
      await discard(ids);
      if (mounted) setState(() => _selectedManualIds.removeAll(ids));
    } finally {
      if (mounted) setState(() => _manualActionBusy = false);
    }
  }

  Widget _buildManualInbox() {
    final mode = widget.manualCaptureMode!;
    final inbox = widget.manualInbox!;
    return ValueListenableBuilder<bool>(
      valueListenable: mode,
      builder: (context, manual, _) => ValueListenableBuilder<List<ManualCameraPhoto>>(
        valueListenable: inbox,
        builder: (context, all, _) {
          final pending =
              all
                  .where(
                    (photo) =>
                        photo.isPending && photo.eventId == widget.eventId,
                  )
                  .toList()
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          if (!manual && pending.isEmpty) return const SizedBox.shrink();
          final availableIds = pending.map((photo) => photo.id).toSet();
          final selected = _selectedManualIds
              .intersection(availableIds)
              .toList();
          return Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            color: AppColors.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: AppColors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        manual
                            ? Icons.checklist_rounded
                            : Icons.photo_library_outlined,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          manual
                              ? 'Select & Upload'
                              : 'Photos awaiting approval',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        '${pending.length} pending',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    manual
                        ? 'Photos stay on this phone until you select them. No cloud upload happens before approval.'
                        : 'Previously captured manual photos still need approval.',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.mutedForeground,
                      height: 1.4,
                    ),
                  ),
                  if (pending.isEmpty) ...[
                    const SizedBox(height: 12),
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Nothing to review yet. Take a photo with your connected camera.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.mutedForeground,
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${selected.length} selected',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        TextButton(
                          onPressed: _manualActionBusy
                              ? null
                              : () => setState(() {
                                  if (selected.length == pending.length) {
                                    _selectedManualIds.removeAll(availableIds);
                                  } else {
                                    _selectedManualIds.addAll(availableIds);
                                  }
                                }),
                          child: Text(
                            selected.length == pending.length
                                ? 'Deselect all'
                                : 'Select all',
                          ),
                        ),
                      ],
                    ),
                    SizedBox(
                      height: pending.length > 3 ? 264 : 126,
                      child: GridView.builder(
                        itemCount: pending.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 7,
                              mainAxisSpacing: 7,
                              childAspectRatio: .93,
                            ),
                        itemBuilder: (context, index) {
                          final photo = pending[index];
                          final checked = _selectedManualIds.contains(photo.id);
                          return InkWell(
                            key: ValueKey('review-${photo.id}'),
                            borderRadius: BorderRadius.circular(9),
                            onTap: _manualActionBusy
                                ? null
                                : () => setState(() {
                                    if (!checked) {
                                      _selectedManualIds.add(photo.id);
                                    } else {
                                      _selectedManualIds.remove(photo.id);
                                    }
                                  }),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(9),
                                  child: Image.file(
                                    File(photo.path),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, error, stackTrace) =>
                                        const ColoredBox(
                                          color: AppColors.accentSoft,
                                          child: Icon(
                                            Icons.photo_outlined,
                                            color: AppColors.primary,
                                            size: 30,
                                          ),
                                        ),
                                  ),
                                ),
                                Positioned(
                                  right: 5,
                                  top: 5,
                                  child: Icon(
                                    checked
                                        ? Icons.check_circle_rounded
                                        : Icons.radio_button_unchecked_rounded,
                                    color: checked
                                        ? AppColors.primary
                                        : Colors.white,
                                    size: 25,
                                    shadows: const [
                                      Shadow(
                                        color: Colors.black54,
                                        blurRadius: 3,
                                      ),
                                    ],
                                  ),
                                ),
                                Positioned(
                                  bottom: 0,
                                  left: 0,
                                  right: 0,
                                  child: Container(
                                    color: Colors.black54,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 3,
                                    ),
                                    child: Text(
                                      photo.filename,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _manualActionBusy || selected.isEmpty
                                ? null
                                : () => _discardManualSelection(selected),
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                            ),
                            label: const Text('Remove'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: _manualActionBusy || selected.isEmpty
                                ? null
                                : () => _uploadManualSelection(selected),
                            icon: _manualActionBusy
                                ? const SizedBox(
                                    width: 15,
                                    height: 15,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.cloud_upload_outlined,
                                    size: 18,
                                  ),
                            label: Text('Upload selected (${selected.length})'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPickedPhotos() {
    final photos = widget.pickedPhotos;
    if (photos == null) return const SizedBox.shrink();
    return ValueListenableBuilder<List<PickedTransferPhoto>>(
      valueListenable: photos,
      builder: (context, selected, _) {
        if (selected.isEmpty) return const SizedBox.shrink();
        return Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          color: AppColors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: AppColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.photo_library_outlined,
                      size: 20,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        'Selected photos (${selected.length})',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (widget.onAddPickedPhotos != null)
                      TextButton(
                        onPressed: widget.onAddPickedPhotos,
                        child: const Text('Add'),
                      ),
                    if (widget.onClearPickedPhotos != null)
                      TextButton(
                        onPressed: widget.onClearPickedPhotos,
                        child: const Text('Clear'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: selected.length > 3 ? 220 : 112,
                  child: GridView.builder(
                    primary: false,
                    itemCount: selected.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 7,
                          crossAxisSpacing: 7,
                          childAspectRatio: 1,
                        ),
                    itemBuilder: (context, index) {
                      final photo = selected[index];
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(photo.path),
                              fit: BoxFit.cover,
                              errorBuilder: (_, error, stackTrace) =>
                                  const ColoredBox(
                                    color: AppColors.accentSoft,
                                    child: Icon(
                                      Icons.photo_outlined,
                                      size: 30,
                                      color: AppColors.primary,
                                    ),
                                  ),
                            ),
                          ),
                          Positioned(
                            right: 3,
                            top: 3,
                            child: IconButton.filledTonal(
                              key: ValueKey('remove-picked-${photo.path}'),
                              tooltip: 'Remove ${photo.filename}',
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints(
                                minWidth: 28,
                                minHeight: 28,
                              ),
                              padding: EdgeInsets.zero,
                              iconSize: 16,
                              onPressed: widget.onRemovePickedPhoto == null
                                  ? null
                                  : () =>
                                        widget.onRemovePickedPhoto!(photo.path),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 3,
                              ),
                              color: Colors.black54,
                              child: Text(
                                photo.filename,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                if (widget.onUploadPickedPhotos != null)
                  ValueListenableBuilder<bool>(
                    valueListenable:
                        widget.pickedUploading ??
                        const AlwaysStoppedAnimation<bool>(false),
                    builder: (context, uploading, _) => SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: uploading
                            ? null
                            : () => widget.onUploadPickedPhotos?.call(),
                        icon: uploading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.cloud_upload_outlined),
                        label: Text(
                          uploading
                              ? 'Uploading selected photos...'
                              : 'Upload selected (${selected.length})',
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  PopupMenuItem<String> _menuAction(
    String value,
    String title,
    IconData icon,
  ) => PopupMenuItem<String>(
    value: value,
    height: 53,
    child: Row(
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.accentSoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: AppColors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        actions: [
          if (widget.onShareGuestQr != null || widget.onShareGallery != null)
            IconButton(
              tooltip: 'Share album QR code',
              style: IconButton.styleFrom(
                backgroundColor: AppColors.accentSoft,
                foregroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: widget.onShareGuestQr ?? widget.onShareGallery,
              icon: const Icon(Icons.share_rounded, size: 20),
            ),
          PopupMenuButton<String>(
            tooltip: 'More camera transfer actions',
            position: PopupMenuPosition.under,
            offset: const Offset(0, 6),
            color: AppColors.card,
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: AppColors.border),
            ),
            constraints: const BoxConstraints(minWidth: 245, maxWidth: 295),
            onSelected: (value) {
              switch (value) {
                case 'upload-settings':
                  _showUploadPreferences();
                case 'camera-options':
                  widget.onCameraOptions?.call();
                case 'invite':
                  widget.onInvitePhotographers?.call();
                case 'add-photos':
                  widget.onAddPickedPhotos?.call();
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
            itemBuilder: (_) => [
              if (widget.onAddPickedPhotos != null)
                _menuAction(
                  'add-photos',
                  'Choose more photos',
                  Icons.add_photo_alternate_outlined,
                ),
              if (widget.onInvitePhotographers != null)
                _menuAction(
                  'invite',
                  'Invite photographers',
                  Icons.group_add_outlined,
                ),
              if (widget.onChangeManualMode != null)
                _menuAction(
                  'upload-settings',
                  'Upload settings',
                  Icons.tune_rounded,
                ),
              if (widget.onCameraOptions != null)
                _menuAction(
                  'camera-options',
                  'Camera options',
                  Icons.settings_input_component_outlined,
                ),
              const PopupMenuDivider(height: 8),
              if (widget.connectionDetailsBuilder != null)
                _menuAction(
                  'details',
                  'Connection details',
                  Icons.cable_rounded,
                ),
              if (widget.onPreviewGallery != null)
                _menuAction(
                  'preview',
                  'Preview Photo Live',
                  Icons.preview_outlined,
                ),
              _menuAction(
                _showGrid ? 'view-list' : 'view-grid',
                _showGrid ? 'List view' : 'Grid view',
                _showGrid ? Icons.view_list_rounded : Icons.grid_view_rounded,
              ),
              if (widget.onViewHistory != null)
                _menuAction(
                  'history',
                  'Transfer history',
                  Icons.history_rounded,
                ),
              if (widget.onShareGuestQr != null)
                _menuAction('qr', 'Share gallery QR', Icons.qr_code_2_rounded),
              if (widget.onShareFaceQr != null)
                _menuAction(
                  'face-qr',
                  'Share face-delivery QR',
                  Icons.face_retouching_natural_outlined,
                ),
            ],
            icon: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.accentSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.more_horiz_rounded,
                color: AppColors.primary,
                size: 22,
              ),
            ),
          ),
        ],
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.eventTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              'Camera transfers',
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
              builder: (context, session, _) => ValueListenableBuilder<List<TransferLedgerItem>>(
                valueListenable: _transfers,
                builder: (context, allItems, _) => ValueListenableBuilder<List<PendingUploadItem>>(
                  valueListenable: _queue,
                  builder: (context, queued, _) {
                    final since = widget.startedAt?.millisecondsSinceEpoch;
                    final items =
                        allItems
                            .where(
                              (item) =>
                                  item.eventId == widget.eventId &&
                                  (since == null || item.createdAt >= since),
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
                        widget.canCancel ?? UploadQueueService.canCancel;
                    final filtered = items
                        .where((item) => _transferMatches(item, _filter))
                        .toList(growable: false);
                    return CustomScrollView(
                      key: PageStorageKey(
                        'camera-transfers-${widget.eventId}-$since',
                      ),
                      slivers: [
                        if (widget.pickedPhotos != null)
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                            sliver: SliverToBoxAdapter(
                              child: _buildPickedPhotos(),
                            ),
                          ),
                        if (widget.manualCaptureMode != null &&
                            widget.manualInbox != null)
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                            sliver: SliverToBoxAdapter(
                              child: _buildManualInbox(),
                            ),
                          ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                          sliver: SliverToBoxAdapter(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_isSelectedPhotoSource && !session.isActive)
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(13),
                                    decoration: BoxDecoration(
                                      color: AppColors.accentSoft,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              (widget
                                                          .pickedPhotos
                                                          ?.value
                                                          .isNotEmpty ??
                                                      false)
                                                  ? Icons
                                                        .check_circle_outline_rounded
                                                  : Icons
                                                        .add_photo_alternate_outlined,
                                              color: AppColors.primary,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                (widget
                                                            .pickedPhotos
                                                            ?.value
                                                            .isNotEmpty ??
                                                        false)
                                                    ? 'Photos ready to upload'
                                                    : 'Add photos to this album',
                                                maxLines: 2,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          (widget
                                                      .pickedPhotos
                                                      ?.value
                                                      .isNotEmpty ??
                                                  false)
                                              ? '${widget.pickedPhotos!.value.length} selected. Review your photos before uploading.'
                                              : 'Choose more photos here anytime. Uploaded photos stay in the gallery below.',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.mutedForeground,
                                          ),
                                        ),
                                        if (widget.onRepeatPickedSource !=
                                            null) ...[
                                          const SizedBox(height: 10),
                                          SizedBox(
                                            width: double.infinity,
                                            child: FilledButton.tonalIcon(
                                              key: const Key(
                                                'repeat-upload-source',
                                              ),
                                              onPressed:
                                                  widget.onRepeatPickedSource,
                                              icon: Icon(
                                                _repeatSourceIcon,
                                                size: 18,
                                              ),
                                              label: Text(_repeatSourceLabel),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  )
                                else
                                  _SessionHeader(
                                    session: session,
                                    items: items,
                                    stopping: _stopping,
                                    onStop: widget.onStop == null
                                        ? null
                                        : _stop,
                                  ),
                                if (widget.enhancementControl != null) ...[
                                  const SizedBox(height: 12),
                                  widget.enhancementControl!,
                                ],
                                const SizedBox(height: 12),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      for (final filter
                                          in _TransferFilter.values)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            right: 6,
                                          ),
                                          child: ChoiceChip(
                                            key: ValueKey(
                                              'filter-${filter.name}',
                                            ),
                                            visualDensity:
                                                VisualDensity.compact,
                                            label: Text(
                                              '${_filterTitle(filter)} ${items.where((item) => _transferMatches(item, filter)).length + ((filter == _TransferFilter.all || filter == _TransferFilter.notUploaded) ? (widget.pickedPhotos?.value.length ?? 0) : 0)}',
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
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (items.isEmpty)
                          SliverToBoxAdapter(
                            child: _EmptyTransfers(
                              session: session,
                              onCameraSetupHelp: widget.onCameraSetupHelp,
                            ),
                          )
                        else if (filtered.isEmpty)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Center(
                                child: Text(
                                  'No ${_filterTitle(_filter).toLowerCase()} photos',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                            ),
                          )
                        else if (_showGrid)
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(10, 0, 10, 24),
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
                                      cancelling: _cancelling.contains(item.id),
                                      onCancel: canCancel(item)
                                          ? () => _cancel(item)
                                          : null,
                                      onTap: () => _showPhotoDetails(item),
                                    );
                                  }, childCount: filtered.length),
                                );
                              },
                            ),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate((
                                context,
                                index,
                              ) {
                                final item = filtered[index];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _TransferPhotoCard(
                                    key: ValueKey(item.id),
                                    item: item,
                                    queued: queueById[item.id],
                                    cancelling: _cancelling.contains(item.id),
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
      if (!previewable || item.displayUrl?.isNotEmpty != true) {
        return placeholder();
      }
      return ImageLoader.loadImage(
        item.displayUrl,
        fallbackUrl: item.imageUrl,
        fit: BoxFit.cover,
        errorWidget: placeholder(),
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
