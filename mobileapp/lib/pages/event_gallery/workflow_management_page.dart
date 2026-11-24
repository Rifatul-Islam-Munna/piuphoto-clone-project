import 'package:flutter/material.dart';
import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:mobileapp/core/theme/app_theme.dart';
import 'package:mobileapp/utilities/app_toast.dart';

class WorkflowManagementPage extends StatefulWidget {
  const WorkflowManagementPage({
    super.key,
    required this.eventId,
    this.albumId,
    required this.eventTitle,
    required this.albumTitle,
    required this.onOpenPhotoManagement,
    required this.onShareAlbum,
  });

  final String eventId;
  final String? albumId;
  final String eventTitle;
  final String albumTitle;
  final VoidCallback onOpenPhotoManagement;
  final VoidCallback onShareAlbum;

  @override
  State<WorkflowManagementPage> createState() => _WorkflowManagementPageState();
}

class _WorkflowManagementPageState extends State<WorkflowManagementPage> {
  bool _loading = true;
  bool _saving = false;
  bool _autoEnhanceImages = false;

  @override
  void initState() {
    super.initState();
    _loadWorkflow();
  }

  Future<void> _loadWorkflow() async {
    try {
      final response = await DioHelper.get(
        '/event/get-one',
        queryParameters: {'id': widget.eventId},
      );
      final raw = response.data['data'];
      final event = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};
      var enabled = event['autoEnhanceImages'] == true;
      if (widget.albumId != null) {
        final response = await DioHelper.get(
          '/album/get-all',
          queryParameters: {'eventId': widget.eventId},
        );
        final matches = (response.data['data'] as List).where(
          (row) =>
              row is Map &&
              (row['_id'] ?? row['id']).toString() == widget.albumId,
        );
        if (matches.isEmpty) throw StateError('Album not found');
        final album = matches.first as Map;
        if (album['autoEnhanceImages'] is bool)
          enabled = album['autoEnhanceImages'] == true;
      }
      if (!mounted) return;
      setState(() {
        _autoEnhanceImages = enabled;
      });
    } catch (_) {
      if (mounted) AppToast.error('Could not load workflow settings');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setAutoEnhance(bool enabled) async {
    if (_saving) return;
    final previous = _autoEnhanceImages;
    setState(() {
      _autoEnhanceImages = enabled;
      _saving = true;
    });
    try {
      await DioHelper.patch(
        widget.albumId == null ? '/event/update' : '/album/update',
        queryParameters: {'id': widget.albumId ?? widget.eventId},
        data: {'autoEnhanceImages': enabled},
      );
      AppToast.success(
        enabled
            ? 'AI image enhancement enabled'
            : 'AI image enhancement disabled',
      );
    } catch (_) {
      if (mounted) setState(() => _autoEnhanceImages = previous);
      AppToast.error('Could not update AI image enhancement');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _openPhotoManagement() {
    Navigator.of(context).pop();
    widget.onOpenPhotoManagement();
  }

  void _shareAlbum() {
    Navigator.of(context).pop();
    widget.onShareAlbum();
  }

  Widget _roleCard({
    required String number,
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget trailing,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.accentSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                number,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 17, color: AppColors.primary),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: AppColors.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: 8),
                  trailing,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Workflow Management',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                Text(
                  widget.albumTitle,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  widget.eventTitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.mutedForeground,
                  ),
                ),
                const SizedBox(height: 18),
                _roleCard(
                  number: '01',
                  icon: Icons.camera_alt_outlined,
                  title: 'Photographer',
                  subtitle:
                      'Capture and upload photos directly into this album. Manual selection and automatic camera transfer stay available from Upload.',
                  trailing: const Text(
                    'Photographer access active',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _roleCard(
                  number: '02',
                  icon: Icons.auto_awesome_outlined,
                  title: 'AI Retoucher',
                  subtitle:
                      'Automatically keep the original photo and add an enhanced copy to this album.',
                  trailing: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: _autoEnhanceImages,
                    onChanged: _saving ? null : _setAutoEnhance,
                    title: const Text(
                      'AI image enhancement',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _roleCard(
                  number: '03',
                  icon: Icons.fact_check_outlined,
                  title: 'Reviewer',
                  subtitle:
                      'Review selected photos, then publish or hide them from the guest gallery.',
                  trailing: OutlinedButton.icon(
                    onPressed: _openPhotoManagement,
                    icon: const Icon(Icons.photo_library_outlined, size: 17),
                    label: const Text('Review photos'),
                  ),
                ),
                const SizedBox(height: 10),
                _roleCard(
                  number: '04',
                  icon: Icons.people_outline_rounded,
                  title: 'Audience',
                  subtitle:
                      'Share the album with guests. Published photos are the ones available in the event gallery.',
                  trailing: OutlinedButton.icon(
                    onPressed: _shareAlbum,
                    icon: const Icon(Icons.share_outlined, size: 17),
                    label: const Text('Share album'),
                  ),
                ),
                if (_saving)
                  const Padding(
                    padding: EdgeInsets.only(top: 14),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
              ],
            ),
    );
  }
}
