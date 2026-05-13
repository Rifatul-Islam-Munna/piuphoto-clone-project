import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:mobileapp/core/router/app_router.dart';
import 'package:mobileapp/core/storage/user_storage.dart';

@RoutePage()
class MainShellPage extends StatelessWidget {
  const MainShellPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: UserStorage.currentUser,
      builder: (context, user, _) {
        final isPhotographer = user?.isPhotographer ?? false;
        
        final routes = isPhotographer
            ? [
                const HomeRoute(),
                const UploadRoute(),
                const InvitationsRoute(),
                const ProfileRoute(),
              ]
            : [
                const HomeRoute(),
                const EventsRoute(),
                const PlansRoute(),
                const ProfileRoute(),
              ];

        return AutoTabsScaffold(
          key: ValueKey(user?.role ?? 'guest'),
          routes: routes,
          bottomNavigationBuilder: (context, tabsRouter) => BottomNavigationBar(
            currentIndex: tabsRouter.activeIndex,
            onTap: tabsRouter.setActiveIndex,
            items: buildShellItems(user),
          ),
        );
      },
    );
  }
}
