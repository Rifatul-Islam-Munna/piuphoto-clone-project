import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:mobileapp/core/platform/image_downloads.dart';
import 'package:mobileapp/core/theme/app_theme.dart';
import 'package:mobileapp/core/utils/image_loader.dart';
import 'package:mobileapp/models/album_model.dart';
import 'package:mobileapp/models/event_image_model.dart';
import 'package:mobileapp/utilities/app_toast.dart';
import 'package:mobileapp/widgets/app_ui.dart';

class EventGalleryPage extends StatefulWidget {
  const EventGalleryPage({
    super.key,
    required this.eventId,
    this.albumId,
    this.albumTitle,
    this.publicAccess = false,
    this.faceEnrollment = false,
  });

  final String eventId;
  final String? albumId;
  final String? albumTitle;
  final bool publicAccess;
  final bool faceEnrollment;

  @override
  State<EventGalleryPage> createState() => _EventGalleryPageState();
}

class _EventGalleryPageState extends State<EventGalleryPage> {
  static const _pageSize = 20;

  final _scrollController = ScrollController();
  final List<EventImageModel> _allImages = [];
  final ImagePicker _imagePicker = ImagePicker();
  final _passwordController = TextEditingController();
  final _emailController = TextEditingController();
  final _whatsappController = TextEditingController();
  final List<XFile> _profileSelfies = [];
  final List<AlbumModel> _albums = [];
  final Set<String> _selectedIds = {};
  Timer? _personalGalleryTimer;
  int _visibleCount = _pageSize;
  bool _loading = true;
  bool _saving = false;
  bool _faceSearching = false;
  bool _showingFaceMatches = false;
  bool _unlocking = false;
  bool _accessBlocked = false;
  bool _requiresPassword = false;
  bool _requiresPrivateLink = false;
  bool _requiresFaceSearch = false;
  bool _guestNotificationsEnabled = false;
  bool _emailNotificationsEnabled = true;
  bool _whatsappNotificationsEnabled = false;
  bool _profileConsent = false;
  bool _notifyEmail = true;
  bool _notifyWhatsapp = true;
  bool _registeringProfile = false;
  String? _guestToken;
  String? _accessToken;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    if (!widget.publicAccess) {
      _loadAlbums();
    }
    _scrollController.addListener(_loadMoreWhenNeeded);
  }

  @override
  void dispose() {
    _personalGalleryTimer?.cancel();
    _scrollController.dispose();
    _passwordController.dispose();
    _emailController.dispose();
    _whatsappController.dispose();
    super.dispose();
  }

  Future<bool> _preparePublicAccess() async {
    if (!widget.publicAccess) return true;
    final response = await DioHelper.get(
      '/gallery-access/info',
      queryParameters: {
        'eventId': widget.eventId,
        if (widget.albumId != null) 'albumId': widget.albumId,
        if (_accessToken != null) 'accessToken': _accessToken,
      },
    );
    final raw = response.data;
    final info = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    final unlocked = info['unlocked'] == true;
    if (mounted) {
      setState(() {
        _requiresPassword = info['requiresPassword'] == true;
        _requiresPrivateLink = info['requiresPrivateLink'] == true;
        _requiresFaceSearch = info['requiresFaceSearch'] == true;
        _guestNotificationsEnabled = info['guestNotificationsEnabled'] == true;
        _emailNotificationsEnabled = info['emailNotificationsEnabled'] != false;
        _whatsappNotificationsEnabled =
            info['whatsappNotificationsEnabled'] == true;
        if (!widget.faceEnrollment) {
          _notifyEmail = _emailNotificationsEnabled;
          _notifyWhatsapp = _whatsappNotificationsEnabled;
        }
        _accessBlocked =
            !unlocked &&
            (_requiresPassword || _requiresPrivateLink || _requiresFaceSearch);
      });
    }
    return unlocked || !_accessBlocked;
  }

  Future<void> _unlockGallery() async {
    final password = _passwordController.text.trim();
    if (password.isEmpty) {
      AppToast.error('Enter the gallery password');
      return;
    }
    setState(() => _unlocking = true);
    try {
      final response = await DioHelper.post(
        '/gallery-access/unlock',
        data: {
          'eventId': widget.eventId,
          if (widget.albumId != null) 'albumId': widget.albumId,
          'password': password,
        },
      );
      final token = response.data is Map
          ? response.data['accessToken']?.toString()
          : null;
      if (token == null || token.isEmpty) {
        throw Exception('Missing gallery access token');
      }
      _accessToken = token;
      _passwordController.clear();
      await _load();
    } on DioException catch (error) {
      AppToast.error(
        error.response?.data?['message']?.toString() ??
            'Invalid gallery password',
      );
    } catch (_) {
      AppToast.error('Could not unlock gallery');
    } finally {
      if (mounted) setState(() => _unlocking = false);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (widget.publicAccess && !(await _preparePublicAccess())) {
        setState(() {
          _allImages.clear();
          _visibleCount = 0;
        });
        return;
      }
      final response = await DioHelper.get(
        widget.publicAccess ? '/eventImage/public' : '/eventImage/get-all',
        queryParameters: {
          'eventId': widget.eventId,
          if (widget.albumId != null) 'albumId': widget.albumId,
          if (widget.publicAccess && _accessToken != null)
            'accessToken': _accessToken,
        },
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
        _showingFaceMatches = false;
      });
    } catch (error) {
      setState(() => _error = 'Failed to load event images');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _findMyPictures() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );
    if (picked == null) return;

    setState(() {
      _faceSearching = true;
      _error = null;
    });

    try {
      final formData = FormData.fromMap({
        'image': await MultipartFile.fromFile(
          picked.path,
          filename: picked.name,
        ),
      });
      final response = await DioHelper.post(
        widget.publicAccess
            ? '/eventImage/public/my-picture'
            : '/eventImage/my-picture',
        data: formData,
        queryParameters: {
          'eventId': widget.eventId,
          if (widget.albumId != null) 'albumId': widget.albumId,
          if (widget.publicAccess && _accessToken != null)
            'accessToken': _accessToken,
          'limit': 10000,
        },
        options: Options(contentType: Headers.multipartFormDataContentType),
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
        _selectedIds.clear();
        _showingFaceMatches = true;
        _accessBlocked = false;
        _requiresFaceSearch = false;
      });
      AppToast.success('Found ${images.length} matching images');
    } catch (_) {
      AppToast.error('Face search failed');
    } finally {
      if (mounted) {
        setState(() => _faceSearching = false);
      }
    }
  }

  Future<void> _loadAlbums() async {
    try {
      final response = await DioHelper.get(
        '/album/get-all',
        queryParameters: {'eventId': widget.eventId},
      );
      final data = response.data['data'] as List? ?? [];
      setState(() {
        _albums
          ..clear()
          ..addAll(
            data.map(
              (item) => AlbumModel.fromJson(Map<String, dynamic>.from(item)),
            ),
          );
      });
    } catch (_) {}
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

  Future<void> _assignToAlbum(AlbumModel album) async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) {
      AppToast.error('Select images first');
      return;
    }

    setState(() => _saving = true);
    try {
      for (final id in ids) {
        await DioHelper.patch(
          '/eventImage/update?id=$id',
          data: {'eventId': widget.eventId, 'albumId': album.id},
        );
      }
      AppToast.success('Moved ${ids.length} images to ${album.title}');
      _selectedIds.clear();
      await _load();
    } catch (_) {
      AppToast.error('Failed to move images');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _showAlbumPicker() {
    if (_albums.isEmpty) {
      AppToast.error('Create an album first');
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Move selected to album')),
            for (final album in _albums)
              ListTile(
                leading: const Icon(Icons.photo_album_outlined),
                title: Text(album.title),
                subtitle: album.description == null
                    ? null
                    : Text(album.description!),
                onTap: () {
                  Navigator.pop(context);
                  _assignToAlbum(album);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _addProfileSelfie() async {
    if (_profileSelfies.length >= 5) return;
    final picked = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );
    if (picked == null || !mounted) return;
    setState(() => _profileSelfies.add(picked));
  }

  Future<void> _registerGlobalFaceProfile() async {
    if (_profileSelfies.length < 2) {
      AppToast.error('Take at least 2 clear selfies');
      return;
    }
    if (_emailController.text.trim().isEmpty ||
        _whatsappController.text.trim().isEmpty) {
      AppToast.error('Email and WhatsApp are required');
      return;
    }
    if (!_profileConsent) {
      AppToast.error('Face profile consent is required');
      return;
    }

    setState(() => _registeringProfile = true);
    try {
      final files = <MultipartFile>[];
      for (final selfie in _profileSelfies.take(5)) {
        files.add(
          await MultipartFile.fromFile(selfie.path, filename: selfie.name),
        );
      }
      final formData = FormData.fromMap({
        'eventId': widget.eventId,
        if (widget.albumId != null) 'albumId': widget.albumId,
        'consent': 'true',
        'globalProfile': 'true',
        'email': _emailController.text.trim(),
        'whatsapp': _whatsappController.text.trim(),
        'notifyEmail': _notifyEmail.toString(),
        'notifyWhatsapp': _notifyWhatsapp.toString(),
        if (_accessToken != null) 'accessToken': _accessToken,
        'selfies': files,
      });
      final response = await DioHelper.post(
        '/guest-gallery/register',
        data: formData,
        options: Options(contentType: Headers.multipartFormDataContentType),
      );
      final raw = response.data is Map ? response.data : null;
      final token = raw?['guestToken']?.toString();
      if (token == null || token.isEmpty) {
        throw Exception('Missing personal gallery token');
      }
      _guestToken = token;
      AppToast.success(
        raw?['updatedGlobalProfile'] == true
            ? 'Global face profile updated'
            : 'Global face profile created',
      );
      await _loadPersonalGallery();
      _personalGalleryTimer?.cancel();
      _personalGalleryTimer = Timer.periodic(
        const Duration(seconds: 6),
        (_) => _loadPersonalGallery(silent: true),
      );
    } on DioException catch (error) {
      AppToast.error(
        error.response?.data?['message']?.toString() ??
            'Could not create face profile',
      );
    } catch (_) {
      AppToast.error('Could not create face profile');
    } finally {
      if (mounted) setState(() => _registeringProfile = false);
    }
  }

  Future<void> _loadPersonalGallery({bool silent = false}) async {
    final token = _guestToken;
    if (token == null || token.isEmpty) return;
    try {
      final response = await DioHelper.get(
        '/guest-gallery/personal',
        queryParameters: {
          'eventId': widget.eventId,
          if (widget.albumId != null) 'albumId': widget.albumId,
          'guestToken': token,
        },
      );
      final data = response.data is Map ? response.data['data'] : null;
      final rows = data is List ? data : const [];
      final images = rows
          .whereType<Map>()
          .map(
            (item) => EventImageModel.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
      if (!mounted) return;
      setState(() {
        _allImages
          ..clear()
          ..addAll(images);
        _visibleCount = images.length < _pageSize ? images.length : _pageSize;
        _accessBlocked = false;
        _error = null;
        _loading = false;
      });
    } catch (_) {
      if (!silent && mounted) {
        setState(() => _error = 'Could not load your personal gallery');
      }
    }
  }

  Widget _buildGlobalFaceEnrollment() {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.face_retouching_natural_outlined,
                      size: 34,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Global face delivery',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Take 2-5 clear selfies. Your profile gets stronger when you scan again later.',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < _profileSelfies.length; i++)
                      InputChip(
                        avatar: const Icon(Icons.face, size: 18),
                        label: Text('Selfie ${i + 1}'),
                        onDeleted: _registeringProfile
                            ? null
                            : () => setState(() => _profileSelfies.removeAt(i)),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed:
                        _profileSelfies.length >= 5 || _registeringProfile
                        ? null
                        : _addProfileSelfie,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: Text(
                      _profileSelfies.isEmpty
                          ? 'Take first selfie'
                          : 'Add selfie (${_profileSelfies.length}/5)',
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _whatsappController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'WhatsApp *',
                    hintText: '+1...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                if (_guestNotificationsEnabled && _emailNotificationsEnabled)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _notifyEmail,
                    onChanged: (value) => setState(() => _notifyEmail = value),
                    title: const Text('Email new matches'),
                  ),
                if (_guestNotificationsEnabled && _whatsappNotificationsEnabled)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _notifyWhatsapp,
                    onChanged: (value) =>
                        setState(() => _notifyWhatsapp = value),
                    title: const Text('WhatsApp new matches'),
                  ),
                if (!_guestNotificationsEnabled)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Automatic match alerts are disabled for this event. Your reusable face profile still works for finding your photos.',
                    ),
                  ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _profileConsent,
                  onChanged: (value) =>
                      setState(() => _profileConsent = value == true),
                  title: const Text(
                    'I consent to a reusable global face profile. Face vectors and delivery preferences can be reused at enabled events; original selfie files are not retained.',
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _registeringProfile
                        ? null
                        : _registerGlobalFaceProfile,
                    icon: _registeringProfile
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.person_search_outlined),
                    label: Text(
                      _registeringProfile
                          ? 'Building profile...'
                          : 'Create / update my profile',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAccessGate() {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIconTile(
                    icon: _requiresPassword
                        ? Icons.lock_outline
                        : _requiresFaceSearch
                        ? Icons.face_retouching_natural_outlined
                        : Icons.shield_outlined,
                    size: 58,
                    iconSize: 27,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _requiresPassword
                        ? 'Password protected gallery'
                        : _requiresFaceSearch
                        ? 'Find your photos'
                        : 'Private gallery',
                    style: theme.textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _requiresPassword
                        ? 'Enter the password shared by the photographer to view and download photos.'
                        : _requiresFaceSearch
                        ? 'Take a selfie to see only the photos that match you.'
                        : 'This gallery can only be opened with the secure private link shared by the photographer.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.mutedForeground,
                      height: 1.5,
                    ),
                  ),
                  if (_requiresPassword) ...[
                    const SizedBox(height: 20),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) {
                        if (!_unlocking) _unlockGallery();
                      },
                      decoration: const InputDecoration(
                        labelText: 'Gallery password',
                        prefixIcon: Icon(Icons.lock_outline, size: 20),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton.icon(
                        onPressed: _unlocking ? null : _unlockGallery,
                        icon: _unlocking
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.lock_open_outlined),
                        label: Text(
                          _unlocking ? 'Unlocking...' : 'Unlock gallery',
                        ),
                      ),
                    ),
                  ],
                  if (_requiresFaceSearch) ...[
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton.icon(
                        onPressed: _faceSearching ? null : _findMyPictures,
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: Text(
                          _faceSearching
                              ? 'Matching...'
                              : 'Take selfie & find me',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _allImages.take(_visibleCount).toList();
    final selectedImages = _allImages
        .where((image) => _selectedIds.contains(image.id))
        .toList();
    final profileSetup = widget.faceEnrollment && _guestToken == null;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 76,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              profileSetup
                  ? 'Face delivery'
                  : (widget.albumTitle ?? 'Event photos'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            Text(
              profileSetup
                  ? 'Set up your personal gallery'
                  : 'Tap photos to select and download',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: AppColors.mutedForeground,
              ),
            ),
          ],
        ),
        actions: [
          if (!_accessBlocked && !profileSetup)
            IconButton(
              tooltip: 'Find my pictures',
              onPressed: _faceSearching ? null : _findMyPictures,
              icon: _faceSearching
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.face_retouching_natural_outlined),
            ),
          if (_showingFaceMatches)
            IconButton(
              tooltip: 'Show all photos',
              onPressed: _faceSearching ? null : _load,
              icon: const Icon(Icons.grid_view_outlined),
            ),
          if (!widget.publicAccess)
            IconButton(
              tooltip: 'Move to album',
              onPressed: _saving ? null : _showAlbumPicker,
              icon: const Icon(Icons.drive_file_move_outline),
            ),
          if (!_accessBlocked && !profileSetup)
            IconButton(
              tooltip: 'Download selected',
              onPressed: _saving ? null : () => _saveImages(selectedImages),
              icon: const Icon(Icons.download_outlined),
            ),
          if (!_accessBlocked && !profileSetup)
            TextButton(
              onPressed: _saving ? null : () => _saveImages(_allImages),
              child: const Text('All'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : profileSetup
          ? _buildGlobalFaceEnrollment()
          : _accessBlocked
          ? _buildAccessGate()
          : _error != null
          ? Center(child: Text(_error!))
          : _allImages.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: AppEmptyState(
                icon: Icons.photo_library_outlined,
                title: 'No photos found',
                message:
                    'Photos appear here as soon as the photographer publishes them.',
              ),
            )
          : GridView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 20),
              itemCount: visible.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 5,
                crossAxisSpacing: 5,
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
                        borderRadius: BorderRadius.circular(9),
                        child: ImageLoader.loadImage(
                          image.imageUrl,
                          fit: BoxFit.cover,
                        ),
                      ),
                      if (selected)
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                              color: AppColors.primary,
                              width: 2,
                            ),
                          ),
                        ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.primary
                                : Colors.black.withValues(alpha: 0.45),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.9),
                              width: 1.5,
                            ),
                          ),
                          child: Icon(
                            selected ? Icons.check : Icons.add,
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
