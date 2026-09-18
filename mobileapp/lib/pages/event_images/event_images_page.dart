import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:mobileapp/core/storage/active_event_storage.dart';
import 'package:mobileapp/core/theme/app_theme.dart';
import 'package:mobileapp/models/event_image_model.dart';
import 'package:mobileapp/models/event_invitation_model.dart';
import 'package:mobileapp/utilities/app_toast.dart';
import 'package:mobileapp/widgets/app_ui.dart';

enum _MediaFilter { all, live, hidden }

@RoutePage()
class EventImagesPage extends StatefulWidget {
  const EventImagesPage({super.key});

  @override
  State<EventImagesPage> createState() => _EventImagesPageState();
}

class _EventImagesPageState extends State<EventImagesPage> {
  Future<List<EventImageModel>>? _future;
  String? _eventId;
  _MediaFilter _filter = _MediaFilter.all;
  final _promptController = TextEditingController();

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<List<EventImageModel>> _loadEventImages(String eventId) async {
    final response = await DioHelper.get(
      '/eventImage/get-all',
      queryParameters: {'eventId': eventId},
    );
    final data = response.data['data'] as List? ?? [];
    return data
        .map(
          (item) =>
              EventImageModel.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<void> _deleteImage(EventSummary event, EventImageModel image) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete image'),
        content: const Text('Delete this image?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await DioHelper.delete(
        '/eventImage/delete',
        queryParameters: {'id': image.id},
      );
      AppToast.success('Image deleted');
      await _refresh(event);
    } catch (_) {
      AppToast.error('Failed to delete image');
    }
  }

  Future<void> _setPublished(
    EventSummary event,
    EventImageModel image,
    bool isPublished,
  ) async {
    try {
      await DioHelper.patch(
        '/eventImage/publish',
        data: {'isPublished': isPublished},
        queryParameters: {'id': image.id},
      );
      AppToast.success(isPublished ? 'Image published' : 'Image hidden');
      await _refresh(event);
    } catch (_) {
      AppToast.error('Failed to update publish status');
    }
  }

  Future<void> _enhanceImage(EventSummary event, EventImageModel image) async {
    _promptController.clear();
    final prompt = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enhance image'),
        content: TextField(
          controller: _promptController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Custom prompt',
            hintText: 'Optional if your plan allows it',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _promptController.text),
            child: const Text('Enhance'),
          ),
        ],
      ),
    );

    if (prompt == null) return;

    try {
      final response = await DioHelper.post(
        '/eventImage/enhance',
        data: {
          'id': image.id,
          if (prompt.trim().isNotEmpty) 'prompt': prompt.trim(),
        },
      );
      if (response.data['skipped'] == true) {
        AppToast.error('Enhance skipped. Not enough credits.');
      } else {
        AppToast.success('Image enhanced');
      }
      await _refresh(event);
    } catch (_) {
      AppToast.error('Failed to enhance image');
    }
  }

  void _openImageActions(EventSummary event, EventImageModel image) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                image.isPublished
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              title: Text(
                image.isPublished
                    ? 'Hide from live gallery'
                    : 'Publish to live gallery',
              ),
              onTap: () {
                Navigator.pop(context);
                _setPublished(event, image, !image.isPublished);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Share'),
              onTap: () {
                Navigator.pop(context);
                SharePlus.instance.share(
                  ShareParams(uri: Uri.parse(image.imageUrl)),
                );
              },
            ),
            if (image.mediaType != 'video')
              ListTile(
                leading: const Icon(Icons.auto_fix_high),
                title: const Text('Enhance'),
                onTap: () {
                  Navigator.pop(context);
                  _enhanceImage(event, image);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete'),
              onTap: () {
                Navigator.pop(context);
                _deleteImage(event, image);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refresh(EventSummary event) async {
    setState(() {
      _future = _loadEventImages(event.id);
      _eventId = event.id;
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: ActiveEventStorage.activeEvent,
      builder: (context, activeEvent, _) {
        if (activeEvent != null && _eventId != activeEvent.id) {
          _future = _loadEventImages(activeEvent.id);
          _eventId = activeEvent.id;
        }

        return Scaffold(
          appBar: AppBar(
            toolbarHeight: 82,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Uploaded media'),
                const SizedBox(height: 3),
                Text(
                  activeEvent?.title ?? 'No active event',
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
            actions: [
              if (activeEvent != null)
                IconButton.filledTonal(
                  tooltip: 'Refresh',
                  onPressed: () => _refresh(activeEvent),
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.muted,
                    foregroundColor: AppColors.foreground,
                  ),
                ),
              const SizedBox(width: 12),
            ],
          ),
          body: activeEvent == null
              ? const Center(child: Text('No active event selected.'))
              : FutureBuilder<List<EventImageModel>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('Failed to load images: ${snapshot.error}'),
                      );
                    }

                    final images = snapshot.data ?? [];
                    if (images.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: AppEmptyState(
                          icon: Icons.photo_library_outlined,
                          title: 'No photos yet',
                          message:
                              'Photos you upload for this event will appear here.',
                        ),
                      );
                    }

                    final filteredImages = switch (_filter) {
                      _MediaFilter.all => images,
                      _MediaFilter.live =>
                        images.where((image) => image.isPublished).toList(),
                      _MediaFilter.hidden =>
                        images.where((image) => !image.isPublished).toList(),
                    };
                    final liveCount = images
                        .where((image) => image.isPublished)
                        .length;

                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                AppCategoryChip(
                                  label: 'All ${images.length}',
                                  icon: Icons.grid_view_rounded,
                                  selected: _filter == _MediaFilter.all,
                                  onTap: () => setState(
                                    () => _filter = _MediaFilter.all,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                AppCategoryChip(
                                  label: 'Live $liveCount',
                                  icon: Icons.public_rounded,
                                  color: AppColors.secondary,
                                  selected: _filter == _MediaFilter.live,
                                  onTap: () => setState(
                                    () => _filter = _MediaFilter.live,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                AppCategoryChip(
                                  label: 'Hidden ${images.length - liveCount}',
                                  icon: Icons.visibility_off_outlined,
                                  color: const Color(0xFF78716C),
                                  selected: _filter == _MediaFilter.hidden,
                                  onTap: () => setState(
                                    () => _filter = _MediaFilter.hidden,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: filteredImages.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.all(20),
                                  child: AppEmptyState(
                                    icon: Icons.filter_alt_off_outlined,
                                    title: 'No media in this view',
                                    message:
                                        'Choose another filter to see uploaded media.',
                                  ),
                                )
                              : GridView.builder(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    0,
                                    20,
                                    28,
                                  ),
                                  itemCount: filteredImages.length,
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 2,
                                        crossAxisSpacing: 5,
                                        mainAxisSpacing: 5,
                                      ),
                                  itemBuilder: (context, index) {
                                    final image = filteredImages[index];
                                    return InkWell(
                                      onTap: () =>
                                          _openImageActions(activeEvent, image),
                                      borderRadius: BorderRadius.circular(10),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            image.mediaType == 'video'
                                                ? const ColoredBox(
                                                    color: Colors.black87,
                                                    child: Center(
                                                      child: Icon(
                                                        Icons.videocam_outlined,
                                                        color: Colors.white,
                                                        size: 42,
                                                      ),
                                                    ),
                                                  )
                                                : Image.network(
                                                    image.imageUrl,
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (_, _, _) =>
                                                        const ColoredBox(
                                                          color: Colors.black12,
                                                          child: Center(
                                                            child: Icon(
                                                              Icons
                                                                  .broken_image_outlined,
                                                            ),
                                                          ),
                                                        ),
                                                  ),
                                            Positioned(
                                              top: 8,
                                              right: 8,
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 7,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: image.isPublished
                                                      ? Colors.green.shade700
                                                      : Colors.black54,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        999,
                                                      ),
                                                ),
                                                child: Text(
                                                  image.isPublished
                                                      ? 'LIVE'
                                                      : 'HIDDEN',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            Positioned(
                                              left: 8,
                                              right: 8,
                                              bottom: 8,
                                              child: DecoratedBox(
                                                decoration: BoxDecoration(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.6),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        999,
                                                      ),
                                                ),
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 6,
                                                      ),
                                                  child: Text(
                                                    image.isEnhanced
                                                        ? 'Enhanced'
                                                        : image.takenBy ??
                                                              'Uploaded',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    );
                  },
                ),
        );
      },
    );
  }
}
