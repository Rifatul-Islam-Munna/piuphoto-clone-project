import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:mobileapp/core/router/app_router.dart';
import 'package:mobileapp/core/storage/user_storage.dart';
import 'package:mobileapp/core/theme/app_theme.dart';

@RoutePage()
class MainShellPage extends StatelessWidget {
  const MainShellPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: UserStorage.currentUser,
      builder: (context, user, _) {
        final isPhotographer = user?.isPhotographer ?? false;
        final hasPlannerAccess = user?.hasPlannerAccess ?? false;

        final routes = isPhotographer
            ? (hasPlannerAccess
                  ? [
                      const HomeRoute(),
                      const EventsRoute(),
                      const UploadRoute(),
                      const PlansRoute(),
                      const InvitationsRoute(),
                      const ProfileRoute(),
                    ]
                  : [
                      const HomeRoute(),
                      const UploadRoute(),
                      const PlansRoute(),
                      const InvitationsRoute(),
                      const ProfileRoute(),
                    ])
            : [
                const HomeRoute(),
                const EventsRoute(),
                const PlansRoute(),
                const ProfileRoute(),
              ];

        return AutoTabsScaffold(
          key: ValueKey(
            '${user?.role ?? 'guest'}-${user?.hasPlannerAccess ?? false}',
          ),
          routes: routes,
          bottomNavigationBuilder: (context, tabsRouter) => _AppBottomNavBar(
            tabsRouter: tabsRouter,
            items: buildShellItems(user),
          ),
        );
      },
    );
  }
}

class _AppBottomNavBar extends StatelessWidget {
  const _AppBottomNavBar({required this.tabsRouter, required this.items});

  final TabsRouter tabsRouter;
  final List<BottomNavigationBarItem> items;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _NavItemTile(
                    iconData: (items[i].icon as Icon).icon ?? Icons.circle,
                    label: items[i].label ?? '',
                    selected: tabsRouter.activeIndex == i,
                    onTap: () => tabsRouter.setActiveIndex(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItemTile extends StatelessWidget {
  const _NavItemTile({
    required this.iconData,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData iconData;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = selected ? AppColors.primary : AppColors.mutedForeground;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: AnimatedScale(
          scale: selected ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(iconData, size: 23, color: accent),
              const SizedBox(height: 5),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: accent,
                  letterSpacing: 0.1,
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
