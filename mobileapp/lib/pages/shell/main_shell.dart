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
                      const InvitationsRoute(),
                      const ProfileRoute(),
                    ]
                  : [
                      const HomeRoute(),
                      const UploadRoute(),
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
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 2),
        child: Container(
          height: 70,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 26,
                offset: const Offset(0, 10),
              ),
            ],
          ),
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
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? AppColors.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(17),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: selected ? 28 : 24,
                height: 24,
                alignment: Alignment.center,
                child: Icon(iconData, size: selected ? 21 : 20, color: accent),
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: accent,
                  letterSpacing: 0,
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
