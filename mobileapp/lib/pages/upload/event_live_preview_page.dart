import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/intl.dart';
import 'package:mobileapp/core/guest/guest_qr_payload.dart';
import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:url_launcher/url_launcher.dart';

/// A read-only, authenticated Photo Live preview of cloud-registered event
/// images. Unlike the public website, it also shows photos awaiting publication.
class LiveEventPhoto {
  const LiveEventPhoto({
    required this.id,
    required this.imageUrl,
    required this.createdAt,
    this.isPublished = true,
    this.mediaType = 'photo',
  });

  final String id;
  final String imageUrl;
  final DateTime createdAt;
  final bool isPublished;
  final String mediaType;

  factory LiveEventPhoto.fromJson(Map<String, dynamic> json) {
    return LiveEventPhoto(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      imageUrl: (json['imageUrl'] ?? '').toString(),
      createdAt:
          DateTime.tryParse((json['createdAt'] ?? '').toString())?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      isPublished: json['isPublished'] != false,
      mediaType: (json['mediaType'] ?? 'photo').toString(),
    );
  }
}

class LiveEventPhotoPage {
  const LiveEventPhotoPage({
    required this.photos,
    required this.hasMore,
    required this.total,
  });

  final List<LiveEventPhoto> photos;
  final bool hasMore;
  final int total;

  factory LiveEventPhotoPage.fromJson(Map<String, dynamic> json) {
    final rows = json['data'];
    return LiveEventPhotoPage(
      photos: [
        if (rows is List)
          for (final row in rows)
            if (row is Map)
              LiveEventPhoto.fromJson(Map<String, dynamic>.from(row)),
      ],
      hasMore: json['hasNextPage'] == true,
      total: int.tryParse(json['totalItems']?.toString() ?? '') ?? 0,
    );
  }
}

typedef LoadLiveEventPhotos = Future<LiveEventPhotoPage> Function(int page);

class EventLivePreviewPage extends StatefulWidget {
  const EventLivePreviewPage({
    super.key,
    required this.eventId,
    required this.eventTitle,
    this.loadPhotos,
  });

  final String eventId;
  final String eventTitle;
  final LoadLiveEventPhotos? loadPhotos;

  @override
  State<EventLivePreviewPage> createState() => _EventLivePreviewPageState();
}

class _EventLivePreviewPageState extends State<EventLivePreviewPage> {
  final List<LiveEventPhoto> _photos = [];
  Timer? _poller;
  int _nextPage = 1;
  int _total = 0;
  bool _hasMore = true;
  bool _loading = false;
  bool _refreshing = false;
  String? _error;

  Future<LiveEventPhotoPage> _fetch(int page) async {
    if (widget.loadPhotos != null) return widget.loadPhotos!(page);
    final response = await DioHelper.get(
      '/eventImage/get-all',
      queryParameters: {'eventId': widget.eventId, 'page': page, 'limit': 100},
    );
    final data = response.data;
    if (data is! Map) throw StateError('Unexpected gallery response');
    return LiveEventPhotoPage.fromJson(Map<String, dynamic>.from(data));
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadMore());
    // Preview stays live even when the photographer keeps shooting.
    _poller = Timer.periodic(
      const Duration(seconds: 8),
      (_) => unawaited(_refreshLatest()),
    );
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _fetch(_nextPage);
      if (!mounted) return;
      setState(() {
        final existing = _photos.map((photo) => photo.id).toSet();
        _photos.addAll(
          result.photos.where(
            (photo) => photo.id.isNotEmpty && existing.add(photo.id),
          ),
        );
        _photos.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        _nextPage++;
        _total = result.total;
        _hasMore = result.hasMore;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load event photos. Try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshLatest() async {
    if (_loading || _refreshing) return;
    _refreshing = true;
    try {
      final result = await _fetch(1);
      if (!mounted) return;
      setState(() {
        final updated = <String, LiveEventPhoto>{
          for (final item in _photos) item.id: item,
          for (final item in result.photos)
            if (item.id.isNotEmpty) item.id: item,
        };
        _photos
          ..clear()
          ..addAll(updated.values)
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        _total = result.total;
        if (_nextPage == 1) _hasMore = result.hasMore;
        _error = null;
      });
    } catch (_) {
      // Keep existing photos visible during temporary network interruptions.
      if (mounted && _photos.isEmpty) {
        setState(() => _error = 'Could not refresh live photos.');
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _openPublicGallery() async {
    try {
      final url = GuestQrPayload.encode(
        widget.eventId,
        publicAppUrl: dotenv.env['PUBLIC_APP_URL'],
        faceEnrollment: false,
      );
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.inAppBrowserView,
      );
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the public gallery.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Public gallery link is unavailable.')),
        );
      }
    }
  }

  void _showPhoto(LiveEventPhoto photo) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      DateFormat(
                        'MMM d, yyyy · h:mm a',
                      ).format(photo.createdAt),
                      style: Theme.of(dialogContext).textTheme.bodySmall,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.68,
                ),
                child: photo.mediaType == 'video'
                    ? const AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Center(child: Icon(Icons.videocam, size: 54)),
                      )
                    : Image.network(
                        photo.imageUrl,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Padding(
                          padding: EdgeInsets.all(32),
                          child: Text('Photo preview unavailable'),
                        ),
                      ),
              ),
              if (!photo.isPublished)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Uploaded · not visible to guests yet'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // Keep one uninterrupted masonry grid across all upload timestamps.
    // Splitting photos into hourly slivers leaves blank space beneath shorter
    // columns whenever a new hour starts.
    final galleryPhotos = _photos;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Photo Live'),
        actions: [
          IconButton(
            tooltip: 'Refresh live photos',
            onPressed: () => unawaited(_refreshLatest()),
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Open public web gallery',
            onPressed: _openPublicGallery,
            icon: const Icon(Icons.open_in_browser_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshLatest,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
                color: colors.surfaceContainerLow,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Photo Live',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Photos appear here as they reach the event cloud.',
                    ),
                    const SizedBox(height: 20),
                    Text(
                      widget.eventTitle,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_photos.length} loaded · $_total event uploads',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Icon(
                          Icons.fiber_manual_record,
                          color: colors.primary,
                          size: 12,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            'Live Photos',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: colors.primary,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _openPublicGallery,
                          icon: const Icon(Icons.language_rounded, size: 18),
                          label: const Text('Web'),
                        ),
                      ],
                    ),
                    const Text(
                      'Private preview can include uploaded photos not yet published.',
                      style: TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
            if (_photos.isEmpty && !_loading)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error ??
                          'No cloud uploads yet. Shoot photos to see them here live.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            if (galleryPhotos.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(5, 10, 5, 8),
                  child: Text(
                    '${_total > 0 ? _total : galleryPhotos.length} photos',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
              // Same natural-aspect masonry layout as the web gallery.
              // A sliver lazily builds only nearby thumbnails during long shoots.
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.crossAxisExtent < 680
                        ? 2
                        : constraints.crossAxisExtent < 1024
                        ? 3
                        : 4;
                    return SliverMasonryGrid.count(
                      crossAxisCount: columns,
                      mainAxisSpacing: 5,
                      crossAxisSpacing: 5,
                      childCount: galleryPhotos.length,
                      itemBuilder: (context, index) {
                        final photo = galleryPhotos[index];
                        return Material(
                          key: ValueKey('live-photo-${photo.id}'),
                          color: colors.surfaceContainer,
                          child: InkWell(
                            onTap: () => _showPhoto(photo),
                            child: Stack(
                              children: [
                                if (photo.mediaType == 'video')
                                  const AspectRatio(
                                    aspectRatio: 16 / 9,
                                    child: Center(
                                      child: Icon(Icons.videocam, size: 40),
                                    ),
                                  )
                                else
                                  Image.network(
                                    photo.imageUrl,
                                    width: double.infinity,
                                    fit: BoxFit.fitWidth,
                                    cacheWidth: 600,
                                    // Keep the tile stable until the image's
                                    // real aspect ratio is decoded.
                                    loadingBuilder: (context, child, progress) {
                                      if (progress == null) return child;
                                      return const AspectRatio(
                                        aspectRatio: 4 / 3,
                                        child: Center(
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      );
                                    },
                                    errorBuilder: (_, _, _) =>
                                        const AspectRatio(
                                          aspectRatio: 4 / 3,
                                          child: Center(
                                            child: Icon(
                                              Icons.broken_image_outlined,
                                            ),
                                          ),
                                        ),
                                  ),
                                if (!photo.isPublished)
                                  Positioned(
                                    bottom: 0,
                                    left: 0,
                                    right: 0,
                                    child: ColoredBox(
                                      color: Colors.black54,
                                      child: Padding(
                                        padding: const EdgeInsets.all(3),
                                        child: Text(
                                          'Not published',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 9,
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
              ),
            ],
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
                child: Column(
                  children: [
                    if (_loading) const CircularProgressIndicator(),
                    if (_error != null && _photos.isNotEmpty)
                      Text(_error!, textAlign: TextAlign.center),
                    if (_hasMore && !_loading)
                      OutlinedButton.icon(
                        onPressed: _loadMore,
                        icon: const Icon(Icons.expand_more_rounded),
                        label: const Text('Load older photos'),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
