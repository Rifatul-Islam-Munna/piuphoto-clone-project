import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:mobileapp/core/router/app_router.dart';
import 'package:mobileapp/core/storage/user_storage.dart';

@RoutePage()
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final seenOnboarding = await UserStorage.hasSeenOnboarding();
    final token = await UserStorage.getAccessToken();

    if (!mounted) return;

    if (!seenOnboarding) {
      context.router.replace(const OnboardingRoute());
      return;
    }

    if (token != null && token.isNotEmpty) {
      await goHome(context);
      return;
    }

    await goHome(context);
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
