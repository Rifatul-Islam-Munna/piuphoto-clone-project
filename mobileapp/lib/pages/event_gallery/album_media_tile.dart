import 'package:flutter/material.dart';
import 'package:mobileapp/core/theme/app_theme.dart';
import 'package:mobileapp/core/utils/image_loader.dart';
import 'package:mobileapp/models/event_image_model.dart';

/// One compact media thumbnail in the Album Management grid.
///
/// Tapping selects the photo for bulk actions; double-tapping a photo or
/// pressing its visible expand button opens the original in full-screen.
class AlbumMediaTile extends StatelessWidget {
  const AlbumMediaTile({
    super.key,
    required this.image,
    required this.label,
    required this.selected,
    required this.onSelect,
    required this.onOpen,
    this.preview,
  });

  final EventImageModel image;
  final String label;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onOpen;

  /// Optional alternate preview, useful for offline media and tests.
  final Widget? preview;

  bool get _isVideo => image.mediaType.toLowerCase() == 'video';

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        InkWell(
          key: ValueKey('album-media-${image.id}'),
          onTap: onSelect,
          onDoubleTap: _isVideo ? null : onOpen,
          onLongPress: onSelect,
          borderRadius: BorderRadius.circular(8),
          child: Column(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_isVideo)
                        const ColoredBox(
                          color: Color(0xFF202124),
                          child: Center(
                            child: Icon(
                              Icons.play_circle_outline_rounded,
                              color: Colors.white,
                              size: 38,
                            ),
                          ),
                        )
                      else
                        preview ?? ImageLoader.loadImage(image.imageUrl),
                      if (selected)
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: .18),
                            border: Border.all(
                              color: AppColors.primary,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      Positioned(
                        top: 7,
                        right: 7,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.primary
                                : Colors.black.withValues(alpha: .28),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.4),
                          ),
                          child: Icon(
                            selected ? Icons.check : Icons.circle_outlined,
                            color: Colors.white,
                            size: 15,
                          ),
                        ),
                      ),
                      Positioned(
                        left: 7,
                        bottom: 7,
                        child: Icon(
                          image.isPublished ? Icons.check_circle : Icons.lock,
                          color: image.isPublished
                              ? const Color(0xFF34C759)
                              : Colors.white,
                          size: 18,
                          shadows: const [
                            Shadow(color: Colors.black54, blurRadius: 5),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                height: 25,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.mutedForeground,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!_isVideo)
          Positioned(
            right: 5,
            bottom: 30,
            child: Material(
              color: Colors.black.withValues(alpha: .62),
              borderRadius: BorderRadius.circular(8),
              child: IconButton(
                key: ValueKey('view-photo-${image.id}'),
                tooltip: 'View full screen',
                onPressed: onOpen,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                padding: EdgeInsets.zero,
                icon: const Icon(
                  Icons.open_in_full_rounded,
                  color: Colors.white,
                  size: 17,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Shows the full-resolution photo, with pinch-to-zoom and pan gestures.
class AlbumPhotoViewerPage extends StatelessWidget {
  const AlbumPhotoViewerPage({
    super.key,
    required this.imageUrl,
    required this.label,
  });

  final String imageUrl;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        leading: IconButton(
          tooltip: 'Close photo',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
        ),
        title: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          panEnabled: true,
          child: SizedBox.expand(
            child: ImageLoader.loadImage(
              imageUrl,
              fit: BoxFit.contain,
              placeholder: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
              errorWidget: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white70,
                      size: 42,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Photo could not be loaded',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
