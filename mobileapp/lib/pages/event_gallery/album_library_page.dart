import 'package:flutter/material.dart';
import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:mobileapp/core/storage/active_event_storage.dart';
import 'package:mobileapp/core/storage/user_storage.dart';
import 'package:mobileapp/core/theme/app_theme.dart';
import 'package:mobileapp/core/utils/image_loader.dart';
import 'package:mobileapp/models/event_invitation_model.dart';
import 'package:mobileapp/pages/event_gallery/album_management_page.dart';
import 'package:mobileapp/pages/invitations/invitations_page.dart';
import 'package:mobileapp/pages/upload/upload_page.dart';
import 'package:mobileapp/utilities/app_toast.dart';

class AlbumLibraryPage extends StatefulWidget {
  const AlbumLibraryPage({super.key, this.onCreateEvent});

  final Future<void> Function()? onCreateEvent;

  @override
  State<AlbumLibraryPage> createState() => _AlbumLibraryPageState();
}

class _AlbumEvent {
  _AlbumEvent({
    required this.id,
    required this.title,
    required this.canManage,
    this.description,
    this.imageUrl,
    this.photosCount = 0,
  });

  final String id;
  final String title;
  final String? description;
  final String? imageUrl;
  final int photosCount;
  bool canManage;

  factory _AlbumEvent.fromJson(
    Map<String, dynamic> json, {
    bool canManage = false,
  }) {
    final image = json['image'];
    return _AlbumEvent(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Untitled event',
      description: json['description']?.toString(),
      imageUrl: image is Map
          ? image['url']?.toString()
          : image?.toString() ?? json['imageUrl']?.toString(),
      photosCount: int.tryParse(json['photosCount']?.toString() ?? '') ?? 0,
      canManage: canManage,
    );
  }

  EventSummary toSummary() => EventSummary(
    id: id,
    title: title,
    description: description,
    imageUrl: imageUrl,
    photosCount: photosCount,
  );
}

class _AlbumLibraryPageState extends State<AlbumLibraryPage> {
  List<_AlbumEvent> _events = [];
  bool _loading = true;
  bool _creating = false;
  bool _transferring = false;
  String? _error;

  bool get _canCreateAlbum => widget.onCreateEvent != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final ownedResponse = await DioHelper.get(
        '/event/my-events',
        queryParameters: {'page': '1', 'limit': '100'},
      );
      final ownedData = ownedResponse.data['data'] as List? ?? [];
      final currentUser = UserStorage.currentUser.value;
      final currentUserId = currentUser?.mongoId ?? currentUser?.id;
      final eventsById = <String, _AlbumEvent>{};
      for (final item in ownedData) {
        final json = Map<String, dynamic>.from(item as Map);
        final owner = json['userId'];
        final ownerId = owner is Map
            ? (owner['_id'] ?? owner['id'])?.toString()
            : owner?.toString();
        final event = _AlbumEvent.fromJson(
          json,
          canManage: currentUserId != null && ownerId == currentUserId,
        );
        if (event.id.isNotEmpty) eventsById[event.id] = event;
      }

      // Membership data adds shared events and identifies planner permissions.
      // The library itself is event-backed: it must not depend on separate
      // Album documents existing for an event to appear here.
      try {
        final membershipResponse = await DioHelper.get('/event-members/mine');
        final memberships = membershipResponse.data['data'] as List? ?? [];
        for (final item in memberships) {
          final membership = Map<String, dynamic>.from(item as Map);
          if (membership['status']?.toString().toLowerCase() != 'active') {
            continue;
          }
          final rawEvent = membership['eventId'];
          if (rawEvent is! Map) continue;
          final role = membership['role']?.toString().toLowerCase();
          final event = _AlbumEvent.fromJson(
            Map<String, dynamic>.from(rawEvent),
            canManage: role == 'owner' || role == 'event_planner',
          );
          if (event.id.isEmpty) continue;
          final existing = eventsById[event.id];
          if (existing == null) {
            eventsById[event.id] = event;
          } else {
            existing.canManage = existing.canManage || event.canManage;
          }
        }
      } catch (_) {
        // The owned/shared events already loaded remain visible if membership
        // metadata is temporarily unavailable.
      }

      if (!mounted) return;
      setState(() {
        _events = eventsById.values.toList();
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load your albums.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createAlbum() async {
    if (_creating || widget.onCreateEvent == null) return;
    setState(() => _creating = true);
    try {
      // In this workspace an album is the event itself. Reuse the existing
      // event creation flow instead of creating a second Album document.
      await widget.onCreateEvent!();
      if (mounted) await _load();
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _join() async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const InvitationsPage()));
    if (mounted) await _load();
  }

  Future<void> _transfer() async {
    if (_transferring) return;
    if (_events.isEmpty) {
      AppToast.error('Create or join an event before transferring photos.');
      return;
    }

    final activeId = ActiveEventStorage.activeEvent.value?.id;
    _AlbumEvent? selectedEvent;
    for (final event in _events) {
      if (event.id == activeId) {
        selectedEvent = event;
        break;
      }
    }

    selectedEvent ??= _events.length == 1
        ? _events.first
        : await showModalBottomSheet<_AlbumEvent>(
            context: context,
            showDragHandle: true,
            builder: (sheetContext) => SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: [
                  const ListTile(
                    title: Text(
                      'Choose an event',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text('Where should the photos be transferred?'),
                  ),
                  for (final event in _events)
                    ListTile(
                      leading: const Icon(Icons.photo_album_outlined),
                      title: Text(event.title),
                      subtitle: Text('${event.photosCount} photos'),
                      onTap: () => Navigator.pop(sheetContext, event),
                    ),
                ],
              ),
            ),
          );

    if (selectedEvent == null) return;
    setState(() => _transferring = true);
    try {
      await ActiveEventStorage.saveActiveEvent(selectedEvent.toSummary());
      if (!mounted) return;
      await showCameraUploadBottomSheet(context);
      if (mounted) await _load();
    } finally {
      if (mounted) setState(() => _transferring = false);
    }
  }

  Future<void> _openAlbum(_AlbumEvent event) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AlbumManagementPage(
          eventId: event.id,
          eventTitle: event.title,
          albumId: null,
          albumTitle: event.title,
          canManage: event.canManage,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Widget _buildAction({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool primary = false,
    bool busy = false,
  }) {
    return Expanded(
      child: SizedBox(
        height: 48,
        child: primary
            ? FilledButton(
                onPressed: onTap,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 18),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : OutlinedButton(
                onPressed: onTap,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  side: const BorderSide(color: AppColors.border),
                  foregroundColor: AppColors.foreground,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (busy)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Icon(icon, size: 17),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildAlbumCard(_AlbumEvent event) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openAlbum(event),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 70,
                  height: 70,
                  child: event.imageUrl?.isNotEmpty == true
                      ? ImageLoader.loadImage(event.imageUrl!)
                      : const ColoredBox(
                          color: AppColors.accentSoft,
                          child: Icon(
                            Icons.photo_library_outlined,
                            color: AppColors.primary,
                            size: 27,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      event.description?.isNotEmpty == true
                          ? event.description!
                          : 'Event album',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.mutedForeground,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.accentSoft,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: const Text(
                            'Album',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          '${event.photosCount} photos',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.mutedForeground,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
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
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
        children: [
          Row(
            children: [
              if (_canCreateAlbum) ...[
                _buildAction(
                  icon: Icons.add_rounded,
                  label: 'Create Album',
                  onTap: _creating ? null : _createAlbum,
                  primary: true,
                ),
                const SizedBox(width: 8),
              ],
              _buildAction(
                icon: Icons.login_rounded,
                label: 'Join',
                onTap: _join,
                primary: !_canCreateAlbum,
              ),
              const SizedBox(width: 8),
              _buildAction(
                icon: Icons.cloud_upload_outlined,
                label: 'Transfer',
                onTap: _transferring ? null : _transfer,
                busy: _transferring,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Text(
                'Your albums',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Text(
                '${_events.length} albums',
                style: const TextStyle(
                  color: AppColors.mutedForeground,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_events.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  const Icon(
                    Icons.photo_library_outlined,
                    size: 46,
                    color: AppColors.mutedForeground,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No albums yet',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Your existing events will appear here. Create a new event or join one to start uploading photos.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _canCreateAlbum ? _createAlbum : _join,
                    icon: Icon(
                      _canCreateAlbum ? Icons.add_rounded : Icons.login_rounded,
                    ),
                    label: Text(
                      _canCreateAlbum ? 'Create Album' : 'Join an event',
                    ),
                  ),
                ],
              ),
            )
          else
            ..._events.map(
              (event) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: _buildAlbumCard(event),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Albums',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
        ),
        actions: [
          if (widget.onCreateEvent != null)
            TextButton.icon(
              onPressed: () async {
                await widget.onCreateEvent!();
                if (mounted) await _load();
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New event'),
            ),
          IconButton(
            tooltip: 'Refresh albums',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _buildBody(),
    );
  }
}
