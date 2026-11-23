import 'package:flutter/material.dart';
import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:mobileapp/core/utils/image_upload_helper.dart';
import 'package:mobileapp/core/theme/app_theme.dart';
import 'package:mobileapp/core/utils/image_loader.dart';
import 'package:mobileapp/utilities/app_toast.dart';

class AlbumBrandingSettingsPage extends StatefulWidget {
  const AlbumBrandingSettingsPage({
    super.key,
    required this.eventId,
    required this.eventTitle,
  });
  final String eventId;
  final String eventTitle;
  @override
  State<AlbumBrandingSettingsPage> createState() =>
      _AlbumBrandingSettingsPageState();
}

class _AlbumBrandingSettingsPageState extends State<AlbumBrandingSettingsPage> {
  Map<String, dynamic> _branding = {};
  String _watermarkPosition = 'bottom_right';
  double _watermarkOpacity = .7;
  double _watermarkScale = 24;
  bool _loading = true,
      _saving = false,
      _uploadingCover = false,
      _uploadingWatermark = false;

  @override
  void initState() {
    super.initState();
    _load();
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
      final branding = data['branding'];
      if (!mounted) return;
      setState(() {
        _branding = branding is Map
            ? Map<String, dynamic>.from(branding)
            : <String, dynamic>{};
        _watermarkPosition =
            _branding['watermarkPosition']?.toString() ?? 'bottom_right';
        _watermarkOpacity =
            (_branding['watermarkOpacity'] as num?)?.toDouble() ?? .7;
        _watermarkScale =
            (_branding['watermarkScale'] as num?)?.toDouble() ?? 24;
      });
    } catch (_) {
      if (mounted) AppToast.error('Could not load album branding settings');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickImage({
    required String key,
    required bool watermark,
  }) async {
    if (watermark ? _uploadingWatermark : _uploadingCover) return;
    setState(() {
      if (watermark) {
        _uploadingWatermark = true;
      } else {
        _uploadingCover = true;
      }
    });
    try {
      final picked = await ImageUploadHelper.pickFromGallery();
      if (picked == null) return;
      final url = await ImageUploadHelper.uploadFile(
        path: picked.path,
        filename: picked.name,
      );
      if (!mounted) return;
      setState(() => _branding = {..._branding, key: url});
      AppToast.success(watermark ? 'Watermark uploaded' : 'Banner uploaded');
    } catch (_) {
      if (mounted) AppToast.error('Could not upload image');
    } finally {
      if (mounted) {
        setState(() {
          if (watermark) {
            _uploadingWatermark = false;
          } else {
            _uploadingCover = false;
          }
        });
      }
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await DioHelper.patch(
        '/gallery-access/settings',
        data: {
          'eventId': widget.eventId,
          'branding': {
            ..._branding,
            'watermarkPosition': _watermarkPosition,
            'watermarkOpacity': _watermarkOpacity,
            'watermarkScale': _watermarkScale,
          },
        },
      );
      if (mounted) AppToast.success('Branding settings saved');
    } catch (_) {
      if (mounted) AppToast.error('Could not save branding settings');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(left: 2, top: 18, bottom: 8),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: .35,
        color: AppColors.mutedForeground,
      ),
    ),
  );

  Widget _imageSetting({
    required String title,
    required String subtitle,
    required String key,
    required bool watermark,
  }) {
    final url = _branding[key]?.toString() ?? '';
    final busy = watermark ? _uploadingWatermark : _uploadingCover;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.mutedForeground,
            ),
          ),
          if (url.isNotEmpty) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: watermark ? 90 : 130,
                width: double.infinity,
                child: ImageLoader.loadImage(url, fit: BoxFit.contain),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => _pickImage(key: key, watermark: watermark),
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_outlined),
                  label: Text(url.isEmpty ? 'Upload image' : 'Replace image'),
                ),
              ),
              if (url.isNotEmpty) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Remove image',
                  onPressed: _saving
                      ? null
                      : () => setState(() => _branding.remove(key)),
                  icon: const Icon(
                    Icons.delete_outline,
                    color: AppColors.destructive,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Branding settings',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
      actions: [
        TextButton(
          onPressed: _saving || _loading ? null : _save,
          child: const Text('Save'),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            children: [
              Text(
                widget.eventTitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.mutedForeground,
                ),
              ),
              _section('GALLERY BRANDING'),
              _imageSetting(
                title: 'Banner',
                subtitle: 'Cover image shown at the top of the public gallery.',
                key: 'coverUrl',
                watermark: false,
              ),
              _section('PHOTO WATERMARK'),
              _imageSetting(
                title: 'Photo Watermark',
                subtitle: 'Add your logo or watermark to store preview images.',
                key: 'watermarkUrl',
                watermark: true,
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _watermarkPosition,
                      decoration: const InputDecoration(
                        labelText: 'Watermark position',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'top_left',
                          child: Text('Top left'),
                        ),
                        DropdownMenuItem(
                          value: 'top_center',
                          child: Text('Top center'),
                        ),
                        DropdownMenuItem(
                          value: 'top_right',
                          child: Text('Top right'),
                        ),
                        DropdownMenuItem(
                          value: 'center',
                          child: Text('Center'),
                        ),
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
                      onChanged: (value) => setState(
                        () => _watermarkPosition = value ?? 'bottom_right',
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text('Opacity ${(_watermarkOpacity * 100).round()}%'),
                    Slider(
                      value: _watermarkOpacity.clamp(.05, 1),
                      min: .05,
                      max: 1,
                      divisions: 19,
                      onChanged: (value) =>
                          setState(() => _watermarkOpacity = value),
                    ),
                    Text('Size ${_watermarkScale.round()}%'),
                    Slider(
                      value: _watermarkScale.clamp(5, 100),
                      min: 5,
                      max: 100,
                      divisions: 19,
                      onChanged: (value) =>
                          setState(() => _watermarkScale = value),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save branding settings'),
                ),
              ),
            ],
          ),
  );
}
