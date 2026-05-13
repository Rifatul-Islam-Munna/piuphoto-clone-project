import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:mobileapp/core/storage/active_event_storage.dart';
import 'package:mobileapp/models/event_image_model.dart';
import 'package:mobileapp/models/event_invitation_model.dart';

@RoutePage()
class EventImagesPage extends StatefulWidget {
  const EventImagesPage({super.key});

  @override
  State<EventImagesPage> createState() => _EventImagesPageState();
}

class _EventImagesPageState extends State<EventImagesPage> {
  Future<List<EventImageModel>>? _future;
  String? _eventId;

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
                        return ClipRRect(
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
                                      image.referenceId?.isNotEmpty ?? false
                                          ? image.referenceId!
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
