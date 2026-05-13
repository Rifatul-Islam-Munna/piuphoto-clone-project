import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:mobileapp/core/platform/image_downloads.dart';
import 'package:mobileapp/models/event_image_model.dart';
import 'package:mobileapp/utilities/app_toast.dart';

class EventGalleryPage extends StatefulWidget {
  const EventGalleryPage({
    super.key,
    required this.eventId,
  });

  final String eventId;

  @override
  State<EventGalleryPage> createState() => _EventGalleryPageState();
}

class _EventGalleryPageState extends State<EventGalleryPage> {
  static const _pageSize = 20;

  final _scrollController = ScrollController();
  final List<EventImageModel> _allImages = [];
  final Set<String> _selectedIds = {};
  int _visibleCount = _pageSize;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _scrollController.addListener(_loadMoreWhenNeeded);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await DioHelper.get(
        '/eventImage/get-all',
        queryParameters: {'eventId': widget.eventId},
      );
      final data = response.data['data'] as List? ?? [];
      final images = data
          .map(
            (item) => EventImageModel.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
      setState(() {
        _allImages
          ..clear()
          ..addAll(images);
        _visibleCount = images.length < _pageSize ? images.length : _pageSize;
      });
    } catch (error) {
      setState(() => _error = 'Failed to load event images');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _loadMoreWhenNeeded() {
    if (_scrollController.position.extentAfter > 500) return;
    if (_visibleCount >= _allImages.length) return;
    setState(() {
      _visibleCount = (_visibleCount + _pageSize).clamp(0, _allImages.length);
    });
  }

  String _filenameFor(EventImageModel image) {
    final uri = Uri.tryParse(image.imageUrl);
    final name = uri?.pathSegments.isNotEmpty ?? false
        ? uri!.pathSegments.last
        : '';
    if (name.contains('.')) return name;
    return 'event-image-${image.id}.jpg';
  }

  Future<void> _saveImages(List<EventImageModel> images) async {
    if (images.isEmpty) {
      AppToast.error('Select images first');
      return;
    }

    setState(() => _saving = true);
    var saved = 0;
    try {
      for (final image in images) {
        final response = await DioHelper.dio.get<List<int>>(
          image.imageUrl,
          options: Options(responseType: ResponseType.bytes),
        );
        final bytes = Uint8List.fromList(response.data ?? []);
        if (bytes.isEmpty) continue;

        final didSave = await ImageDownloads.saveImage(
          bytes: bytes,
          filename: _filenameFor(image),
        );
        if (didSave) saved += 1;
      }

      AppToast.success('Downloaded $saved images');
    } catch (_) {
      AppToast.error('Failed to download images');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _allImages.take(_visibleCount).toList();
    final selectedImages = _allImages
        .where((image) => _selectedIds.contains(image.id))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Event photos'),
        actions: [
          IconButton(
            tooltip: 'Download selected',
            onPressed: _saving ? null : () => _saveImages(selectedImages),
            icon: const Icon(Icons.download_outlined),
          ),
          TextButton(
            onPressed: _saving ? null : () => _saveImages(_allImages),
            child: const Text('All'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _allImages.isEmpty
                  ? const Center(child: Text('No photos found.'))
                  : GridView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(12),
                      itemCount: visible.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                      ),
                      itemBuilder: (context, index) {
                        final image = visible[index];
                        final selected = _selectedIds.contains(image.id);

                        return InkWell(
                          onTap: () {
                            setState(() {
                              selected
                                  ? _selectedIds.remove(image.id)
                                  : _selectedIds.add(image.id);
                            });
                          },
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  image.imageUrl,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: CircleAvatar(
                                  radius: 14,
                                  backgroundColor: selected
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.black54,
                                  child: Icon(
                                    selected ? Icons.check : Icons.circle,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
    );
  }
}
