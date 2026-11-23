import 'package:flutter/material.dart';
import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:mobileapp/core/theme/app_theme.dart';
import 'package:mobileapp/pages/event_gallery/album_branding_settings_page.dart';
import 'package:mobileapp/pages/event_gallery/event_auto_enhance_toggle.dart';
import 'package:mobileapp/pages/event_gallery/upload_settings_page.dart';
import 'package:mobileapp/pages/events/events_page.dart';
import 'package:mobileapp/utilities/app_toast.dart';

class AlbumSettingsPage extends StatelessWidget {
  const AlbumSettingsPage({
    super.key,
    required this.albumId,
    required this.eventId,
    required this.eventTitle,
    required this.albumTitle,
    required this.albumDescription,
    required this.onOpenWorkflow,
  });

  final String? albumId;
  final String eventId;
  final String eventTitle;
  final String albumTitle;
  final String albumDescription;
  final VoidCallback onOpenWorkflow;

  Future<void> _openBasicInfo(BuildContext context) async {
    final updated = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute(
        builder: (_) => AlbumBasicInfoPage(
          albumId: albumId,
          eventId: eventId,
          albumTitle: albumTitle,
          albumDescription: albumDescription,
        ),
      ),
    );
    if (updated != null && context.mounted) {
      Navigator.of(context).pop(updated);
    }
  }

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(left: 2, bottom: 8, top: 14),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppColors.mutedForeground,
      ),
    ),
  );

  Widget _tile({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? value,
    required VoidCallback onTap,
  }) => Material(
    color: AppColors.card,
    child: ListTile(
      dense: true,
      minLeadingWidth: 24,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: Icon(icon, color: iconColor, size: 21),
      title: Text(title, style: const TextStyle(fontSize: 13)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null)
            Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.mutedForeground,
              ),
            ),
          const SizedBox(width: 5),
          const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.mutedForeground,
          ),
        ],
      ),
      onTap: onTap,
    ),
  );

  Widget _group(List<Widget> tiles) => ClipRRect(
    borderRadius: BorderRadius.circular(13),
    child: Column(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const Divider(height: 1, indent: 48),
          tiles[i],
        ],
      ],
    ),
  );

  void _openPrivacy(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            EventGalleryPrivacyPage(eventId: eventId, eventTitle: eventTitle),
      ),
    );
  }

  void _openBranding(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            AlbumBrandingSettingsPage(eventId: eventId, eventTitle: eventTitle),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 28),
        children: [
          _sectionTitle('Basic settings'),
          _group([
            _tile(
              icon: Icons.dashboard_rounded,
              iconColor: const Color(0xFFE7A82F),
              title: 'Basic info',
              onTap: () => _openBasicInfo(context),
            ),
            _tile(
              icon: Icons.lock_outline_rounded,
              iconColor: const Color(0xFFE7A82F),
              title: 'Album & Photo Privacy',
              value: 'Manage',
              onTap: () => _openPrivacy(context),
            ),
          ]),
          _sectionTitle('People'),
          _group([
            _tile(
              icon: Icons.group_add_outlined,
              iconColor: AppColors.primary,
              title: 'Invite photographers',
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => EventPhotographerInvitesPage(
                    eventId: eventId,
                    eventTitle: eventTitle,
                  ),
                ),
              ),
            ),
          ]),
          _sectionTitle('Branding settings'),
          _group([
            _tile(
              icon: Icons.image_outlined,
              iconColor: const Color(0xFF4B9DEB),
              title: 'Banner',
              onTap: () => _openBranding(context),
            ),
            _tile(
              icon: Icons.branding_watermark_outlined,
              iconColor: const Color(0xFF55A8E8),
              title: 'Photo Watermark',
              onTap: () => _openBranding(context),
            ),
          ]),
          _sectionTitle('Store'),
          _group([
            _tile(
              icon: Icons.storefront_outlined,
              iconColor: const Color(0xFF4B9DEB),
              title: 'Store settings',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EventStoreSettingsPage(
                    eventId: eventId,
                    eventTitle: eventTitle,
                  ),
                ),
              ),
            ),
          ]),
          _sectionTitle('Workflow & upload'),
          _group([
            // Same event-backed switch used on the live transfer screen.
            // There is no separate per-upload enhancement setting.
            EventAutoEnhanceToggle(eventId: eventId),
            _tile(
              icon: Icons.hub_outlined,
              iconColor: AppColors.primary,
              title: 'Workflow Management',
              onTap: onOpenWorkflow,
            ),
            _tile(
              icon: Icons.cloud_upload_outlined,
              iconColor: AppColors.primary,
              title: 'Upload settings',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const UploadSettingsPage()),
                );
              },
            ),
          ]),
        ],
      ),
    );
  }
}

class AlbumBasicInfoPage extends StatefulWidget {
  const AlbumBasicInfoPage({
    super.key,
    required this.albumId,
    required this.eventId,
    required this.albumTitle,
    required this.albumDescription,
  });

  final String? albumId;
  final String eventId;
  final String albumTitle;
  final String albumDescription;

  @override
  State<AlbumBasicInfoPage> createState() => _AlbumBasicInfoPageState();
}

class _AlbumBasicInfoPageState extends State<AlbumBasicInfoPage> {
  late final TextEditingController _titleController = TextEditingController(
    text: widget.albumTitle,
  );
  late final TextEditingController _descriptionController =
      TextEditingController(text: widget.albumDescription);
  bool _saving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    if (title.isEmpty) {
      AppToast.error('Album name is required');
      return;
    }
    if (_saving) return;

    setState(() => _saving = true);
    try {
      if (widget.albumId != null) {
        await DioHelper.patch(
          '/album/update',
          queryParameters: {'id': widget.albumId},
          data: {'title': title, 'description': description},
        );
      } else {
        await DioHelper.patch(
          '/event/update',
          queryParameters: {'id': widget.eventId},
          data: {'title': title, 'description': description},
        );
      }
      if (!mounted) return;
      AppToast.success('Album information saved');
      Navigator.of(context).pop({'title': title, 'description': description});
    } catch (_) {
      AppToast.error('Could not save album information');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Basic info',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        children: [
          const Text(
            'Album Info',
            style: TextStyle(fontSize: 12, color: AppColors.mutedForeground),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                TextField(
                  controller: _titleController,
                  maxLength: 120,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    border: InputBorder.none,
                  ),
                ),
                const Divider(height: 1),
                TextField(
                  controller: _descriptionController,
                  maxLength: 600,
                  minLines: 3,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    hintText: 'Enter album description',
                    border: InputBorder.none,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save changes'),
            ),
          ),
        ],
      ),
    );
  }
}
