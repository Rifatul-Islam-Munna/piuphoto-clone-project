import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:mobileapp/core/router/app_router.dart';
import 'package:mobileapp/core/storage/user_storage.dart';
import 'package:mobileapp/core/utils/image_loader.dart';
import 'package:mobileapp/core/utils/image_upload_helper.dart';
import 'package:mobileapp/models/user_model.dart';
import 'package:mobileapp/utilities/app_toast.dart';

@RoutePage()
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _whatsappController = TextEditingController();
  bool _editing = false;
  bool _saving = false;
  String? _editingUserKey;
  String? _selectedProfileImagePath;
  String? _selectedProfileImageName;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _whatsappController.dispose();
    super.dispose();
  }

  void _syncControllers(UserModel user) {
    final key = user.stableId;
    if (_editingUserKey == key) return;

    _editingUserKey = key;
    _nameController.text = user.name ?? '';
    _phoneController.text = user.phone ?? '';
    _whatsappController.text = user.whatsapp ?? '';
  }

  Future<void> _pickProfileImage() async {
    try {
      final picked = await ImageUploadHelper.pickFromGallery();
      if (picked == null || !mounted) return;
      setState(() {
        _selectedProfileImagePath = picked.path;
        _selectedProfileImageName = picked.name;
      });
    } catch (_) {
      AppToast.error('Failed to pick profile image');
    }
  }

  Future<void> _save(UserModel user) async {
    setState(() => _saving = true);
    try {
      String? profileImageUrl = user.profileImage?['url']?.toString();
      final selectedPath = _selectedProfileImagePath;
      final selectedName = _selectedProfileImageName;

      if (selectedPath != null && selectedName != null) {
        final uploadedUrl = await ImageUploadHelper.uploadFile(
          path: selectedPath,
          filename: selectedName,
        );
        if (uploadedUrl.isEmpty) {
          throw Exception('Profile image upload returned no URL');
        }
        profileImageUrl = uploadedUrl;
      }

      final response = await DioHelper.dio.patch(
        '/user/update-profile',
        data: {
          'name': _nameController.text.trim(),
          'phone': _phoneController.text.trim(),
          'whatsapp': _whatsappController.text.trim(),
          if (profileImageUrl != null && profileImageUrl.isNotEmpty)
            'profileImage': {'url': profileImageUrl},
        },
      );
      final data = Map<String, dynamic>.from(response.data['data'] as Map);
      await UserStorage.saveUser(UserModel.fromJson(data));
      setState(() {
        _editing = false;
        _selectedProfileImagePath = null;
        _selectedProfileImageName = null;
      });
      AppToast.success('Profile updated');
    } catch (_) {
      AppToast.error('Failed to update profile');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: UserStorage.currentUser,
      builder: (context, user, _) {
        if (user != null) {
          _syncControllers(user);
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Profile'),
            actions: [
              if (user != null)
                IconButton(
                  tooltip: _editing ? 'Cancel edit' : 'Edit profile',
                  onPressed: _saving
                      ? null
                      : () {
                          setState(() {
                            if (_editing) {
                              _editingUserKey = null;
                              _selectedProfileImagePath = null;
                              _selectedProfileImageName = null;
                              _syncControllers(user);
                            }
                            _editing = !_editing;
                          });
                        },
                  icon: Icon(_editing ? Icons.close : Icons.edit_outlined),
                ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: user == null
                ? const Center(child: Text('No user profile loaded.'))
                : ListView(
                    children: [
                      Stack(
                        children: [
                          CircleAvatar(
                            radius: 40,
                            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                            child: ClipOval(
                              child: _selectedProfileImagePath != null
                                  ? Image.file(
                                      File(_selectedProfileImagePath!),
                                      width: 80,
                                      height: 80,
                                      fit: BoxFit.cover,
                                    )
                                  : SizedBox(
                                      width: 80,
                                      height: 80,
                                      child: (user.profileImage?['url']?.toString().isNotEmpty ?? false)
                                          ? ImageLoader.loadImageCircle(
                                              user.profileImage?['url']?.toString(),
                                              size: 80,
                                            )
                                          : Center(child: Text(user.avatarText)),
                                    ),
                            ),
                          ),
                          if (_editing)
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: IconButton.filled(
                                onPressed: _saving ? null : _pickProfileImage,
                                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                                iconSize: 18,
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_editing) ...[
                        if (_selectedProfileImageName != null) ...[
                          Text(
                            _selectedProfileImageName!,
                            style: Theme.of(context).textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                        ],
                        TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Name',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Phone',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _whatsappController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'WhatsApp',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _saving ? null : () => _save(user),
                          icon: const Icon(Icons.save_outlined),
                          label: Text(_saving ? 'Saving...' : 'Save profile'),
                        ),
                      ] else ...[
                        Text(
                          user.displayLabel,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(user.email ?? ''),
                        const SizedBox(height: 24),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Role'),
                          subtitle: Text(user.role ?? '-'),
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Phone'),
                          subtitle: Text(user.phone ?? '-'),
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('WhatsApp'),
                          subtitle: Text(user.whatsapp ?? '-'),
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Credits'),
                          subtitle: Text('${user.credits}'),
                        ),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _saving
                              ? null
                              : () async {
                                  await UserStorage.clear();
                                  if (context.mounted) {
                                    await context.router.root.replaceAll([
                                      const LoginRoute(),
                                    ]);
                                  }
                                },
                          icon: const Icon(Icons.logout),
                          label: const Text('Logout'),
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}
