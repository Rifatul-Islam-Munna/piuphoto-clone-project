import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:mobileapp/core/router/app_router.dart';
import 'package:mobileapp/core/storage/user_storage.dart';

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
                Text(
                  user == null
                      ? 'Welcome to PiuPhoto'
                      : user.isPhotographer
                          ? 'Photographer home'
                          : 'User home',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
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
                ] else ...[
                  Text(user.displayLabel),
                  const SizedBox(height: 8),
                  Text('Role: ${user.role ?? '-'}'),
                  const SizedBox(height: 8),
                  Text('Credits: ${user.credits}'),
                ],
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
                                title: Text(plan['title']?.toString() ?? '-'),
                                subtitle: Text(
                                  '${plan['currency'] ?? 'USD'} ${plan['discount_price'] ?? plan['price'] ?? 0}',
                                ),
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
                                title: Text(addon['title']?.toString() ?? '-'),
                                subtitle: Text(
                                  '${addon['credit'] ?? 0} credits - ${addon['currency'] ?? 'USD'} ${addon['price'] ?? 0}',
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
