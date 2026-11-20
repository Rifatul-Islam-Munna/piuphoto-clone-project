import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobileapp/core/upload/transfer_ledger_storage.dart';

/// Always-visible overview on the Upload page. The full searchable/filterable
/// photo grid lives in CameraTransferPage and uses this same persistent ledger.
class UploadTransferOverview extends StatelessWidget {
  const UploadTransferOverview({
    super.key,
    required this.eventId,
    required this.onViewAll,
    this.transfers,
  });

  final String eventId;
  final VoidCallback onViewAll;
  final ValueListenable<List<TransferLedgerItem>>? transfers;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<TransferLedgerItem>>(
      valueListenable: transfers ?? TransferLedgerStorage.items,
      builder: (context, all, _) {
        final items = all.where((item) => item.eventId == eventId).toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        if (items.isEmpty) return const SizedBox.shrink();

        final uploaded = items.where((item) => item.isUploaded).length;
        final uploading = items
            .where(
              (item) =>
                  item.status == TransferLedgerStatus.uploading ||
                  (item.status == TransferLedgerStatus.processing &&
                      !item.isUploaded),
            )
            .length;
        final failed = items
            .where((item) => item.status == TransferLedgerStatus.failed)
            .length;
        final waiting = items.length - uploaded - uploading - failed;
        final palette = Theme.of(context).colorScheme;

        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.grid_view_rounded, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Recent photo uploads',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: onViewAll,
                      icon: const Icon(Icons.open_in_full_rounded, size: 15),
                      label: const Text('View grid'),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 9,
                  runSpacing: 3,
                  children:
                      [
                            Text('${items.length} received'),
                            Text('$uploaded uploaded'),
                            Text('$uploading uploading'),
                            Text('$waiting not uploaded'),
                            Text('$failed failed'),
                          ]
                          .map(
                            (text) => DefaultTextStyle(
                              style: TextStyle(
                                fontSize: 10.5,
                                color: palette.onSurfaceVariant,
                              ),
                              child: text,
                            ),
                          )
                          .toList(),
                ),
                const SizedBox(height: 9),
                GridView.builder(
                  key: const ValueKey('upload-overview-grid'),
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length > 6 ? 6 : items.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                    childAspectRatio: 1.0,
                  ),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final label = item.isUploaded
                        ? 'Uploaded'
                        : item.status == TransferLedgerStatus.failed
                        ? 'Failed'
                        : item.status == TransferLedgerStatus.uploading
                        ? 'Uploading ${item.progress}%'
                        : 'Not uploaded';
                    return ClipRRect(
                      key: ValueKey('overview-photo-${item.id}'),
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _thumb(item),
                          Positioned(
                            top: 3,
                            right: 3,
                            child: Container(
                              decoration: BoxDecoration(
                                color:
                                    item.status == TransferLedgerStatus.failed
                                    ? palette.error
                                    : Colors.black87,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              child: Text(
                                label,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: ColoredBox(
                              color: Colors.black54,
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Text(
                                  item.filename,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                if (items.length > 6)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      'Showing the latest 6 photos. Open View grid for all ${items.length}.',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _thumb(TransferLedgerItem item) {
    Widget placeholder() => const ColoredBox(
      color: Color(0xFF353941),
      child: Center(child: Icon(Icons.image_outlined, color: Colors.white70)),
    );
    final filename = item.filename.toLowerCase();
    if (![
      '.jpg',
      '.jpeg',
      '.png',
      '.webp',
      '.heic',
      '.heif',
    ].any(filename.endsWith)) {
      return placeholder();
    }
    Widget network() => item.imageUrl?.isNotEmpty == true
        ? Image.network(
            item.imageUrl!,
            fit: BoxFit.cover,
            cacheWidth: 280,
            errorBuilder: (_, _, _) => placeholder(),
          )
        : placeholder();
    if (item.localPath?.isNotEmpty == true) {
      return Image.file(
        File(item.localPath!),
        fit: BoxFit.cover,
        cacheWidth: 280,
        errorBuilder: (_, _, _) => network(),
      );
    }
    return network();
  }
}
