import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:mobileapp/core/storage/user_storage.dart';
import 'package:mobileapp/core/utils/image_loader.dart';
import 'package:mobileapp/core/utils/image_upload_helper.dart';
import 'package:mobileapp/models/album_model.dart';
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
      return data.map((item) => EventModel.fromJson(Map<String, dynamic>.from(item))).toList();
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
        !(UserStorage.currentUser.value?.isPhotographer ?? false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Events'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
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
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create your first event to start\nmanaging photo uploads',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            if (!(UserStorage.currentUser.value?.isPhotographer ?? false))
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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _EventDetailPage(event: event, onUpdated: _refresh),
      ),
    ).then((_) => _refresh());
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
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                            color: event.isPublished ? Colors.green : Colors.orange,
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
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.photo_library, size: 16, color: Theme.of(context).colorScheme.primary),
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

      await DioHelper.post('/event', data: {
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'isPublished': _isPublished,
        'autoEnhanceImages': _autoEnhanceImages,
        if (imageUrl != null && imageUrl.isNotEmpty) 'image': {'url': imageUrl},
      });
      
      if (mounted) {
        Navigator.pop(context);
        widget.onCreated();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Event created successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to create event')),
        );
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
                bottom: BorderSide(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)),
              ),
            ),
            child: Row(
              children: [
                Text(
                  'Create Event',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
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
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                            style: BorderStyle.solid,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _selectedImagePath != null
                            ? Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.file(File(_selectedImagePath!), fit: BoxFit.cover),
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
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.add_photo_alternate,
                                    size: 48,
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Add Event Cover Image',
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
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
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        prefixIcon: const Icon(Icons.description),
                      ),
                      maxLines: 4,
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('Publish immediately'),
                      subtitle: const Text('Guests can see the event'),
                      value: _isPublished,
                      onChanged: (value) => setState(() => _isPublished = value),
                      contentPadding: EdgeInsets.zero,
                    ),
                    SwitchListTile(
                      title: const Text('AI image enhance'),
                      subtitle: const Text('Keep original and add enhanced copy'),
                      value: _autoEnhanceImages,
                      onChanged: (value) => setState(() => _autoEnhanceImages = value),
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
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Create Event', style: TextStyle(fontSize: 16)),
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

  Future<List<PhotographerModel>> _searchPhotographers(String query) async {
    try {
      final response = await DioHelper.get('/user/get-all', queryParameters: {
        'role': 'photographer',
        if (query.isNotEmpty) 'search': query,
      });
      final data = response.data['data'] as List? ?? [];
      return data.map((item) => PhotographerModel.fromJson(Map<String, dynamic>.from(item))).toList();
    } catch (e) {
      return [];
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
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
                        ImageLoader.loadImage(_event.imageUrl!, fit: BoxFit.cover),
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
              IconButton(icon: const Icon(Icons.edit), onPressed: () => _showEditDialog(context)),
              IconButton(icon: const Icon(Icons.delete), onPressed: () => _deleteEvent(context)),
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
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _event.isPublished ? Colors.green : Colors.orange,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _event.isPublished ? 'Published' : 'Draft',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
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
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () => _openEventGallery(context, _event.id, _event.title),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.photo_library, color: Theme.of(context).colorScheme.primary, size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Photo Gallery',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_event.photosCount} photos',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
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
                    Text(_event.description!, style: Theme.of(context).textTheme.bodyLarge),
                  ],
                  const SizedBox(height: 32),
                  _EventAlbumsSection(eventId: _event.id),
                  const SizedBox(height: 32),
                  Text('Invite Photographers', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
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

  void _openEventGallery(BuildContext context, String eventId, String eventTitle) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EventGalleryPage(eventId: eventId, albumTitle: eventTitle),
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

  Future<void> _deleteEvent(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Event'),
        content: const Text('Are you sure? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      try {
        await DioHelper.delete('/event/delete?id=${_event.id}');
        if (mounted) {
          Navigator.pop(context);
          widget.onUpdated();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete')));
        }
      }
    }
  }
}

class _InvitePhotographersSection extends StatefulWidget {
  final String eventId;

  const _InvitePhotographersSection({required this.eventId});

  @override
  State<_InvitePhotographersSection> createState() => _InvitePhotographersSectionState();
}

class _InvitePhotographersSectionState extends State<_InvitePhotographersSection> {
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
      final response = await DioHelper.get('/user/get-all', queryParameters: {
        'role': 'photographer',
        if (query.isNotEmpty) 'query': query,
      });
      final data = response.data['data'] as List? ?? [];
      setState(() {
        _photographers = data.map((item) => PhotographerModel.fromJson(Map<String, dynamic>.from(item))).toList();
      });
    } catch (e) {
      // handle error
    } finally {
      setState(() => _isSearching = false);
    }
  }

  Future<void> _invitePhotographer(PhotographerModel photographer) async {
    try {
      await DioHelper.post('/event/invite-photographer', data: {
        'eventId': widget.eventId,
        'photographerId': photographer.id,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invited ${photographer.displayName}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to invite')));
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
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      child: Icon(Icons.person, color: Theme.of(context).colorScheme.primary),
                    ),
                    title: Text(photographer.displayName),
                    subtitle: Text(photographer.email ?? photographer.phone ?? ''),
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
      builder: (context) => _CreateAlbumSheet(
        eventId: widget.eventId,
        onCreated: _loadAlbums,
      ),
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
        content: Text('Delete "${album.title}"? Images will stay in event gallery.'),
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
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
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
  const _CreateAlbumSheet({
    required this.eventId,
    required this.onCreated,
  });

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Album title is required')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await DioHelper.post('/album', data: {
        'eventId': widget.eventId,
        'title': title,
        'description': _descriptionController.text.trim(),
      });
      widget.onCreated();
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to create album')),
        );
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
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
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

      final response = await DioHelper.patch('/event/update?id=${widget.event.id}', data: {
        'title': widget.titleController.text.trim(),
        'description': widget.descriptionController.text.trim(),
        'isPublished': _isPublished,
        'autoEnhanceImages': _autoEnhanceImages,
        if (imageUrl != null && imageUrl.isNotEmpty) 'image': {'url': imageUrl},
      });

      final updated = EventModel.fromJson(
        Map<String, dynamic>.from(response.data['data'] as Map),
      );
      
      widget.onSave(updated);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to update')));
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
                bottom: BorderSide(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)),
              ),
            ),
            child: Row(
              children: [
                Text('Edit Event', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
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
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _selectedImagePath != null
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.file(File(_selectedImagePath!), fit: BoxFit.cover),
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
                                    Icon(Icons.add_photo_alternate, size: 48, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                                    const SizedBox(height: 8),
                                    Text('Change Cover Image', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))),
                                  ],
                                ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: widget.titleController,
                    decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: widget.descriptionController,
                    decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
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
                    subtitle: const Text('New uploads keep original and add enhanced copy'),
                    value: _autoEnhanceImages,
                    onChanged: (value) => setState(() => _autoEnhanceImages = value),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: _isLoading ? null : _saveEvent,
                      child: _isLoading ? const CircularProgressIndicator(strokeWidth: 2) : const Text('Save Changes'),
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
