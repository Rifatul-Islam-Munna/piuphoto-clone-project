import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:mobileapp/core/router/app_router.dart';
import 'package:mobileapp/core/storage/user_storage.dart';
import 'package:mobileapp/core/theme/app_theme.dart';
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

  void _toggleEditing(UserModel user) {
    if (_saving) return;
    setState(() {
      if (_editing) {
        _editingUserKey = null;
        _selectedProfileImagePath = null;
        _selectedProfileImageName = null;
        _syncControllers(user);
      }
      _editing = !_editing;
    });
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
    if (_saving) return;
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
      if (!mounted) return;
      setState(() {
        _editing = false;
        _selectedProfileImagePath = null;
        _selectedProfileImageName = null;
      });
      AppToast.success('Profile updated');
    } catch (_) {
      AppToast.error('Failed to update profile');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _logout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'You will need to sign in again to manage events and uploads.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (shouldLogout != true) return;

    await UserStorage.clear();
    if (mounted) {
      await context.router.root.replaceAll([const LoginRoute()]);
    }
  }

  String _roleLabel(UserModel user) {
    final role = user.role?.trim().replaceAll('_', ' ') ?? 'Member';
    if (role.isEmpty) return 'Member';
    return role
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  String _planLabel(UserModel user) {
    final plan = user.subscriptionPlan;
    if (plan is Map) {
      final title = plan['title'] ?? plan['name'];
      if (title != null && title.toString().trim().isNotEmpty) {
        return title.toString().trim();
      }
    }
    if (plan is String && plan.trim().isNotEmpty) return plan.trim();
    return user.isSubscriber == true ? 'Active plan' : 'Free plan';
  }

  Widget _avatar(UserModel user, {double size = 92}) {
    final profileUrl = user.profileImage?['url']?.toString();
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipOval(
        child: _selectedProfileImagePath != null
            ? Image.file(
                File(_selectedProfileImagePath!),
                width: size,
                height: size,
                fit: BoxFit.cover,
              )
            : (profileUrl?.isNotEmpty ?? false)
            ? ImageLoader.loadImageCircle(profileUrl, size: size)
            : ColoredBox(
                color: AppColors.cream,
                child: Center(
                  child: Text(
                    user.avatarText,
                    style: TextStyle(
                      color: AppColors.primaryDark,
                      fontSize: size * 0.34,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UserModel?>(
      valueListenable: UserStorage.currentUser,
      builder: (context, user, _) {
        if (user != null) _syncControllers(user);

        return Scaffold(
          appBar: AppBar(
            toolbarHeight: 82,
            title: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Profile'),
                SizedBox(height: 3),
                Text(
                  'Account, contact and workspace',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.mutedForeground,
                  ),
                ),
              ],
            ),
            actions: [
              if (user != null)
                TextButton.icon(
                  onPressed: _saving ? null : () => _toggleEditing(user),
                  icon: Icon(
                    _editing ? Icons.close_rounded : Icons.edit_outlined,
                    color: AppColors.primary,
                    size: 18,
                  ),
                  label: Text(_editing ? 'Cancel' : 'Edit'),
                ),
              const SizedBox(width: 8),
            ],
          ),
          body: user == null
              ? const Center(child: Text('No user profile loaded.'))
              : RefreshIndicator(
                  onRefresh: () async {
                    // UserStorage updates this screen whenever fresh account data
                    // is saved elsewhere in the app.
                    await Future<void>.delayed(
                      const Duration(milliseconds: 350),
                    );
                  },
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                    children: [
                      _ProfileHero(
                        user: user,
                        avatar: _avatar(user),
                        roleLabel: _roleLabel(user),
                        editing: _editing,
                        saving: _saving,
                        onPhotoTap: _pickProfileImage,
                      ),
                      const SizedBox(height: 14),
                      if (_editing)
                        _buildEditor(user)
                      else ...[
                        _buildAccountSummary(user),
                        const SizedBox(height: 14),
                        _buildContactCard(user),
                        const SizedBox(height: 14),
                        _buildPlanCard(user),
                      ],
                      const SizedBox(height: 18),
                      if (!_editing)
                        OutlinedButton.icon(
                          onPressed: () => _toggleEditing(user),
                          icon: const Icon(Icons.manage_accounts_outlined),
                          label: const Text('Edit profile information'),
                        ),
                      if (!_editing) const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _saving ? null : _logout,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.destructive,
                          side: const BorderSide(color: AppColors.destructive),
                        ),
                        icon: const Icon(Icons.logout),
                        label: const Text('Log out'),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  Widget _buildEditor(UserModel user) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Personal information',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Keep your contact details current for event communication.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_selectedProfileImageName != null) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(
                    Icons.image_outlined,
                    size: 18,
                    color: AppColors.mutedForeground,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedProfileImageName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Full name',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _whatsappController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'WhatsApp',
                prefixIcon: Icon(Icons.chat_outlined),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : () => _save(user),
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(_saving ? 'Saving changes...' : 'Save changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountSummary(UserModel user) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: _SummaryItem(
                icon: Icons.auto_awesome_outlined,
                value: '${user.credits}',
                label: 'Credits',
              ),
            ),
            const SizedBox(height: 44, child: VerticalDivider(width: 1)),
            Expanded(
              child: _SummaryItem(
                icon: user.isActive == false
                    ? Icons.pause_circle_outline
                    : Icons.verified_user_outlined,
                value: user.isActive == false ? 'Paused' : 'Active',
                label: 'Account',
              ),
            ),
            const SizedBox(height: 44, child: VerticalDivider(width: 1)),
            Expanded(
              child: _SummaryItem(
                icon: user.isEmailVerified == true
                    ? Icons.mark_email_read_outlined
                    : Icons.mail_outline,
                value: user.isEmailVerified == true ? 'Verified' : 'Pending',
                label: 'Email',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactCard(UserModel user) {
    return _SectionCard(
      title: 'Contact details',
      icon: Icons.contact_phone_outlined,
      children: [
        _InfoRow(
          icon: Icons.email_outlined,
          label: 'Email',
          value: user.email ?? 'Not added',
        ),
        const Divider(),
        _InfoRow(
          icon: Icons.phone_outlined,
          label: 'Phone',
          value: user.phone?.trim().isNotEmpty == true
              ? user.phone!
              : 'Not added',
        ),
        const Divider(),
        _InfoRow(
          icon: Icons.chat_bubble_outline,
          label: 'WhatsApp',
          value: user.whatsapp?.trim().isNotEmpty == true
              ? user.whatsapp!
              : 'Not added',
        ),
      ],
    );
  }

  Widget _buildPlanCard(UserModel user) {
    return _SectionCard(
      title: 'Workspace',
      icon: Icons.workspace_premium_outlined,
      children: [
        _InfoRow(
          icon: Icons.badge_outlined,
          label: 'Role',
          value: _roleLabel(user),
        ),
        const Divider(),
        _InfoRow(
          icon: Icons.card_membership_outlined,
          label: 'Plan',
          value: _planLabel(user),
        ),
        if (user.subscriptionEndDate?.isNotEmpty == true) ...[
          const Divider(),
          _InfoRow(
            icon: Icons.event_available_outlined,
            label: 'Plan valid until',
            value: user.subscriptionEndDate!,
          ),
        ],
      ],
    );
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.user,
    required this.avatar,
    required this.roleLabel,
    required this.editing,
    required this.saving,
    required this.onPhotoTap,
  });

  final UserModel user;
  final Widget avatar;
  final String roleLabel;
  final bool editing;
  final bool saving;
  final VoidCallback onPhotoTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: AppGradients.studio,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -34,
            top: -50,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            left: 70,
            bottom: -66,
            child: Container(
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    avatar,
                    if (editing)
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: IconButton.filled(
                          tooltip: 'Change profile photo',
                          onPressed: saving ? null : onPhotoTap,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppColors.primary,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.9),
                              width: 2,
                            ),
                          ),
                          icon: const Icon(
                            Icons.photo_camera_outlined,
                            size: 19,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.displayLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 23,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        user.email ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.82),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.17),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.28),
                          ),
                        ),
                        child: Text(
                          roleLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 8),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.cream,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.mutedForeground),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: AppColors.mutedForeground),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: AppColors.primary, size: 21),
        const SizedBox(height: 7),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
        const SizedBox(height: 2),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
