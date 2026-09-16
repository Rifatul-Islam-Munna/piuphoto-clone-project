import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:mobileapp/core/storage/active_event_storage.dart';
import 'package:mobileapp/core/storage/user_storage.dart';
import 'package:mobileapp/core/utils/image_loader.dart';
import 'package:mobileapp/core/utils/image_upload_helper.dart';
import 'package:mobileapp/models/album_model.dart';
import 'package:mobileapp/models/event_invitation_model.dart';
import 'package:mobileapp/pages/event_gallery/event_gallery_page.dart';
import 'package:mobileapp/utilities/app_toast.dart';

class EventModel {
  final String id;
  final String title;
  final String? description;
  final String? imageUrl;
  final bool isPublished;
  final bool isActive;
  final bool autoEnhanceImages;
  final String? createdAt;
  final int photosCount;

  EventModel({
    required this.id,
    required this.title,
    this.description,
    this.imageUrl,
    this.isPublished = false,
    this.isActive = false,
    this.autoEnhanceImages = false,
    this.createdAt,
    this.photosCount = 0,
  });

  static int _intFromJson(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  factory EventModel.fromJson(Map<String, dynamic> json) {
    final image = json['image'];
    return EventModel(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Untitled',
      description: json['description']?.toString(),
      imageUrl: image is Map ? image['url']?.toString() : null,
      isPublished: json['isPublished'] ?? false,
      isActive: json['isActive'] ?? false,
      autoEnhanceImages: json['autoEnhanceImages'] == true,
      createdAt: json['createdAt']?.toString(),
      photosCount: _intFromJson(json['photosCount']),
    );
  }
}

class PhotographerModel {
  final String id;
  final String? name;
  final String? email;
  final String? phone;

  PhotographerModel({required this.id, this.name, this.email, this.phone});

  factory PhotographerModel.fromJson(Map<String, dynamic> json) {
    return PhotographerModel(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      name: json['name']?.toString(),
      email: json['email']?.toString(),
      phone: json['phone']?.toString(),
    );
  }

  String get displayName => name ?? email ?? phone ?? 'Unknown';
}

@RoutePage()
class EventsPage extends StatelessWidget {
  const EventsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _EventsListView();
  }
}

class _EventsListView extends StatefulWidget {
  const _EventsListView();

  @override
  State<_EventsListView> createState() => _EventsListViewState();
}

class _EventsListViewState extends State<_EventsListView> {
  late Future<List<EventModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadEvents();
  }

  Future<List<EventModel>> _loadEvents() async {
    try {
      final response = await DioHelper.get('/event/my-events');
      final data = response.data['data'] as List? ?? [];
      return data
          .map((item) => EventModel.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (e) {
      return [];
    }
  }

  void _refresh() {
    setState(() => _future = _loadEvents());
  }

  @override
  Widget build(BuildContext context) {
    final canCreateEvents =
        UserStorage.currentUser.value?.hasPlannerAccess ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Events'),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      body: FutureBuilder<List<EventModel>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final events = snapshot.data ?? [];

          if (events.isEmpty) {
            return _buildEmptyState(context);
          }

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: events.length,
              itemBuilder: (context, index) {
                return _EventCardItem(
                  event: events[index],
                  onTap: () => _openEventDetail(context, events[index]),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: canCreateEvents
          ? FloatingActionButton.extended(
              onPressed: () => _showCreateEventDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('Create Event'),
            )
          : null,
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.event_note,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No Events Yet',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Create your first event to start\nmanaging photo uploads',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            if (UserStorage.currentUser.value?.hasPlannerAccess ?? false)
              FilledButton.icon(
                onPressed: () => _showCreateEventDialog(context),
                icon: const Icon(Icons.add),
                label: const Text('Create Event'),
              ),
          ],
        ),
      ),
    );
  }

  void _showCreateEventDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CreateEventSheet(onCreated: _refresh),
    );
  }

  void _openEventDetail(BuildContext context, EventModel event) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => _EventDetailPage(event: event, onUpdated: _refresh),
          ),
        )
        .then((_) => _refresh());
  }
}

class _EventCardItem extends StatelessWidget {
  final EventModel event;
  final VoidCallback onTap;

  const _EventCardItem({required this.event, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ImageLoader.loadImage(
                event.imageUrl,
                fit: BoxFit.cover,
                errorWidget: _buildPlaceholder(context),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          event.title,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: event.isPublished
                              ? Colors.green.withValues(alpha: 0.1)
                              : Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          event.isPublished ? 'Published' : 'Draft',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: event.isPublished
                                ? Colors.green
                                : Colors.orange,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (event.description?.isNotEmpty ?? false) ...[
                    const SizedBox(height: 8),
                    Text(
                      event.description!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.photo_library,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${event.photosCount} photos',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.image,
          size: 64,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
        ),
      ),
    );
  }
}

class _CreateEventSheet extends StatefulWidget {
  final VoidCallback onCreated;

  const _CreateEventSheet({required this.onCreated});

  @override
  State<_CreateEventSheet> createState() => _CreateEventSheetState();
}

class _CreateEventSheetState extends State<_CreateEventSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isLoading = false;
  bool _isPublished = true;
  bool _autoEnhanceImages = false;
  String? _selectedImagePath;
  String? _selectedImageName;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickCoverImage() async {
    try {
      final picked = await ImageUploadHelper.pickFromGallery();
      if (picked == null || !mounted) return;
      setState(() {
        _selectedImagePath = picked.path;
        _selectedImageName = picked.name;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to pick cover image')),
        );
      }
    }
  }

  Future<void> _createEvent() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      String? imageUrl;
      if (_selectedImagePath != null && _selectedImageName != null) {
        imageUrl = await ImageUploadHelper.uploadFile(
          path: _selectedImagePath!,
          filename: _selectedImageName!,
        );
      }

      final response = await DioHelper.post(
        '/event',
        data: {
          'title': _titleController.text.trim(),
          'description': _descriptionController.text.trim(),
          'isPublished': _isPublished,
          'autoEnhanceImages': _autoEnhanceImages,
          if (imageUrl != null && imageUrl.isNotEmpty)
            'image': {'url': imageUrl},
        },
      );

      final raw = response.data is Map ? response.data['data'] : null;
      if ((UserStorage.currentUser.value?.isPhotographer ?? false) &&
          raw is Map) {
        final event = EventSummary.fromJson(Map<String, dynamic>.from(raw));
        if (event.id.isNotEmpty) {
          await ActiveEventStorage.saveActiveEvent(event);
        }
      }

      if (mounted) {
        Navigator.pop(context);
        widget.onCreated();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Event created successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to create event')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: Row(
              children: [
                Text(
                  'Create Event',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _isLoading ? null : _pickCoverImage,
                      child: Container(
                        height: 150,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(
                              context,
                            ).colorScheme.outline.withValues(alpha: 0.3),
                            style: BorderStyle.solid,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _selectedImagePath != null
                            ? Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.file(
                                    File(_selectedImagePath!),
                                    fit: BoxFit.cover,
                                  ),
                                  Align(
                                    alignment: Alignment.bottomCenter,
                                    child: Container(
                                      color: Colors.black.withValues(
                                        alpha: 0.45,
                                      ),
                                      padding: const EdgeInsets.all(8),
                                      child: const Text(
                                        'Tap to change cover image',
                                        style: TextStyle(color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.add_photo_alternate,
                                    size: 48,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.5),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Add Event Cover Image',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withValues(alpha: 0.5),
                                        ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _titleController,
                      decoration: InputDecoration(
                        labelText: 'Event Title *',
                        hintText: 'Enter event name',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        prefixIcon: const Icon(Icons.title),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Title is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _descriptionController,
                      decoration: InputDecoration(
                        labelText: 'Description',
                        hintText: 'Enter event description',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        prefixIcon: const Icon(Icons.description),
                      ),
                      maxLines: 4,
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('Publish immediately'),
                      subtitle: const Text('Guests can see the event'),
                      value: _isPublished,
                      onChanged: (value) =>
                          setState(() => _isPublished = value),
                      contentPadding: EdgeInsets.zero,
                    ),
                    SwitchListTile(
                      title: const Text('AI image enhance'),
                      subtitle: const Text(
                        'Keep original and add enhanced copy',
                      ),
                      value: _autoEnhanceImages,
                      onChanged: (value) =>
                          setState(() => _autoEnhanceImages = value),
                      contentPadding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton(
                        onPressed: _isLoading ? null : _createEvent,
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Create Event',
                                style: TextStyle(fontSize: 16),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventDetailPage extends StatefulWidget {
  final EventModel event;
  final VoidCallback onUpdated;

  const _EventDetailPage({required this.event, required this.onUpdated});

  @override
  State<_EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends State<_EventDetailPage> {
  late EventModel _event;
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _event = widget.event;
    _titleController.text = _event.title;
    _descriptionController.text = _event.description ?? '';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _makeActiveEvent() async {
    await ActiveEventStorage.saveActiveEvent(
      EventSummary(
        id: _event.id,
        title: _event.title,
        description: _event.description,
        imageUrl: _event.imageUrl,
        photosCount: _event.photosCount,
      ),
    );
    AppToast.success('Active upload event updated');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Colors.white,
            iconTheme: const IconThemeData(color: Colors.white),
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                _event.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              titlePadding: const EdgeInsetsDirectional.only(
                start: 56,
                bottom: 16,
                end: 16,
              ),
              background: _event.imageUrl != null && _event.imageUrl!.isNotEmpty
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        ImageLoader.loadImage(
                          _event.imageUrl!,
                          fit: BoxFit.cover,
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.35),
                          ),
                        ),
                      ],
                    )
                  : Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      child: const Icon(
                        Icons.event,
                        size: 64,
                        color: Colors.white,
                      ),
                    ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => _showEditDialog(context),
              ),
              IconButton(
                icon: const Icon(Icons.delete),
                onPressed: _deleteEvent,
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _event.title,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _event.isPublished
                              ? Colors.green
                              : Colors.orange,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _event.isPublished ? 'Published' : 'Draft',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (_event.autoEnhanceImages) ...[
                        const SizedBox(width: 8),
                        const Chip(
                          avatar: Icon(Icons.auto_fix_high, size: 16),
                          label: Text('Enhance'),
                        ),
                      ],
                    ],
                  ),
                  if (UserStorage.currentUser.value?.isPhotographer ??
                      false) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed: _makeActiveEvent,
                        icon: const Icon(Icons.cloud_upload_outlined),
                        label: const Text('Use as active upload event'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () =>
                        _openEventGallery(context, _event.id, _event.title),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primaryContainer.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.photo_library,
                            color: Theme.of(context).colorScheme.primary,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Photo Gallery',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_event.photosCount} photos',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.7),
                                      ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_event.description?.isNotEmpty ?? false) ...[
                    const SizedBox(height: 16),
                    Text(
                      _event.description!,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                  if (UserStorage.currentUser.value?.hasPlannerAccess ??
                      false) ...[
                    const SizedBox(height: 32),
                    Text(
                      'Gallery Access',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _GalleryPrivacySection(eventId: _event.id),
                  ],
                  const SizedBox(height: 32),
                  _EventAlbumsSection(eventId: _event.id),
                  const SizedBox(height: 32),
                  Text(
                    'Invite Photographers',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _InvitePhotographersSection(eventId: _event.id),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openEventGallery(
    BuildContext context,
    String eventId,
    String eventTitle,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            EventGalleryPage(eventId: eventId, albumTitle: eventTitle),
      ),
    );
  }

  void _showEditDialog(BuildContext context) {
    _titleController.text = _event.title;
    _descriptionController.text = _event.description ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _EditEventSheet(
        event: _event,
        titleController: _titleController,
        descriptionController: _descriptionController,
        onSave: (updated) {
          setState(() => _event = updated);
          widget.onUpdated();
        },
      ),
    );
  }

  Future<void> _deleteEvent() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Event'),
        content: const Text('Are you sure? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (!mounted) return;
      try {
        await DioHelper.delete('/event/delete?id=${_event.id}');
        if (mounted) {
          Navigator.pop(context);
          widget.onUpdated();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Failed to delete')));
        }
      }
    }
  }
}

class _GalleryPrivacySection extends StatefulWidget {
  const _GalleryPrivacySection({required this.eventId});

  final String eventId;

  @override
  State<_GalleryPrivacySection> createState() => _GalleryPrivacySectionState();
}

class _GalleryPrivacySectionState extends State<_GalleryPrivacySection> {
  final _passwordController = TextEditingController();
  final _storeCurrencyController = TextEditingController(text: 'USD');
  final _singlePriceController = TextEditingController(text: '5');
  final _wholeEventPriceController = TextEditingController(text: '0');
  final _bundlePriceController = TextEditingController(text: '0');
  final _bundleMinController = TextEditingController(text: '10');
  final _stripeLabelController = TextEditingController();
  final _stripeSecretController = TextEditingController();
  final _stripeWebhookController = TextEditingController();
  String _mode = 'public';
  String _loadedMode = 'public';
  bool _loading = true;
  bool _saving = false;
  bool _faceSearchEnabled = false;
  bool _guestNotificationsEnabled = false;
  bool _emailNotificationsEnabled = true;
  bool _whatsappNotificationsEnabled = false;
  bool _uploadingWatermark = false;
  bool _storeLoading = true;
  bool _storeSaving = false;
  bool _storeEnabled = false;
  bool _watermarkedPreview = true;
  bool _useCustomStripe = false;
  bool _customStripeConfigured = false;
  bool _customStripeWebhookConfigured = false;
  Map<String, dynamic> _branding = {};
  String _watermarkPosition = 'bottom_right';
  double _watermarkOpacity = 0.7;
  double _watermarkScale = 24;

  @override
  void initState() {
    super.initState();
    _load();
    _loadStore();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _storeCurrencyController.dispose();
    _singlePriceController.dispose();
    _wholeEventPriceController.dispose();
    _bundlePriceController.dispose();
    _bundleMinController.dispose();
    _stripeLabelController.dispose();
    _stripeSecretController.dispose();
    _stripeWebhookController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final response = await DioHelper.get(
        '/gallery-access/settings',
        queryParameters: {'eventId': widget.eventId},
      );
      final raw = response.data is Map ? response.data['data'] : null;
      final data = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};
      final mode = data['galleryVisibility']?.toString() ?? 'public';
      if (mounted) {
        setState(() {
          _mode = mode;
          _loadedMode = mode;
          _faceSearchEnabled = data['faceSearchEnabled'] == true;
          _guestNotificationsEnabled =
              data['guestNotificationsEnabled'] == true;
          _emailNotificationsEnabled =
              data['emailNotificationsEnabled'] != false;
          _whatsappNotificationsEnabled =
              data['whatsappNotificationsEnabled'] == true;
          final brandingRaw = data['branding'];
          _branding = brandingRaw is Map
              ? Map<String, dynamic>.from(brandingRaw)
              : <String, dynamic>{};
          _watermarkPosition =
              _branding['watermarkPosition']?.toString() ?? 'bottom_right';
          _watermarkOpacity =
              (_branding['watermarkOpacity'] as num?)?.toDouble() ?? 0.7;
          _watermarkScale =
              (_branding['watermarkScale'] as num?)?.toDouble() ?? 24;
        });
      }
    } catch (_) {
      AppToast.error('Could not load gallery privacy');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadStore() async {
    try {
      final response = await DioHelper.get(
        '/store/settings',
        queryParameters: {'eventId': widget.eventId},
      );
      final raw = response.data is Map ? response.data['data'] : null;
      final data = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _storeEnabled = data['enabled'] == true;
        _watermarkedPreview = data['watermarkedPreview'] != false;
        _useCustomStripe = data['useCustomStripe'] == true;
        _customStripeConfigured = data['customStripeConfigured'] == true;
        _customStripeWebhookConfigured =
            data['customStripeWebhookConfigured'] == true;
        _storeCurrencyController.text =
            data['currency']?.toString().isNotEmpty == true
            ? data['currency'].toString()
            : 'USD';
        _singlePriceController.text =
            ((data['singlePhotoPrice'] as num?)?.toDouble() ?? 5).toString();
        _wholeEventPriceController.text =
            ((data['wholeEventPrice'] as num?)?.toDouble() ?? 0).toString();
        _bundlePriceController.text =
            ((data['bundlePrice'] as num?)?.toDouble() ?? 0).toString();
        _bundleMinController.text =
            ((data['bundleMinPhotos'] as num?)?.toInt() ?? 10).toString();
        _stripeLabelController.text =
            data['stripeAccountLabel']?.toString() ?? '';
      });
    } catch (_) {
      AppToast.error('Could not load store settings');
    } finally {
      if (mounted) setState(() => _storeLoading = false);
    }
  }

  Future<void> _pickWatermark() async {
    if (_uploadingWatermark) return;
    setState(() => _uploadingWatermark = true);
    try {
      final picked = await ImageUploadHelper.pickFromGallery();
      if (picked == null) return;
      final url = await ImageUploadHelper.uploadFile(
        path: picked.path,
        filename: picked.name,
      );
      if (!mounted) return;
      setState(() {
        _branding = {..._branding, 'watermarkUrl': url};
      });
      AppToast.success('Watermark uploaded');
    } catch (_) {
      AppToast.error('Could not upload watermark');
    } finally {
      if (mounted) setState(() => _uploadingWatermark = false);
    }
  }

  Future<void> _saveStore() async {
    if (_storeSaving) return;
    final singlePrice = double.tryParse(_singlePriceController.text.trim());
    final wholeEventPrice = double.tryParse(
      _wholeEventPriceController.text.trim(),
    );
    final bundlePrice = double.tryParse(_bundlePriceController.text.trim());
    final bundleMin = int.tryParse(_bundleMinController.text.trim());
    if (singlePrice == null ||
        singlePrice < 0 ||
        wholeEventPrice == null ||
        wholeEventPrice < 0 ||
        bundlePrice == null ||
        bundlePrice < 0 ||
        bundleMin == null ||
        bundleMin < 2) {
      AppToast.error('Check store prices and bundle minimum');
      return;
    }
    setState(() => _storeSaving = true);
    try {
      final data = <String, dynamic>{
        'eventId': widget.eventId,
        'enabled': _storeEnabled,
        'currency': _storeCurrencyController.text.trim().toUpperCase(),
        'singlePhotoPrice': singlePrice,
        'wholeEventPrice': wholeEventPrice,
        'bundlePrice': bundlePrice,
        'bundleMinPhotos': bundleMin,
        'watermarkedPreview': _watermarkedPreview,
        'useCustomStripe': _useCustomStripe,
        'stripeAccountLabel': _stripeLabelController.text.trim(),
      };
      if (_stripeSecretController.text.trim().isNotEmpty) {
        data['stripeSecretKey'] = _stripeSecretController.text.trim();
      }
      if (_stripeWebhookController.text.trim().isNotEmpty) {
        data['stripeWebhookSecret'] = _stripeWebhookController.text.trim();
      }
      await DioHelper.patch('/store/settings', data: data);
      _stripeSecretController.clear();
      _stripeWebhookController.clear();
      AppToast.success('Store settings saved');
      await _loadStore();
    } catch (_) {
      AppToast.error('Could not update store settings');
    } finally {
      if (mounted) setState(() => _storeSaving = false);
    }
  }

  Future<void> _save() async {
    final password = _passwordController.text.trim();
    if (_mode == 'password' && _loadedMode != 'password' && password.isEmpty) {
      AppToast.error('Enter a gallery password');
      return;
    }
    setState(() => _saving = true);
    try {
      await DioHelper.patch(
        '/gallery-access/settings',
        data: {
          'eventId': widget.eventId,
          'visibility': _mode,
          'faceSearchEnabled': _faceSearchEnabled,
          'guestNotificationsEnabled': _guestNotificationsEnabled,
          'emailNotificationsEnabled': _emailNotificationsEnabled,
          'whatsappNotificationsEnabled': _whatsappNotificationsEnabled,
          'branding': {
            ..._branding,
            'watermarkPosition': _watermarkPosition,
            'watermarkOpacity': _watermarkOpacity,
            'watermarkScale': _watermarkScale,
          },
          if (_mode == 'password' && password.isNotEmpty) 'password': password,
        },
      );
      _passwordController.clear();
      _loadedMode = _mode;
      AppToast.success(
        _mode == 'password'
            ? 'Gallery is password protected'
            : 'Gallery access updated',
      );
    } catch (_) {
      AppToast.error('Could not update gallery privacy');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _mode,
              decoration: const InputDecoration(
                labelText: 'Who can view this gallery?',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'public',
                  child: Text('Public - anyone with link'),
                ),
                DropdownMenuItem(
                  value: 'password',
                  child: Text('Password protected'),
                ),
                DropdownMenuItem(
                  value: 'private',
                  child: Text('Private secure link only'),
                ),
                DropdownMenuItem(
                  value: 'facial',
                  child: Text('Face recognition privacy'),
                ),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _mode = value ?? 'public'),
            ),
            if (_mode == 'password') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: _loadedMode == 'password'
                      ? 'New password (optional)'
                      : 'Gallery password',
                  hintText: _loadedMode == 'password'
                      ? 'Leave blank to keep current password'
                      : 'Required',
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'Password-protected galleries block viewing and downloads until the guest unlocks the gallery.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _faceSearchEnabled,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _faceSearchEnabled = value),
              title: const Text('Face recognition'),
              subtitle: const Text(
                'Allow guests to build personal galleries and use the face-delivery QR.',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _guestNotificationsEnabled,
              onChanged: _saving
                  ? null
                  : (value) =>
                        setState(() => _guestNotificationsEnabled = value),
              title: const Text('Automatic match alerts'),
              subtitle: const Text(
                'Send a personal gallery link when this event finds a registered guest.',
              ),
            ),
            if (_guestNotificationsEnabled) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _emailNotificationsEnabled,
                onChanged: _saving
                    ? null
                    : (value) =>
                          setState(() => _emailNotificationsEnabled = value),
                title: const Text('Email delivery'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _whatsappNotificationsEnabled,
                onChanged: _saving
                    ? null
                    : (value) =>
                          setState(() => _whatsappNotificationsEnabled = value),
                title: const Text('WhatsApp delivery'),
              ),
            ],
            const Divider(height: 28),
            Text(
              'Store',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Sell individual originals or the complete event. Paid downloads use the original full-resolution source, never the watermarked preview.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (_storeLoading)
              const Center(child: CircularProgressIndicator())
            else ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _storeEnabled,
                onChanged: _storeSaving
                    ? null
                    : (value) => setState(() => _storeEnabled = value),
                title: const Text('Enable store for this event'),
                subtitle: const Text(
                  'Guests can purchase original files from the event store.',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _storeCurrencyController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Currency',
                  hintText: 'USD',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _singlePriceController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Price per photo',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _wholeEventPriceController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Whole event price',
                        helperText: '0 disables',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _bundlePriceController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Bundle price',
                        helperText: '0 disables',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _bundleMinController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Bundle starts at',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _watermarkedPreview,
                onChanged: _storeSaving
                    ? null
                    : (value) => setState(() => _watermarkedPreview = value),
                title: const Text('Watermark store previews'),
                subtitle: const Text(
                  'Only previews are watermarked; purchased files stay original.',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _useCustomStripe,
                onChanged: _storeSaving
                    ? null
                    : (value) => setState(() => _useCustomStripe = value),
                title: const Text('Use my Stripe account'),
                subtitle: Text(
                  _customStripeConfigured
                      ? 'Stripe secret is already saved for this event.'
                      : 'Otherwise the platform Stripe account is used.',
                ),
              ),
              if (_useCustomStripe) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _stripeLabelController,
                  decoration: const InputDecoration(
                    labelText: 'Stripe account label',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _stripeSecretController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Stripe secret key',
                    hintText: _customStripeConfigured
                        ? 'Saved - leave blank to keep it'
                        : 'sk_live_... or sk_test_...',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _stripeWebhookController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Stripe webhook secret',
                    hintText: _customStripeWebhookConfigured
                        ? 'Saved - leave blank to keep it'
                        : 'whsec_...',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _storeSaving ? null : _saveStore,
                  icon: _storeSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.storefront_outlined),
                  label: Text(
                    _storeSaving ? 'Saving store...' : 'Save store settings',
                  ),
                ),
              ),
            ],
            const Divider(height: 28),
            Text(
              'Store preview watermark',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Preview files are resized and watermarked. Paid customers receive the original full-resolution file without this watermark.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if ((_branding['watermarkUrl']?.toString().isNotEmpty ?? false))
              Container(
                height: 90,
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(8),
                child: ImageLoader.loadImage(
                  _branding['watermarkUrl'].toString(),
                  fit: BoxFit.contain,
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _uploadingWatermark ? null : _pickWatermark,
                    icon: _uploadingWatermark
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.branding_watermark_outlined),
                    label: Text(
                      _branding['watermarkUrl'] == null
                          ? 'Upload watermark'
                          : 'Replace watermark',
                    ),
                  ),
                ),
                if (_branding['watermarkUrl'] != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Remove watermark',
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                            _branding = {..._branding}..remove('watermarkUrl');
                          }),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _watermarkPosition,
              decoration: const InputDecoration(
                labelText: 'Watermark position',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'top_left', child: Text('Top left')),
                DropdownMenuItem(
                  value: 'top_center',
                  child: Text('Top center'),
                ),
                DropdownMenuItem(value: 'top_right', child: Text('Top right')),
                DropdownMenuItem(value: 'center', child: Text('Center')),
                DropdownMenuItem(
                  value: 'bottom_left',
                  child: Text('Bottom left'),
                ),
                DropdownMenuItem(
                  value: 'bottom_center',
                  child: Text('Bottom center'),
                ),
                DropdownMenuItem(
                  value: 'bottom_right',
                  child: Text('Bottom right'),
                ),
                DropdownMenuItem(value: 'tile', child: Text('Tile')),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(
                      () => _watermarkPosition = value ?? 'bottom_right',
                    ),
            ),
            const SizedBox(height: 12),
            Text('Opacity ${(_watermarkOpacity * 100).round()}%'),
            Slider(
              value: _watermarkOpacity.clamp(0.05, 1),
              min: 0.05,
              max: 1,
              divisions: 19,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _watermarkOpacity = value),
            ),
            Text('Size ${_watermarkScale.round()}% of preview width'),
            Slider(
              value: _watermarkScale.clamp(5, 80),
              min: 5,
              max: 80,
              divisions: 15,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _watermarkScale = value),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.lock_outline),
                label: Text(_saving ? 'Saving...' : 'Save gallery access'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvitePhotographersSection extends StatefulWidget {
  final String eventId;

  const _InvitePhotographersSection({required this.eventId});

  @override
  State<_InvitePhotographersSection> createState() =>
      _InvitePhotographersSectionState();
}

class _InvitePhotographersSectionState
    extends State<_InvitePhotographersSection> {
  final _searchController = TextEditingController();
  List<PhotographerModel> _photographers = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _searchPhotographers('');
  }

  Future<void> _searchPhotographers(String query) async {
    setState(() => _isSearching = true);
    try {
      final response = await DioHelper.get(
        '/user/get-all',
        queryParameters: {
          'role': 'photographer',
          if (query.isNotEmpty) 'query': query,
        },
      );
      final data = response.data['data'] as List? ?? [];
      setState(() {
        _photographers = data
            .map(
              (item) =>
                  PhotographerModel.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList();
      });
    } catch (e) {
      // handle error
    } finally {
      setState(() => _isSearching = false);
    }
  }

  Future<void> _invitePhotographer(PhotographerModel photographer) async {
    try {
      await DioHelper.post(
        '/event/invite-photographer',
        data: {'eventId': widget.eventId, 'photographerId': photographer.id},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invited ${photographer.displayName}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to invite')));
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search photographers...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _searchPhotographers('');
                        },
                      )
                    : null,
              ),
              onChanged: (value) => _searchPhotographers(value),
            ),
            const SizedBox(height: 16),
            if (_isSearching)
              const Center(child: CircularProgressIndicator())
            else if (_photographers.isEmpty)
              const Center(child: Text('No photographers found'))
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _photographers.length,
                itemBuilder: (context, index) {
                  final photographer = _photographers[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                      child: Icon(
                        Icons.person,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    title: Text(photographer.displayName),
                    subtitle: Text(
                      photographer.email ?? photographer.phone ?? '',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.person_add),
                      onPressed: () => _invitePhotographer(photographer),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _EventAlbumsSection extends StatefulWidget {
  const _EventAlbumsSection({required this.eventId});

  final String eventId;

  @override
  State<_EventAlbumsSection> createState() => _EventAlbumsSectionState();
}

class _EventAlbumsSectionState extends State<_EventAlbumsSection> {
  List<AlbumModel> _albums = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAlbums();
  }

  Future<void> _loadAlbums() async {
    setState(() => _loading = true);
    try {
      final response = await DioHelper.get(
        '/album/get-all',
        queryParameters: {'eventId': widget.eventId},
      );
      final data = response.data['data'] as List? ?? [];
      setState(() {
        _albums = data
            .map((item) => AlbumModel.fromJson(Map<String, dynamic>.from(item)))
            .toList();
      });
    } catch (_) {
      setState(() => _albums = []);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _openCreateAlbum() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          _CreateAlbumSheet(eventId: widget.eventId, onCreated: _loadAlbums),
    );
  }

  void _openAlbum(AlbumModel album) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EventGalleryPage(
          eventId: widget.eventId,
          albumId: album.id,
          albumTitle: album.title,
        ),
      ),
    );
  }

  Future<void> _deleteAlbum(AlbumModel album) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Album'),
        content: Text(
          'Delete "${album.title}"? Images will stay in event gallery.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await DioHelper.delete('/album/delete?id=${album.id}');
      AppToast.success('Album deleted');
      _loadAlbums();
    } catch (_) {
      AppToast.error('Failed to delete album');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Albums',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _openCreateAlbum,
              icon: const Icon(Icons.add),
              label: const Text('Create'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_albums.isEmpty)
          Card(
            child: ListTile(
              leading: const Icon(Icons.photo_album_outlined),
              title: const Text('No albums yet'),
              subtitle: const Text('Create albums inside this event.'),
              trailing: const Icon(Icons.add),
              onTap: _openCreateAlbum,
            ),
          )
        else
          ..._albums.map(
            (album) => Card(
              child: ListTile(
                leading: const Icon(Icons.photo_album_outlined),
                title: Text(album.title),
                subtitle: album.description == null
                    ? null
                    : Text(album.description!),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      tooltip: 'Delete album',
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _deleteAlbum(album),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: () => _openAlbum(album),
              ),
            ),
          ),
      ],
    );
  }
}

class _CreateAlbumSheet extends StatefulWidget {
  const _CreateAlbumSheet({required this.eventId, required this.onCreated});

  final String eventId;
  final VoidCallback onCreated;

  @override
  State<_CreateAlbumSheet> createState() => _CreateAlbumSheetState();
}

class _CreateAlbumSheetState extends State<_CreateAlbumSheet> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Album title is required')));
      return;
    }

    setState(() => _saving = true);
    try {
      await DioHelper.post(
        '/album',
        data: {
          'eventId': widget.eventId,
          'title': title,
          'description': _descriptionController.text.trim(),
        },
      );
      widget.onCreated();
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to create album')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Create Album',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Album title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _create,
                child: Text(_saving ? 'Creating...' : 'Create Album'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditEventSheet extends StatefulWidget {
  final EventModel event;
  final TextEditingController titleController;
  final TextEditingController descriptionController;
  final Function(EventModel) onSave;

  const _EditEventSheet({
    required this.event,
    required this.titleController,
    required this.descriptionController,
    required this.onSave,
  });

  @override
  State<_EditEventSheet> createState() => _EditEventSheetState();
}

class _EditEventSheetState extends State<_EditEventSheet> {
  bool _isLoading = false;
  bool _isPublished = false;
  bool _autoEnhanceImages = false;
  String? _selectedImagePath;
  String? _selectedImageName;

  @override
  void initState() {
    super.initState();
    _isPublished = widget.event.isPublished;
    _autoEnhanceImages = widget.event.autoEnhanceImages;
  }

  Future<void> _pickCoverImage() async {
    try {
      final picked = await ImageUploadHelper.pickFromGallery();
      if (picked == null || !mounted) return;
      setState(() {
        _selectedImagePath = picked.path;
        _selectedImageName = picked.name;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to pick cover image')),
        );
      }
    }
  }

  Future<void> _saveEvent() async {
    setState(() => _isLoading = true);
    try {
      String? imageUrl = widget.event.imageUrl;
      if (_selectedImagePath != null && _selectedImageName != null) {
        imageUrl = await ImageUploadHelper.uploadFile(
          path: _selectedImagePath!,
          filename: _selectedImageName!,
        );
      }

      final response = await DioHelper.patch(
        '/event/update?id=${widget.event.id}',
        data: {
          'title': widget.titleController.text.trim(),
          'description': widget.descriptionController.text.trim(),
          'isPublished': _isPublished,
          'autoEnhanceImages': _autoEnhanceImages,
          if (imageUrl != null && imageUrl.isNotEmpty)
            'image': {'url': imageUrl},
        },
      );

      final updated = EventModel.fromJson(
        Map<String, dynamic>.from(response.data['data'] as Map),
      );

      widget.onSave(updated);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to update')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: Row(
              children: [
                Text(
                  'Edit Event',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _isLoading ? null : _pickCoverImage,
                    child: Container(
                      height: 150,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _selectedImagePath != null
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.file(
                                  File(_selectedImagePath!),
                                  fit: BoxFit.cover,
                                ),
                                Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    color: Colors.black.withValues(alpha: 0.45),
                                    padding: const EdgeInsets.all(8),
                                    child: const Text(
                                      'Tap to change cover image',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : (widget.event.imageUrl != null &&
                                widget.event.imageUrl!.isNotEmpty)
                          ? ImageLoader.loadImage(
                              widget.event.imageUrl,
                              fit: BoxFit.cover,
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.add_photo_alternate,
                                  size: 48,
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.5),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Change Cover Image',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.5),
                                      ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: widget.titleController,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: widget.descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Published'),
                    value: _isPublished,
                    onChanged: (value) => setState(() => _isPublished = value),
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile(
                    title: const Text('AI image enhance'),
                    subtitle: const Text(
                      'New uploads keep original and add enhanced copy',
                    ),
                    value: _autoEnhanceImages,
                    onChanged: (value) =>
                        setState(() => _autoEnhanceImages = value),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: _isLoading ? null : _saveEvent,
                      child: _isLoading
                          ? const CircularProgressIndicator(strokeWidth: 2)
                          : const Text('Save Changes'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
