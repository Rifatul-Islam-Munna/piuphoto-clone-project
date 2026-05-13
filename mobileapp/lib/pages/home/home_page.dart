import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:mobileapp/core/router/app_router.dart';
import 'package:mobileapp/core/storage/active_event_storage.dart';
import 'package:mobileapp/core/storage/user_storage.dart';
import 'package:mobileapp/pages/event_gallery/event_qr_scan_page.dart';
import 'package:mobileapp/utilities/app_toast.dart';
import 'package:url_launcher/url_launcher.dart';

@RoutePage()
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  Future<List<Map<String, dynamic>>> _loadPlans() async {
    final response = await DioHelper.get(
      '/subscription-plan/get-all?limit=100&isActive=true',
    );
    final data = response.data['data'] as List? ?? [];
    return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> _loadAddons() async {
    final response = await DioHelper.get(
      '/addon/get-all?limit=100&isActive=true',
    );
    final data = response.data['data'] as List? ?? [];
    return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<void> _openCheckout({
    required BuildContext context,
    required String endpoint,
    required Map<String, dynamic> data,
  }) async {
    try {
      final response = await DioHelper.post(endpoint, data: data);
      final url = response.data['url']?.toString();
      if (url == null || url.isEmpty) {
        throw Exception('Checkout URL missing');
      }

      final launched = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw Exception('Unable to open checkout');
      }
    } catch (_) {
      AppToast.error('Failed to open checkout');
    }
  }

  Widget _PhotographerHome(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: ActiveEventStorage.activeEvent,
      builder: (context, activeEvent, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Photographer home',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.camera_alt_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Ready for a shoot',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Pick an event, start camera auto-upload, then shoot normally. New photos that land on this phone are uploaded to the active event.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.event_available_outlined),
                title: const Text('Active event'),
                subtitle: Text(activeEvent?.title ?? 'No event selected'),
                trailing: FilledButton(
                  onPressed: () => context.router.root.push(
                    const InvitationsRoute(),
                  ),
                  child: const Text('Events'),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: activeEvent == null
                        ? null
                        : () => context.router.root.push(const UploadRoute()),
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: const Text('Upload'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: activeEvent == null
                        ? null
                        : () => context.router.root.push(
                              const EventImagesRoute(),
                            ),
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('Uploads'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Quick flow',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _miniStep(
                    context,
                    icon: Icons.event_outlined,
                    title: 'Event',
                    value: activeEvent == null ? 'Select' : 'Active',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _miniStep(
                    context,
                    icon: Icons.autorenew,
                    title: 'Auto',
                    value: 'Upload',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _miniStep(
                    context,
                    icon: Icons.cleaning_services_outlined,
                    title: 'Free',
                    value: 'Space',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Upload methods',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            _tipCard(
              icon: Icons.autorenew,
              title: 'Auto upload from camera',
              body: [
                '1. Select an active event.',
                '2. Connect the camera using its normal Wi-Fi/app transfer.',
                '3. Open Upload and turn on Auto upload from camera.',
                '4. Take photos. When they arrive on the phone, the app uploads them to the active event.',
                '5. Tap Free space later to remove uploaded phone copies.',
              ].join('\n'),
            ),
            _tipCard(
              icon: Icons.cleaning_services_outlined,
              title: 'Free space',
              body:
                  'After auto-upload, tap Free space to remove only the phone photos that were already uploaded by this app.',
            ),
            _tipCard(
              icon: Icons.usb_outlined,
              title: 'OTG / external file',
              body:
                  'Use this when camera files are available through USB storage, card reader, or the phone file picker.',
            ),
            _tipCard(
              icon: Icons.photo_library_outlined,
              title: 'Phone upload',
              body:
                  'Pick existing images manually from the phone when auto-upload is not needed.',
            ),
          ],
        );
      },
    );
  }

  Widget _tipCard({
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(body),
      ),
    );
  }

  Widget _miniStep(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Column(
          children: [
            Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: UserStorage.currentUser,
      builder: (context, user, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Home')),
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: ListView(
              children: [
                if (user?.isPhotographer ?? false) ...[
                  _PhotographerHome(context),
                  const SizedBox(height: 24),
                ] else ...[
                  Text(
                    user == null ? 'Welcome to PiuPhoto' : 'User home',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (user?.isUser ?? false)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.qr_code_scanner),
                      title: const Text('Scan QR Code'),
                      subtitle: const Text('Open event photos'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const EventQrScanPage(),
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 16),
                if (user == null) ...[
                  const Text(
                    'Login or signup, or browse plans and addons below.',
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => context.router.root.push(
                            const LoginRoute(),
                          ),
                          child: const Text('Login'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => context.router.root.push(
                            const RegisterRoute(),
                          ),
                          child: const Text('Sign Up'),
                        ),
                      ),
                    ],
                  ),
                ] else if (!(user.isPhotographer)) ...[
                  Text(user.displayLabel),
                  const SizedBox(height: 8),
                  Text('Role: ${user.role ?? '-'}'),
                  const SizedBox(height: 8),
                  Text('Credits: ${user.credits}'),
                ],
                if (!(user?.isPhotographer ?? false)) ...[
                  const SizedBox(height: 24),
                  const Text(
                    'Plans',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: _loadPlans(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (snapshot.hasError) {
                        return Text('Failed to load plans: ${snapshot.error}');
                      }

                      final plans = snapshot.data ?? [];
                      return Column(
                        children: plans
                            .map(
                              (plan) => Card(
                                child: ListTile(
                                  title:
                                      Text(plan['title']?.toString() ?? '-'),
                                  subtitle: Text(
                                    '${plan['currency'] ?? 'USD'} ${plan['discount_price'] ?? plan['price'] ?? 0}',
                                  ),
                                  trailing: user?.isUser ?? false
                                      ? FilledButton(
                                          onPressed: () => _openCheckout(
                                            context: context,
                                            endpoint:
                                                '/subscription-plan/create-checkout-session',
                                            data: {'id': plan['_id']},
                                          ),
                                          child: const Text('Buy'),
                                        )
                                      : null,
                                ),
                              ),
                            )
                            .toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Addons',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: _loadAddons(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (snapshot.hasError) {
                        return Text('Failed to load addons: ${snapshot.error}');
                      }

                      final addons = snapshot.data ?? [];
                      return Column(
                        children: addons
                            .map(
                              (addon) => Card(
                                child: ListTile(
                                  title:
                                      Text(addon['title']?.toString() ?? '-'),
                                  subtitle: Text(
                                    '${addon['credit'] ?? 0} credits - ${addon['currency'] ?? 'USD'} ${addon['price'] ?? 0}',
                                  ),
                                  trailing: user?.isUser ?? false
                                      ? FilledButton(
                                          onPressed: () => _openCheckout(
                                            context: context,
                                            endpoint:
                                                '/addon/create-checkout-session',
                                            data: {'addonId': addon['_id']},
                                          ),
                                          child: const Text('Buy'),
                                        )
                                      : null,
                                ),
                              ),
                            )
                            .toList(),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
