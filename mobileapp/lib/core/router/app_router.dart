import 'package:animations/animations.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:mobileapp/core/router/auth_guard.dart';

import 'package:mobileapp/core/theme/app_theme.dart';
import 'package:mobileapp/models/user_model.dart';
import 'package:mobileapp/pages/auth/login_page.dart';
import 'package:mobileapp/pages/auth/register_page.dart';
import 'package:mobileapp/pages/camera/camera_page.dart';
import 'package:mobileapp/pages/event_images/event_images_page.dart';
import 'package:mobileapp/pages/history/history_page.dart';
import 'package:mobileapp/pages/home/home_page.dart';
import 'package:mobileapp/pages/invitations/invitations_page.dart';
import 'package:mobileapp/pages/onboarding/onboarding_page.dart';
import 'package:mobileapp/pages/plans/plans_page.dart';
import 'package:mobileapp/pages/profile/profile_page.dart';
import 'package:mobileapp/pages/shell/main_shell.dart';
import 'package:mobileapp/pages/splash/splash_page.dart';
import 'package:mobileapp/pages/templates/templates_page.dart';
import 'package:mobileapp/pages/upload/upload_page.dart';

part 'app_router.gr.dart';

@AutoRouterConfig(replaceInRouteName: 'Screen|Page,Route')
class AppRouter extends RootStackRouter {
  AppRouter({required this.authGuard});

  final AuthGuard authGuard;

  @override
  RouteType get defaultRouteType => RouteType.custom(
        transitionsBuilder: _smoothPageTransition,
        duration: const Duration(milliseconds: 280),
        reverseDuration: const Duration(milliseconds: 240),
      );

  @override
  List<AutoRoute> get routes => [
        AutoRoute(page: SplashRoute.page, path: '/', initial: true),
        AutoRoute(page: OnboardingRoute.page, path: '/onboarding'),
        AutoRoute(page: LoginRoute.page, path: '/login'),
        AutoRoute(page: RegisterRoute.page, path: '/register'),
        AutoRoute(
          page: ProfileRoute.page,
          path: '/profile',
          guards: [authGuard],
        ),
        AutoRoute(
          page: InvitationsRoute.page,
          path: '/invitations',
          guards: [authGuard],
        ),
        AutoRoute(
          page: EventImagesRoute.page,
          path: '/event-images',
          guards: [authGuard],
        ),
        AutoRoute(page: UploadRoute.page, path: '/upload', guards: [authGuard]),
        AutoRoute(
          page: MainShellRoute.page,
          path: '/main',
          children: [
            RedirectRoute(path: '', redirectTo: 'home'),
            AutoRoute(page: HomeRoute.page, path: 'home'),
            AutoRoute(page: PlansRoute.page, path: 'plans'),
            AutoRoute(
              page: ProfileRoute.page,
              path: 'profile',
              guards: [authGuard],
            ),
            AutoRoute(
              page: UploadRoute.page,
              path: 'upload',
              guards: [authGuard],
            ),
            AutoRoute(
              page: InvitationsRoute.page,
              path: 'invitations',
              guards: [authGuard],
            ),
          ],
        ),
      ];
}

Widget _smoothPageTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  return SharedAxisTransition(
    animation: animation,
    secondaryAnimation: secondaryAnimation,
    transitionType: SharedAxisTransitionType.horizontal,
    fillColor: AppColors.background,
    child: child,
  );
}

Future<void> goHome(BuildContext context) {
  return context.router.root.replaceAll([const MainShellRoute()]);
}

Future<void> popOrHome(BuildContext context) async {
  if (context.router.canPop()) {
    final didPop = await context.router.maybePop();
    if (didPop) return;
  }

  if (context.mounted) {
    await goHome(context);
  }
}

List<BottomNavigationBarItem> buildShellItems(UserModel? user) {
  if (user?.isPhotographer ?? false) {
    return const [
      BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Home'),
      BottomNavigationBarItem(
        icon: Icon(Icons.cloud_upload_outlined),
        label: 'Upload',
      ),
      BottomNavigationBarItem(icon: Icon(Icons.mail_outline), label: 'Invites'),
      BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profile'),
    ];
  }

  return const [
    BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Home'),
    BottomNavigationBarItem(
      icon: Icon(Icons.workspace_premium_outlined),
      label: 'Plans',
    ),
    BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profile'),
  ];
}
