import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:mobileapp/core/storage/active_event_storage.dart';
import 'package:mobileapp/models/event_image_model.dart';
import 'package:mobileapp/models/event_invitation_model.dart';
import 'package:mobileapp/utilities/app_toast.dart';

@RoutePage()
class EventImagesPage extends StatefulWidget {
  const EventImagesPage({super.key});

  @override
  State<EventImagesPage> createState() => _EventImagesPageState();
}

class _EventImagesPageState extends State<EventImagesPage> {
  Future<List<EventImageModel>>? _future;
  String? _eventId;
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
          (item) => EventImageModel.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
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
      await DioHelper.delete('/eventImage/delete', queryParameters: {'id': image.id});
      AppToast.success('Image deleted');
      await _refresh(event);
    } catch (_) {
      AppToast.error('Failed to delete image');
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
              leading: const Icon(Icons.share_outlined),
              title: const Text('Share'),
              onTap: () {
                Navigator.pop(context);
                SharePlus.instance.share(ShareParams(uri: Uri.parse(image.imageUrl)));
              },
            ),
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
            title: Text(activeEvent?.title ?? 'Uploaded images'),
            actions: [
              if (activeEvent != null)
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: () => _refresh(activeEvent),
                  icon: const Icon(Icons.refresh),
                ),
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
                      return const Center(
                        child: Text('No images uploaded for this event.'),
                      );
                    }

                    return GridView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: images.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemBuilder: (context, index) {
                        final image = images[index];
                        return InkWell(
                          onTap: () => _openImageActions(activeEvent, image),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.network(
                                image.imageUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const ColoredBox(
                                  color: Colors.black12,
                                  child: Center(
                                    child: Icon(Icons.broken_image_outlined),
                                  ),
                                ),
                              ),
                              Positioned(
                                left: 8,
                                right: 8,
                                bottom: 8,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: Text(
                                      image.isEnhanced
                                          ? 'Enhanced'
                                          : image.takenBy ?? 'Uploaded',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
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
                    );
                  },
                ),
        );
      },
    );
  }
}
