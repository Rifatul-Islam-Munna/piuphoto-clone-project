import 'package:auto_route/auto_route.dart';
import 'package:mobileapp/core/router/app_router.dart';
import 'package:mobileapp/core/storage/user_storage.dart';
import 'package:mobileapp/core/di/locator.dart';

class AuthGuard extends AutoRouteGuard {
  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) async {
    final token = await UserStorage.getAccessToken();

    logger.i('AuthGuard token: $token');

    if (token != null && token.isNotEmpty) {
      resolver.next(true);
      return;
    }

    resolver.next(false);
    router.root.replaceAll([const LoginRoute()]);
  }
}
