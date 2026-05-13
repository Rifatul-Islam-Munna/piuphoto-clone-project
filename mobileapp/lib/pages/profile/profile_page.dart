import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:mobileapp/core/storage/user_storage.dart';

@RoutePage()
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: UserStorage.currentUser,
      builder: (context, user, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Profile')),
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: user == null
                ? const Center(child: Text('No user profile loaded.'))
                : ListView(
                    children: [
                      CircleAvatar(
                        radius: 32,
                        child: Text(user.avatarText),
                      ),
                      const SizedBox(height: 16),
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
                        title: const Text('User ID'),
                        subtitle: Text(user.userId ?? user.stableId),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Phone'),
                        subtitle: Text(user.phone ?? '-'),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Credits'),
                        subtitle: Text('${user.credits}'),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}
