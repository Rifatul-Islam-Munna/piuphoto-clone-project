import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:mobileapp/core/platform/otg_file_picker.dart';
import 'package:mobileapp/core/router/app_router.dart';
import 'package:mobileapp/core/storage/active_event_storage.dart';
import 'package:mobileapp/models/event_invitation_model.dart';
import 'package:mobileapp/utilities/app_toast.dart';

@RoutePage()
class UploadPage extends StatefulWidget {
  const UploadPage({super.key});

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  final _picker = ImagePicker();
  final _referenceController = TextEditingController();
  bool _isEnhanced = false;
  bool _uploading = false;
  String? _selectedFilePath;
  String? _selectedFileName;

  @override
  void dispose() {
    _referenceController.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final image = await _picker.pickImage(
      source: source,
      imageQuality: 92,
    );
    if (image == null) return;
    setState(() {
      _selectedFilePath = image.path;
      _selectedFileName = image.name;
    });
  }

  Future<void> _pickOtgFile() async {
    try {
      final file = await OtgFilePicker.pickImage();
      if (file == null) return;
      setState(() {
        _selectedFilePath = file.path;
        _selectedFileName = file.name;
      });
    } on MissingPluginException {
      AppToast.error('Rebuild the app once to enable OTG picker');
    } catch (_) {
      AppToast.error('Failed to open OTG file picker');
    }
  }

  Future<String> _uploadFile({
    required String path,
    required String filename,
  }) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        path,
        filename: filename,
      ),
    });
    final response = await DioHelper.post('/image/upload', data: formData);
    return response.data['url']?.toString() ?? '';
  }

  Future<void> _createEventImage(EventSummary event, String imageUrl) async {
    await DioHelper.post(
      '/eventImage',
      data: {
        'eventId': event.id,
        'imageUrl': imageUrl,
        'referenceId': _referenceController.text.trim().isEmpty
            ? null
            : _referenceController.text.trim(),
        'isEnhanced': _isEnhanced,
      },
    );
  }

  Future<void> _submit(EventSummary event) async {
    final filePath = _selectedFilePath;
    final fileName = _selectedFileName;
    if (filePath == null || fileName == null) {
      AppToast.error('Choose an image first');
      return;
    }

    setState(() => _uploading = true);
    try {
      final imageUrl = await _uploadFile(path: filePath, filename: fileName);
      if (imageUrl.isEmpty) {
        throw Exception('Image upload returned no URL');
      }

      await _createEventImage(event, imageUrl);
      AppToast.success('Image uploaded to ${event.title}');
      setState(() {
        _selectedFilePath = null;
        _selectedFileName = null;
        _referenceController.clear();
        _isEnhanced = false;
      });
    } catch (_) {
      AppToast.error('Failed to upload image');
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: ActiveEventStorage.activeEvent,
      builder: (context, activeEvent, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Upload')),
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (activeEvent == null)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No active event selected. Accept an invitation and make an event active first.',
                    ),
                  ),
                )
              else
                Card(
                  child: ListTile(
                    title: const Text('Active event'),
                    subtitle: Text(activeEvent.title),
                    trailing: IconButton(
                      tooltip: 'Clear active event',
                      onPressed: _uploading ? null : ActiveEventStorage.clear,
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ),
              if (activeEvent != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        context.router.root.push(const EventImagesRoute()),
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('View uploaded images'),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          _uploading ? null : () => _pick(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Phone'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          _uploading ? null : () => _pick(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Camera'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _uploading ? null : _pickOtgFile,
                  icon: const Icon(Icons.usb_outlined),
                  label: const Text('OTG / external file'),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _referenceController,
                enabled: !_uploading,
                decoration: const InputDecoration(
                  labelText: 'OTG camera / reference ID',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enhanced image'),
                value: _isEnhanced,
                onChanged: _uploading
                    ? null
                    : (value) => setState(() => _isEnhanced = value),
              ),
              if (_selectedFilePath != null) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(_selectedFilePath!),
                    height: 220,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: activeEvent == null || _uploading
                      ? null
                      : () => _submit(activeEvent),
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: _uploading
                      ? const Text('Uploading...')
                      : const Text('Upload to active event'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
