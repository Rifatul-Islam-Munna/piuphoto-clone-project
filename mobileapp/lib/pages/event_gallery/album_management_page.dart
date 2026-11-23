import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mobileapp/core/guest/guest_qr_payload.dart';
import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:mobileapp/core/platform/image_downloads.dart';
import 'package:mobileapp/core/storage/active_event_storage.dart';
import 'package:mobileapp/core/theme/app_theme.dart';
import 'package:mobileapp/core/utils/image_loader.dart';
import 'package:mobileapp/models/album_model.dart';
import 'package:mobileapp/models/event_image_model.dart';
import 'package:mobileapp/models/event_invitation_model.dart';
import 'package:mobileapp/pages/event_gallery/album_analytics_page.dart';
import 'package:mobileapp/pages/event_gallery/album_settings_page.dart';
import 'package:mobileapp/pages/event_gallery/workflow_management_page.dart';
import 'package:mobileapp/pages/upload/event_live_preview_page.dart';
import 'package:mobileapp/pages/plans/plans_page.dart';
import 'package:mobileapp/pages/upload/transfer_list_page.dart';
import 'package:mobileapp/pages/upload/upload_page.dart';
import 'package:mobileapp/utilities/app_toast.dart';
import 'package:mobileapp/widgets/intrinsic_qr_image.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

enum _AlbumMediaTab { photos, videos }

enum _AlbumVisibilityFilter { all, live, hidden }

enum _AlbumSortOrder { newest, oldest }

class AlbumManagementPage extends StatefulWidget {
  const AlbumManagementPage({
    super.key,
    required this.eventId,
    required this.eventTitle,
    this.albumId,
    required this.albumTitle,
    this.canManage = true,
  });

  final String eventId;
  final String eventTitle;
  final String? albumId;
  final String albumTitle;
  final bool canManage;

  @override
  State<AlbumManagementPage> createState() => _AlbumManagementPageState();
}

class _AlbumManagementPageState extends State<AlbumManagementPage> {
  final List<EventImageModel> _images = [];
  final List<AlbumModel> _albums = [];
  final Set<String> _selectedIds = {};
  final ScrollController _gridController = ScrollController();
  int _page = 1;
  bool _hasMore = false;
  bool _loadingMore = false;
  late String _albumTitle = widget.albumTitle;
  String _albumDescription = '';
  bool _loading = true;
  bool _busy = false;
  bool _selectionMode = false;
  String? _error;
  _AlbumMediaTab _mediaTab = _AlbumMediaTab.photos;
  _AlbumVisibilityFilter _visibilityFilter = _AlbumVisibilityFilter.all;
  _AlbumSortOrder _sortOrder = _AlbumSortOrder.newest;

  @override
  void initState() {
    super.initState();
    _gridController.addListener(_handleGridScroll);
    _load();
    _loadAlbums();
  }

  @override
  void dispose() {
    _gridController.removeListener(_handleGridScroll);
    _gridController.dispose();
    super.dispose();
  }

  void _handleGridScroll() {
    if (!_gridController.hasClients || _loading || _loadingMore || !_hasMore) {
      return;
    }
    final position = _gridController.position;
    if (position.pixels >= position.maxScrollExtent - 480) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final response = await DioHelper.get(
        '/eventImage/get-all',
        queryParameters: {
          'eventId': widget.eventId,
          if (widget.albumId != null) 'albumId': widget.albumId,
          'page': '1',
          'limit': '100',
        },
      );
      final data = response.data['data'] as List? ?? [];
      final totalPages =
          int.tryParse(response.data['totalPages']?.toString() ?? '') ?? 1;
      final images = data
          .map(
            (item) => EventImageModel.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
      if (!mounted) return;
      setState(() {
        _images
          ..clear()
          ..addAll(images);
        _page = 1;
        _hasMore = totalPages > 1;
        _loadingMore = false;
        _selectedIds.clear();
        _selectionMode = false;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load this event.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    final nextPage = _page + 1;
    setState(() => _loadingMore = true);
    try {
      final response = await DioHelper.get(
        '/eventImage/get-all',
        queryParameters: {
          'eventId': widget.eventId,
          if (widget.albumId != null) 'albumId': widget.albumId,
          'page': '$nextPage',
          'limit': '100',
        },
      );
      final data = response.data['data'] as List? ?? [];
      final totalPages =
          int.tryParse(response.data['totalPages']?.toString() ?? '') ??
          nextPage;
      final images = data
          .map(
            (item) => EventImageModel.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
      if (!mounted) return;
      setState(() {
        final existingIds = _images.map((image) => image.id).toSet();
        _images.addAll(
          images.where((image) => !existingIds.contains(image.id)),
        );
        _page = nextPage;
        _hasMore = nextPage < totalPages;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _hasMore = false);
        AppToast.error(
          'Could not load more photos. Pull to refresh and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _loadAlbums() async {
    try {
      final response = await DioHelper.get(
        '/album/get-all',
        queryParameters: {'eventId': widget.eventId},
      );
      final data = response.data['data'] as List? ?? [];
      final albums = data
          .map((item) => AlbumModel.fromJson(Map<String, dynamic>.from(item)))
          .toList();
      if (!mounted) return;
      setState(() {
        _albums
          ..clear()
          ..addAll(albums);
        final current = albums.where((album) => album.id == widget.albumId);
        if (current.isNotEmpty) {
          _albumDescription = current.first.description ?? '';
        }
      });
    } catch (_) {
      // Keep the album screen usable if the optional album list is unavailable.
    }
  }

  List<EventImageModel> get _visibleImages {
    final images = _images.where((image) {
      final isVideo = image.mediaType.toLowerCase() == 'video';
      if (_mediaTab == _AlbumMediaTab.videos && !isVideo) return false;
      if (_mediaTab == _AlbumMediaTab.photos && isVideo) return false;
      return switch (_visibilityFilter) {
        _AlbumVisibilityFilter.all => true,
        _AlbumVisibilityFilter.live => image.isPublished,
        _AlbumVisibilityFilter.hidden => !image.isPublished,
      };
    }).toList();
    images.sort((a, b) {
      final first =
          DateTime.tryParse(a.createdAt ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final second =
          DateTime.tryParse(b.createdAt ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return _sortOrder == _AlbumSortOrder.newest
          ? second.compareTo(first)
          : first.compareTo(second);
    });
    return images;
  }

  List<EventImageModel> get _selectedImages =>
      _images.where((image) => _selectedIds.contains(image.id)).toList();
  int get _photoCount =>
      _images.where((image) => image.mediaType.toLowerCase() != 'video').length;
  int get _videoCount =>
      _images.where((image) => image.mediaType.toLowerCase() == 'video').length;

  String _filenameFor(EventImageModel image) {
    final uri = Uri.tryParse(image.imageUrl);
    final name = uri?.pathSegments.isNotEmpty ?? false
        ? uri!.pathSegments.last
        : '';
    if (name.contains('.')) return name;
    return 'event-image-${image.id}.jpg';
  }

  void _toggleSelection(EventImageModel image) {
    setState(() {
      _selectionMode = true;
      if (!_selectedIds.add(image.id)) _selectedIds.remove(image.id);
      if (_selectedIds.isEmpty) _selectionMode = false;
    });
  }

  void _selectAllVisible() {
    setState(() {
      final visibleIds = _visibleImages.map((image) => image.id);
      if (_visibleImages.isNotEmpty &&
          _visibleImages.every((image) => _selectedIds.contains(image.id))) {
        _selectedIds.clear();
        _selectionMode = false;
      } else {
        _selectedIds
          ..clear()
          ..addAll(visibleIds);
        _selectionMode = _selectedIds.isNotEmpty;
      }
    });
  }

  Future<void> _openUpload() async {
    if (ActiveEventStorage.selectionLocked.value) {
      AppToast.error(
        'Finish the current transfer before opening another upload.',
      );
      return;
    }
    await ActiveEventStorage.saveActiveEvent(
      EventSummary(id: widget.eventId, title: widget.eventTitle),
    );
    if (!mounted) return;
    // The camera connection, permission prompts, file picker, and receiving
    // status all run *inside* this sheet. No intermediate UploadPage route.
    await showCameraUploadBottomSheet(context, initialAlbumId: widget.albumId);
    if (mounted) await _load();
  }

  Future<void> _showAlbumUploadMethodSheet() => _openUpload();

  Future<void> _editBasicInfo() async {
    final updated = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute(
        builder: (_) => AlbumBasicInfoPage(
          albumId: widget.albumId,
          eventId: widget.eventId,
          albumTitle: _albumTitle,
          albumDescription: _albumDescription,
        ),
      ),
    );
    if (updated == null || !mounted) return;
    setState(() {
      _albumTitle = updated['title'] ?? _albumTitle;
      _albumDescription = updated['description'] ?? _albumDescription;
    });
    await _loadAlbums();
  }

  Future<void> _editAlbumSettings() async {
    final updated = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute(
        builder: (_) => AlbumSettingsPage(
          albumId: widget.albumId,
          eventId: widget.eventId,
          eventTitle: widget.eventTitle,
          albumTitle: _albumTitle,
          albumDescription: _albumDescription,
          onOpenWorkflow: () {
            _openWorkflowManagement();
          },
        ),
      ),
    );
    if (updated == null || !mounted) return;
    setState(() {
      _albumTitle = updated['title'] ?? _albumTitle;
      _albumDescription = updated['description'] ?? _albumDescription;
    });
    await _loadAlbums();
  }

  Future<void> _openWorkflowManagement() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => WorkflowManagementPage(
          eventId: widget.eventId,
          eventTitle: widget.eventTitle,
          albumTitle: _albumTitle,
          onOpenPhotoManagement: () {
            if (mounted) setState(() => _selectionMode = true);
          },
          onShareAlbum: _shareAlbum,
        ),
      ),
    );
  }

  Future<void> _showSortOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Sort photos',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            ListTile(
              title: const Text('Newest first'),
              trailing: _sortOrder == _AlbumSortOrder.newest
                  ? const Icon(Icons.check_circle, color: AppColors.primary)
                  : null,
              onTap: () {
                setState(() => _sortOrder = _AlbumSortOrder.newest);
                Navigator.pop(sheetContext);
              },
            ),
            ListTile(
              title: const Text('Oldest first'),
              trailing: _sortOrder == _AlbumSortOrder.oldest
                  ? const Icon(Icons.check_circle, color: AppColors.primary)
                  : null,
              onTap: () {
                setState(() => _sortOrder = _AlbumSortOrder.oldest);
                Navigator.pop(sheetContext);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showFilterOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Filter photos',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            for (final filter in _AlbumVisibilityFilter.values)
              ListTile(
                title: Text(switch (filter) {
                  _AlbumVisibilityFilter.all => 'All photos',
                  _AlbumVisibilityFilter.live => 'Published photos',
                  _AlbumVisibilityFilter.hidden => 'Hidden photos',
                }),
                trailing: filter == _visibilityFilter
                    ? const Icon(Icons.check_circle, color: AppColors.primary)
                    : null,
                onTap: () {
                  setState(() => _visibilityFilter = filter);
                  Navigator.pop(sheetContext);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _setSelectedVisibility() async {
    final selected = _selectedImages;
    if (selected.isEmpty) return;
    final publish = selected.any((image) => !image.isPublished);
    setState(() => _busy = true);
    try {
      for (final image in selected) {
        await DioHelper.patch(
          '/eventImage/publish',
          data: {'isPublished': publish},
          queryParameters: {'id': image.id},
        );
      }
      AppToast.success(
        publish
            ? 'Selected photos published'
            : 'Selected photos hidden from the gallery',
      );
      await _load();
    } catch (_) {
      AppToast.error('Could not update selected photos');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteSelected() async {
    final selected = _selectedImages;
    if (selected.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete selected photos?'),
        content: Text(
          'This will permanently delete ${selected.length} selected photos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.destructive),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      for (final image in selected) {
        await DioHelper.delete(
          '/eventImage/delete',
          queryParameters: {'id': image.id},
        );
      }
      AppToast.success('Selected photos deleted');
      await _load();
    } catch (_) {
      AppToast.error('Could not delete all selected photos');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _moveSelected() async {
    final selected = _selectedImages;
    final destinations = _albums
        .where((album) => album.id != widget.albumId)
        .toList();
    if (selected.isEmpty) return;
    if (destinations.isEmpty) {
      AppToast.error('Create another album before moving photos.');
      return;
    }
    final destination = await showModalBottomSheet<AlbumModel>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text(
                'Move photos to album',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            for (final album in destinations)
              ListTile(
                leading: const Icon(Icons.photo_album_outlined),
                title: Text(album.title),
                subtitle: album.description == null
                    ? null
                    : Text(album.description!),
                onTap: () => Navigator.pop(sheetContext, album),
              ),
          ],
        ),
      ),
    );
    if (destination == null) return;
    setState(() => _busy = true);
    try {
      for (final image in selected) {
        await DioHelper.patch(
          '/eventImage/update?id=${image.id}',
          data: {'eventId': widget.eventId, 'albumId': destination.id},
        );
      }
      AppToast.success('Photos moved to ${destination.title}');
      await _load();
    } catch (_) {
      AppToast.error('Could not move all selected photos');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadImages(List<EventImageModel> images) async {
    final photos = images
        .where((image) => image.mediaType.toLowerCase() != 'video')
        .toList();
    if (photos.isEmpty) {
      AppToast.error('There are no downloadable photos in this selection');
      return;
    }
    setState(() => _busy = true);
    var saved = 0;
    try {
      for (final image in photos) {
        final response = await DioHelper.dio.get<List<int>>(
          image.imageUrl,
          options: Options(responseType: ResponseType.bytes),
        );
        final bytes = Uint8List.fromList(response.data ?? []);
        if (bytes.isEmpty) continue;
        if (await ImageDownloads.saveImage(
          bytes: bytes,
          filename: _filenameFor(image),
        )) {
          saved++;
        }
      }
      AppToast.success('Downloaded $saved photos');
    } catch (_) {
      AppToast.error('Could not download all photos');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _socialShareUrl(String network, String url) {
    final title = '$_albumTitle · ${_images.length} photos';
    final link = Uri.encodeComponent(url);
    final encodedTitle = Uri.encodeComponent(title);
    return switch (network) {
      'facebook' => 'https://www.facebook.com/sharer/sharer.php?u=$link',
      'x' => 'https://twitter.com/intent/tweet?url=$link&text=$encodedTitle',
      'pinterest' =>
        'https://pinterest.com/pin/create/button/?url=$link&description=$encodedTitle',
      'whatsapp' => 'https://wa.me/?text=${Uri.encodeComponent('$title $url')}',
      'telegram' => 'https://t.me/share/url?url=$link&text=$encodedTitle',
      'line' => 'https://social-plugins.line.me/lineit/share?url=$link',
      _ => 'mailto:?subject=$encodedTitle&body=$link',
    };
  }

  Future<void> _openSocialShare(String network, String galleryUrl) async {
    if (network == 'wechat' || network == 'messenger' || network == 'more') {
      await SharePlus.instance.share(
        ShareParams(
          text: '$_albumTitle · ${_images.length} photos\\n$galleryUrl',
        ),
      );
      return;
    }
    try {
      final opened = await launchUrl(
        Uri.parse(_socialShareUrl(network, galleryUrl)),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        AppToast.error('Could not open $network sharing');
      }
    } catch (_) {
      if (mounted) AppToast.error('Could not open $network sharing');
    }
  }

  Widget _socialShareButton({
    required String label,
    required Color background,
    required Widget icon,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: background,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox.square(dimension: 44, child: Center(child: icon)),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: AppColors.mutedForeground,
          ),
        ),
      ],
    );
  }

  Future<void> _shareAlbum() async {
    late final String galleryUrl;
    try {
      galleryUrl = GuestQrPayload.encode(
        widget.eventId,
        publicAppUrl: dotenv.env['PUBLIC_APP_URL'],
        faceEnrollment: false,
      );
    } catch (_) {
      AppToast.error('The public gallery link is unavailable');
      return;
    }

    var galleryVisibility = 'public';
    try {
      final settingsResponse = await DioHelper.get(
        '/gallery-access/settings',
        queryParameters: {'eventId': widget.eventId},
      );
      final raw = settingsResponse.data is Map
          ? settingsResponse.data['data']
          : null;
      if (raw is Map) {
        galleryVisibility =
            (raw['galleryVisibility'] ?? raw['visibility'] ?? 'public')
                .toString();
      }
    } catch (_) {
      galleryVisibility = 'unknown';
    }
    if (!mounted) return;
    final isPublic = galleryVisibility == 'public';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.9,
        ),
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Share album',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accentSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          color: AppColors.primary,
                          size: 19,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            isPublic
                                ? 'This album is publicly accessible.'
                                : galleryVisibility == 'unknown'
                                ? 'Gallery access status could not be checked.'
                                : 'This album is private. Review privacy settings before sharing.',
                            style: const TextStyle(fontSize: 11, height: 1.35),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            _editAlbumSettings();
                          },
                          child: const Text(
                            'Settings',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: AppColors.accentSoft,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: _images.isNotEmpty
                              ? ImageLoader.loadImage(
                                  _images.first.imageUrl,
                                  fit: BoxFit.cover,
                                )
                              : const Icon(
                                  Icons.photo_library_outlined,
                                  color: AppColors.primary,
                                  size: 27,
                                ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _albumTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Photos can fly',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.mutedForeground,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_images.length} photos',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 4,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1.12,
                    children: [
                      _socialShareButton(
                        label: 'Facebook',
                        background: const Color(0xFF1877F2),
                        icon: const Text(
                          'f',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 27,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        onTap: () => _openSocialShare('facebook', galleryUrl),
                      ),
                      _socialShareButton(
                        label: 'WhatsApp',
                        background: const Color(0xFF25D366),
                        icon: const Icon(
                          Icons.chat_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                        onTap: () => _openSocialShare('whatsapp', galleryUrl),
                      ),
                      _socialShareButton(
                        label: 'WeChat',
                        background: const Color(0xFF09B83E),
                        icon: const Text(
                          'W',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 23,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        onTap: () => _openSocialShare('wechat', galleryUrl),
                      ),
                      _socialShareButton(
                        label: 'Telegram',
                        background: const Color(0xFF229ED9),
                        icon: const Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 21,
                        ),
                        onTap: () => _openSocialShare('telegram', galleryUrl),
                      ),
                      _socialShareButton(
                        label: 'Messenger',
                        background: const Color(0xFF0866FF),
                        icon: const Icon(
                          Icons.chat_bubble_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                        onTap: () => _openSocialShare('messenger', galleryUrl),
                      ),
                      _socialShareButton(
                        label: 'LINE',
                        background: const Color(0xFF06C755),
                        icon: const Text(
                          'LINE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        onTap: () => _openSocialShare('line', galleryUrl),
                      ),
                      _socialShareButton(
                        label: 'X',
                        background: const Color(0xFF171717),
                        icon: const Text(
                          'X',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onTap: () => _openSocialShare('x', galleryUrl),
                      ),
                      _socialShareButton(
                        label: 'More',
                        background: AppColors.accentSoft,
                        icon: const Icon(
                          Icons.more_horiz_rounded,
                          color: AppColors.foreground,
                          size: 24,
                        ),
                        onTap: () => _openSocialShare('more', galleryUrl),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Material(
                    color: AppColors.card,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: const BorderSide(color: AppColors.border),
                    ),
                    child: ListTile(
                      leading: const Icon(
                        Icons.qr_code_2_rounded,
                        color: AppColors.foreground,
                      ),
                      title: const Text(
                        'QR code',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.mutedForeground,
                      ),
                      onTap: () {
                        showDialog<void>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('Album QR code'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                DecoratedBox(
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: IntrinsicQrImage(
                                      data: galleryUrl,
                                      size: 230,
                                      errorCorrectionLevel:
                                          QrErrorCorrectLevel.Q,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  'Scan with any phone camera to open the event gallery.',
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                            actions: [
                              TextButton.icon(
                                onPressed: () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: galleryUrl),
                                  );
                                  if (dialogContext.mounted) {
                                    AppToast.success('Gallery link copied');
                                  }
                                },
                                icon: const Icon(Icons.copy_outlined),
                                label: const Text('Copy link'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(dialogContext),
                                child: const Text('Done'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: galleryUrl),
                        );
                        if (sheetContext.mounted) {
                          AppToast.success('Gallery link copied');
                        }
                      },
                      icon: const Icon(Icons.copy_outlined),
                      label: const Text('Copy Link'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => EventLivePreviewPage(
                              eventId: widget.eventId,
                              eventTitle: widget.eventTitle,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('Preview'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Guests see published photos according to this event’s gallery access settings.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteAlbum() async {
    final albumId = widget.albumId;
    if (albumId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete album?'),
        content: Text(
          'Delete "$_albumTitle"? Its photos will remain in the event gallery.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Delete album',
              style: TextStyle(color: AppColors.destructive),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await DioHelper.delete('/album/delete', queryParameters: {'id': albumId});
      if (!mounted) return;
      AppToast.success('Album deleted');
      Navigator.of(context).pop();
    } catch (_) {
      AppToast.error('Could not delete album');
    }
  }

  Future<void> _showMoreOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'More',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            if (widget.canManage && widget.albumId != null)
              ListTile(
                leading: const Icon(Icons.insights_outlined),
                title: const Text('PiuAlbum Analytics'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => AlbumAnalyticsPage(
                        eventId: widget.eventId,
                        eventTitle: widget.eventTitle,
                        albumId: widget.albumId!,
                        albumTitle: _albumTitle,
                      ),
                    ),
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.sync_alt_rounded),
              title: const Text('Transfer history'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => TransferListPage(
                      eventId: widget.eventId,
                      eventTitle: widget.eventTitle,
                      filter: TransferListFilter.all,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.storage_outlined),
              title: const Text('Storage & plans'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const PlansPage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Share album photos'),
              onTap: () {
                Navigator.pop(sheetContext);
                _shareAlbum();
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('Download all photos'),
              onTap: () {
                Navigator.pop(sheetContext);
                _downloadImages(_images);
              },
            ),
            ListTile(
              leading: const Icon(Icons.refresh_rounded),
              title: const Text('Refresh album'),
              onTap: () {
                Navigator.pop(sheetContext);
                _load();
              },
            ),
            if (widget.canManage && widget.albumId != null)
              const Divider(height: 1),
            if (widget.canManage && widget.albumId != null)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: AppColors.destructive,
                ),
                title: const Text(
                  'Delete album',
                  style: TextStyle(color: AppColors.destructive),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _deleteAlbum();
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlbumHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _albumTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ),
          if (widget.canManage)
            IconButton(
              tooltip: 'Edit basic info',
              onPressed: _busy ? null : _editBasicInfo,
              icon: const Icon(
                Icons.edit_outlined,
                color: AppColors.primary,
                size: 20,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMediaTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _mediaTabButton(
            label: 'Photos',
            count: _photoCount,
            selected: _mediaTab == _AlbumMediaTab.photos,
            onTap: () => setState(() => _mediaTab = _AlbumMediaTab.photos),
          ),
          const SizedBox(width: 18),
          _mediaTabButton(
            label: 'Videos',
            count: _videoCount,
            selected: _mediaTab == _AlbumMediaTab.videos,
            onTap: () => setState(() => _mediaTab = _AlbumMediaTab.videos),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Sort',
            visualDensity: VisualDensity.compact,
            onPressed: _showSortOptions,
            icon: const Icon(Icons.sort_rounded, size: 21),
          ),
          IconButton(
            tooltip: 'Filter',
            visualDensity: VisualDensity.compact,
            onPressed: _showFilterOptions,
            icon: const Icon(Icons.filter_alt_outlined, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _mediaTabButton({
    required String label,
    required int count,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$label($count)',
              style: TextStyle(
                color: selected ? AppColors.primary : AppColors.foreground,
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 3,
              width: selected ? 44 : 0,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid() {
    final images = _visibleImages;
    if (images.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _mediaTab == _AlbumMediaTab.photos
                    ? Icons.photo_library_outlined
                    : Icons.video_library_outlined,
                size: 44,
                color: AppColors.mutedForeground,
              ),
              const SizedBox(height: 12),
              Text(
                _images.isEmpty
                    ? 'No photos in this album yet'
                    : 'No items match this filter',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              const Text(
                'Upload photos here to keep everything in one place.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.mutedForeground,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _showAlbumUploadMethodSheet,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Upload photos'),
              ),
            ],
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 520
            ? 3
            : constraints.maxWidth < 900
            ? 4
            : 5;
        return GridView.builder(
          controller: _gridController,
          padding: const EdgeInsets.fromLTRB(3, 8, 3, 16),
          itemCount: images.length + (_hasMore ? 1 : 0),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 5,
            mainAxisSpacing: 5,
            childAspectRatio: .86,
          ),
          itemBuilder: (context, index) {
            if (index >= images.length) {
              return const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }
            final image = images[index];
            final selected = _selectedIds.contains(image.id);
            final isVideo = image.mediaType.toLowerCase() == 'video';
            return InkWell(
              onTap: () => _toggleSelection(image),
              onLongPress: () => _toggleSelection(image),
              borderRadius: BorderRadius.circular(8),
              child: Column(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (isVideo)
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
                            ImageLoader.loadImage(image.imageUrl),
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
                                border: Border.all(
                                  color: Colors.white,
                                  width: 1.4,
                                ),
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
                              image.isPublished
                                  ? Icons.check_circle
                                  : Icons.lock,
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
                      _filenameFor(image),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.mutedForeground,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBottomBar() {
    if (_selectionMode) {
      final selected = _selectedImages;
      final allVisibleSelected =
          _visibleImages.isNotEmpty &&
          _visibleImages.every((image) => _selectedIds.contains(image.id));
      final shouldPublish = selected.any((image) => !image.isPublished);
      return SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Close selection',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() {
                      _selectedIds.clear();
                      _selectionMode = false;
                    }),
                    icon: const Icon(Icons.close_rounded),
                  ),
                  Text(
                    '${_selectedIds.length} Photo Selected',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _selectAllVisible,
                    child: Text(
                      allVisibleSelected ? 'Clear all' : 'Select all',
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  _selectionAction(
                    icon: shouldPublish
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    label: shouldPublish ? 'Show photos' : 'Hide photos',
                    onTap: _busy ? null : _setSelectedVisibility,
                  ),
                  _selectionAction(
                    icon: Icons.drive_file_move_outline,
                    label: 'Move',
                    onTap: _busy ? null : _moveSelected,
                  ),
                  _selectionAction(
                    icon: Icons.download_outlined,
                    label: 'Download',
                    onTap: _busy ? null : () => _downloadImages(selected),
                  ),
                  _selectionAction(
                    icon: Icons.delete_outline,
                    label: 'Delete',
                    destructive: true,
                    onTap: _busy ? null : _deleteSelected,
                  ),
                ],
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
            ],
          ),
        ),
      );
    }
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        padding: const EdgeInsets.fromLTRB(6, 7, 8, 8),
        child: Row(
          children: [
            if (widget.canManage)
              _bottomAction(
                icon: Icons.settings_outlined,
                label: 'Settings',
                onTap: _editAlbumSettings,
              ),
            if (widget.canManage)
              _bottomAction(
                icon: Icons.hub_outlined,
                label: 'Workflow\nManagement',
                onTap: _openWorkflowManagement,
              ),
            _bottomAction(
              icon: Icons.grid_view_rounded,
              label: 'Photo\nManagement',
              onTap: () => setState(() => _selectionMode = true),
            ),
            _bottomAction(
              icon: Icons.more_horiz_rounded,
              label: 'More',
              onTap: _showMoreOptions,
            ),
            const SizedBox(width: 3),
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _showAlbumUploadMethodSheet,
                  icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                  label: const Text(
                    'Upload',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 1),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 21, color: AppColors.foreground),
              const SizedBox(height: 3),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 9,
                  height: 1.05,
                  color: AppColors.foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _selectionAction({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool destructive = false,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 21,
                color: destructive
                    ? AppColors.destructive
                    : AppColors.mutedForeground,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  color: destructive
                      ? AppColors.destructive
                      : AppColors.mutedForeground,
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
        centerTitle: true,
        title: const Text(
          'Album Management',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
        ),
        actions: [
          IconButton(
            tooltip: 'Share album',
            onPressed: _shareAlbum,
            style: IconButton.styleFrom(
              minimumSize: const Size(40, 40),
              backgroundColor: AppColors.cream,
              foregroundColor: AppColors.primaryDark,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppColors.border),
              ),
            ),
            icon: const Icon(Icons.share_rounded, size: 20),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Column(
        children: [
          _buildAlbumHeader(),
          const Divider(height: 1),
          _buildMediaTabs(),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 9, 16, 7),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _visibilityFilter == _AlbumVisibilityFilter.all
                        ? 'All photos'
                        : _visibilityFilter == _AlbumVisibilityFilter.live
                        ? 'Published photos'
                        : 'Hidden photos',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${_visibleImages.length} items',
                  style: const TextStyle(
                    color: AppColors.mutedForeground,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Try again'),
                          ),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(onRefresh: _load, child: _buildGrid()),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }
}
