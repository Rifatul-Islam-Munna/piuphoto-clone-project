import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart' hide Card;
import 'package:mobileapp/core/constants/feature_mapping.dart';
import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:mobileapp/core/router/app_router.dart';
import 'package:mobileapp/core/storage/active_event_storage.dart';
import 'package:mobileapp/core/storage/user_storage.dart';
import 'package:mobileapp/core/theme/app_theme.dart';
import 'package:mobileapp/models/event_invitation_model.dart';
import 'package:mobileapp/models/user_model.dart';
import 'package:mobileapp/pages/event_gallery/event_qr_scan_page.dart';
import 'package:mobileapp/utilities/app_toast.dart';
import 'package:mobileapp/widgets/app_ui.dart';

@RoutePage()
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  bool _isRefreshingProfile = false;
  bool _resolvingSoloWorkspace = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshProfileSilently();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshProfileSilently();
    }
  }

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

  Future<void> _openMobilePaymentSheet({
    required BuildContext context,
    required String endpoint,
    required String verifyEndpoint,
    required Map<String, dynamic> data,
  }) async {
    final user = UserStorage.currentUser.value;
    if (user == null) {
      context.router.root.push(const LoginRoute());
      return;
    }

    try {
      final response = await DioHelper.post(endpoint, data: data);
      final paymentData = Map<String, dynamic>.from(
        response.data['data'] as Map? ?? {},
      );
      final publishableKey = paymentData['publishableKey']?.toString();
      final clientSecret = paymentData['paymentIntentClientSecret']?.toString();
      final paymentIntentId = paymentData['paymentIntentId']?.toString();

      if (publishableKey == null ||
          publishableKey.isEmpty ||
          clientSecret == null ||
          clientSecret.isEmpty ||
          paymentIntentId == null ||
          paymentIntentId.isEmpty) {
        throw Exception('Mobile payment data missing');
      }

      Stripe.publishableKey = publishableKey;
      await Stripe.instance.applySettings();
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'Airpix',
          style: ThemeMode.light,
        ),
      );

      await Stripe.instance.presentPaymentSheet();
      await DioHelper.get(
        verifyEndpoint,
        queryParameters: {'paymentIntentId': paymentIntentId},
      );
      try {
        await _refreshCurrentUser();
        await _ensureSoloPhotographerWorkspace();
      } catch (_) {}
      AppToast.success('Payment successful');
    } on StripeException catch (e) {
      AppToast.error(e.error.localizedMessage ?? 'Payment cancelled');
    } catch (_) {
      AppToast.error('Payment failed');
    }
  }

  Future<void> _refreshCurrentUser() async {
    final accessToken = await UserStorage.getAccessToken();
    if (accessToken == null || accessToken.isEmpty) return;

    final response = await DioHelper.get('/user/get-my-profile');
    final rawUser = response.data['data'] ?? response.data;
    if (rawUser is Map) {
      await UserStorage.saveUser(
        UserModel.fromJson(Map<String, dynamic>.from(rawUser)),
      );
    }
  }

  Future<void> _ensureSoloPhotographerWorkspace() async {
    if (_resolvingSoloWorkspace ||
        ActiveEventStorage.activeEvent.value != null) {
      return;
    }
    final user = UserStorage.currentUser.value;
    if (!(user?.isPhotographer ?? false) ||
        !(user?.hasPlannerAccess ?? false)) {
      return;
    }

    _resolvingSoloWorkspace = true;
    try {
      final response = await DioHelper.get(
        '/event/my-events',
        queryParameters: {'workspace': 'planner', 'page': 1, 'limit': 1},
      );
      final rows = response.data is Map ? response.data['data'] : null;
      Map<String, dynamic>? rawEvent;
      if (rows is List && rows.isNotEmpty && rows.first is Map) {
        rawEvent = Map<String, dynamic>.from(rows.first as Map);
      }

      if (rawEvent == null) {
        final created = await DioHelper.post(
          '/event',
          data: {
            'title': 'Solo Workspace',
            'description': 'My photographer delivery workspace',
            'isPublished': true,
          },
        );
        final raw = created.data is Map ? created.data['data'] : null;
        if (raw is Map) rawEvent = Map<String, dynamic>.from(raw);
      }

      if (rawEvent != null) {
        final event = EventSummary.fromJson(rawEvent);
        if (event.id.isNotEmpty) {
          await ActiveEventStorage.saveActiveEvent(event);
        }
      }
    } catch (_) {
      // The Events screen remains available for manual selection if needed.
    } finally {
      _resolvingSoloWorkspace = false;
    }
  }

  Future<void> _refreshProfileSilently() async {
    if (_isRefreshingProfile) return;

    setState(() => _isRefreshingProfile = true);
    try {
      await _refreshCurrentUser();
      await _ensureSoloPhotographerWorkspace();
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _isRefreshingProfile = false);
      }
    }
  }

  Future<void> _refreshProfileWithFeedback() async {
    if (_isRefreshingProfile) return;

    setState(() => _isRefreshingProfile = true);
    try {
      await _refreshCurrentUser();
      await _ensureSoloPhotographerWorkspace();
    } catch (_) {
      AppToast.error('Failed to refresh account');
    } finally {
      if (mounted) {
        setState(() => _isRefreshingProfile = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: UserStorage.currentUser,
      builder: (context, user, _) {
        final isPhotographer = user?.isPhotographer ?? false;
        return Scaffold(
          body: RefreshIndicator(
            onRefresh: _refreshProfileWithFeedback,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                _buildAppBar(context, user, isPhotographer),
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      if (_isRefreshingProfile)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: LinearProgressIndicator(),
                        ),
                      isPhotographer
                          ? _buildPhotographerHome(context)
                          : _buildUserHome(context, user),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  SliverAppBar _buildAppBar(
    BuildContext context,
    dynamic user,
    bool isPhotographer,
  ) {
    final isLoggedIn = user != null;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return SliverAppBar(
      expandedHeight: 100,
      pinned: true,
      backgroundColor: primaryColor,
      automaticallyImplyLeading: false,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(gradient: AppGradients.brand),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  if (isLoggedIn) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: Image.asset(
                        'assets/logo.jpeg',
                        width: 36,
                        height: 36,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isPhotographer
                                ? 'Photographer studio'
                                : (user.displayLabel ?? 'Welcome'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (!isPhotographer && isLoggedIn)
                            Text(
                              'Event planner · ${user.credits ?? 0} credits',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.82),
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.notifications_outlined,
                        color: Colors.white,
                        size: 22,
                      ),
                      onPressed: () {},
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ] else ...[
                    const Icon(Icons.camera_alt, color: Colors.white, size: 24),
                    const SizedBox(width: 8),
                    const Text(
                      'Airpix',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                  ],
                ],
              ),
            ),
          ),
        ),
        title: const Text(''),
      ),
    );
  }

  Widget _buildPhotographerHome(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: ActiveEventStorage.activeEvent,
      builder: (context, activeEvent, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPhotographerWorkspaceHero(context, activeEvent),
            const SizedBox(height: 22),
            _buildSectionTitle(context, 'Studio overview'),
            const SizedBox(height: 12),
            _buildStatsRow(),
            const SizedBox(height: 24),
            _buildSectionTitle(context, 'Active assignment'),
            const SizedBox(height: 12),
            _buildEventCard(context, activeEvent),
            const SizedBox(height: 24),
            _buildSectionTitle(context, 'Shoot toolkit'),
            const SizedBox(height: 12),
            _buildActionsGrid(context, activeEvent),
            const SizedBox(height: 24),
            _buildSectionTitle(context, 'Connection guide'),
            const SizedBox(height: 12),
            _buildHowItWorks(context),
          ],
        );
      },
    );
  }

  /// Photographer identity panel — the studio cockpit for a shoot day.
  Widget _buildPhotographerWorkspaceHero(
    BuildContext context,
    dynamic activeEvent,
  ) {
    final user = UserStorage.currentUser.value;
    final name = user?.displayLabel ?? 'Photographer';

    return AppGradientHero(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.camera_roll_outlined,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Photographer studio',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              AppGlassPill(
                label: activeEvent == null ? 'Idle' : 'On shoot',
                icon: activeEvent == null
                    ? Icons.pause_circle_outline
                    : Icons.radio_button_checked,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            activeEvent == null
                ? 'Pick or create an event to start shooting, syncing and delivering photos live.'
                : 'Shooting ${activeEvent.title} — photos sync and deliver while the event runs.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.88),
              fontSize: 12.5,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserHome(BuildContext context, dynamic user) {
    final isLoggedIn = user != null;
    if (!isLoggedIn) return _buildGuestHome(context);

    return ValueListenableBuilder(
      valueListenable: ActiveEventStorage.activeEvent,
      builder: (context, activeEvent, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPlannerWorkspaceHeader(context, activeEvent),
            const SizedBox(height: 22),
            _buildSectionTitle(context, 'Active event'),
            const SizedBox(height: 12),
            _buildEventCard(context, activeEvent),
            const SizedBox(height: 24),
            _buildSectionTitle(context, 'Manage'),
            const SizedBox(height: 12),
            _buildUserQuickActions(context),
            const SizedBox(height: 24),
            _buildSectionTitle(context, 'Your plans'),
            const SizedBox(height: 12),
            _buildPlansSection(context),
            const SizedBox(height: 24),
            _buildSectionTitle(context, 'Credit addons'),
            const SizedBox(height: 12),
            _buildAddonsSection(context),
          ],
        );
      },
    );
  }

  /// Planner identity panel — event management workspace.
  Widget _buildPlannerWorkspaceHeader(
    BuildContext context,
    dynamic activeEvent,
  ) {
    final user = UserStorage.currentUser.value;
    final name = user?.displayLabel ?? 'Event planner';
    final credits = user?.credits ?? 0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.07),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppIconTile(
                icon: Icons.event_available_outlined,
                size: 46,
                iconSize: 23,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Event planner workspace',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.foreground,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AppPill(
                label: 'Planner',
                icon: Icons.workspace_premium_outlined,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              AppPill(
                label: '$credits credits',
                icon: Icons.toll_outlined,
              ),
              const SizedBox(width: 8),
              AppPill(
                label: activeEvent == null ? 'No active event' : activeEvent.title,
                icon: activeEvent == null
                    ? Icons.event_busy_outlined
                    : Icons.event_available_outlined,
                color: activeEvent == null
                    ? AppColors.mutedForeground
                    : AppColors.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGuestHome(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeroSection(context),
        const SizedBox(height: 24),
        _buildGuestQrCard(context),
        const SizedBox(height: 24),
        _buildSectionTitle(context, 'Why Airpix?'),
        const SizedBox(height: 12),
        _buildFeaturesList(context),
        const SizedBox(height: 24),
        _buildSectionTitle(context, 'Popular Plans'),
        const SizedBox(height: 12),
        _buildPlansSection(context),
        const SizedBox(height: 24),
        _buildSectionTitle(context, 'Credit Addons'),
        const SizedBox(height: 12),
        _buildAddonsSection(context),
        const SizedBox(height: 32),
        _buildBottomCTA(context),
      ],
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return AppSectionTitle(title: title);
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            icon: Icons.photo_library_outlined,
            value: '0',
            label: 'Photos',
            color: Colors.blue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatTile(
            icon: Icons.mail_outline,
            value: '0',
            label: 'Invites',
            color: Colors.purple,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatTile(
            icon: Icons.cloud_done_outlined,
            value: '0',
            label: 'Uploaded',
            color: Colors.green,
          ),
        ),
      ],
    );
  }

  Widget _buildEventCard(BuildContext context, dynamic event) {
    final hasEvent = event != null;
    final isSolo =
        UserStorage.currentUser.value?.hasPlannerAccess ?? false;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: hasEvent
              ? [Colors.green.shade400, Colors.green.shade600]
              : [Colors.grey.shade400, Colors.grey.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: (hasEvent ? Colors.green : Colors.grey).withValues(
              alpha: 0.22,
            ),
            blurRadius: 24,
            offset: const Offset(0, 12),
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
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    hasEvent ? Icons.event_available : Icons.event_busy,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasEvent
                            ? event.title
                            : isSolo
                            ? 'Solo Photographer'
                            : 'No Active Event',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          height: 1.15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        hasEvent
                            ? '${event.photosCount} photos'
                            : isSolo
                            ? 'Solo mode ready - no planner invitation needed'
                            : 'Accept an invitation first',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    hasEvent
                        ? 'Active'
                        : isSolo
                        ? 'Solo'
                        : 'None',
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
    );
  }

  Widget _buildActionsGrid(BuildContext context, dynamic activeEvent) {
    final hasPlannerAccess =
        UserStorage.currentUser.value?.hasPlannerAccess ?? false;
    final isDisabled = activeEvent == null && !hasPlannerAccess;
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.3,
      children: [
        _ActionTile(
          icon: Icons.cloud_upload,
          title: 'Upload',
          subtitle: 'Upload photos',
          color: Colors.blue,
          isDisabled: isDisabled,
          onTap: isDisabled
              ? null
              : () => context.router.root.push(const UploadRoute()),
        ),
        _ActionTile(
          icon: Icons.photo_library,
          title: 'Gallery',
          subtitle: 'View photos',
          color: Colors.teal,
          isDisabled: isDisabled,
          onTap: isDisabled
              ? null
              : activeEvent == null
              ? () => context.router.root.push(const EventsRoute())
              : () => context.router.root.push(const EventImagesRoute()),
        ),
        _ActionTile(
          icon: Icons.camera_alt,
          title: 'Camera',
          subtitle: 'Take photos',
          color: Colors.orange,
          isDisabled: false,
          onTap: () => context.router.root.push(const CameraRoute()),
        ),
        _ActionTile(
          icon: Icons.qr_code_scanner,
          title: 'Scan QR',
          subtitle: 'Event QR',
          color: Colors.purple,
          isDisabled: false,
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const EventQrScanPage())),
        ),
        _ActionTile(
          icon: Icons.workspace_premium_outlined,
          title: 'Plans',
          subtitle: 'Buy or upgrade plan',
          color: Colors.indigo,
          isDisabled: false,
          onTap: () => context.router.root.push(const PlansRoute()),
        ),
      ],
    );
  }

  Widget _buildHowItWorks(BuildContext context) {
    final user = UserStorage.currentUser.value;
    if (!(user?.isPhotographer ?? false)) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final subStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
      height: 1.5,
    );

    Widget step(int number, String text) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(
                '$number',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: subStyle)),
          ],
        ),
      );
    }

    Widget modeLabel(IconData icon, String label) {
      return Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Row(
          children: [
            Icon(icon, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.indigo.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.wifi, color: Colors.indigo, size: 20),
            ),
            title: const Text(
              'Wireless Import',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            subtitle: Text('WiFi camera to phone to cloud', style: subStyle),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              step(1, 'Open Upload page and tap "Wireless Import".'),
              step(2, 'Choose a mode:'),
              const SizedBox(height: 2),
              modeLabel(Icons.router_outlined, 'Shared Network (live upload)'),
              step(3, 'Put phone and camera on the same Wi-Fi network.'),
              step(4, 'App auto-detects camera and polls for new photos.'),
              step(5, 'Every new photo uploads to cloud automatically.'),
              const Divider(height: 18),
              modeLabel(
                Icons.wifi_tethering_outlined,
                'Camera Hotspot (save & upload later)',
              ),
              step(
                3,
                'Join the camera\'s own Wi-Fi hotspot from phone settings.',
              ),
              step(4, 'App detects camera and saves every new photo locally.'),
              step(
                5,
                'Reconnect phone to internet, then tap "Upload All" to send everything to cloud.',
              ),
            ],
          ),
        ),
        Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.brown.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.usb, color: Colors.brown, size: 20),
            ),
            title: const Text(
              'OTG / USB Import',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            subtitle: Text(
              'USB cable, card reader, or adapter',
              style: subStyle,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              step(
                1,
                'Connect camera or card reader to phone via USB / OTG adapter.',
              ),
              step(2, 'Tap "OTG" on the Upload page and choose a mode:'),
              const SizedBox(height: 2),
              modeLabel(Icons.photo_library_outlined, 'Pick Images (one time)'),
              step(3, 'Select images from the file picker.'),
              step(4, 'Tap "Upload to active event" to upload them all.'),
              const Divider(height: 18),
              modeLabel(Icons.folder_open, 'Watch Folder (auto-upload)'),
              step(3, 'Select the camera\'s DCIM folder.'),
              step(
                4,
                'App watches the folder and auto-uploads every new image.',
              ),
              step(5, 'Keep taking photos \u2014 they upload as they appear.'),
            ],
          ),
        ),
        Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.pink.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.photo_library,
                color: Colors.pink,
                size: 20,
              ),
            ),
            title: const Text(
              'Phone Gallery',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            subtitle: Text(
              'Pick photos or auto-detect new ones',
              style: subStyle,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              modeLabel(Icons.touch_app_outlined, 'Manual Pick'),
              step(1, 'Tap "Phone" to open gallery and select photos.'),
              step(2, 'Tap "Upload to active event" to upload.'),
              const Divider(height: 18),
              modeLabel(Icons.autorenew, 'Auto Upload'),
              step(1, 'Tap "Auto upload from phone photos".'),
              step(2, 'App monitors your phone gallery continuously.'),
              step(3, 'Every new photo taken or saved auto-uploads to cloud.'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUserQuickActions(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickActionBtn(
            icon: Icons.qr_code_scanner,
            label: 'Scan QR',
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const EventQrScanPage())),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _QuickActionBtn(
            icon: Icons.workspace_premium,
            label: 'My Plan',
            onTap: () {},
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _QuickActionBtn(
            icon: Icons.history,
            label: 'History',
            onTap: () {},
          ),
        ),
      ],
    );
  }

  Widget _buildHeroSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.camera_alt,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  '📸 Free to start',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'Capture Every\nMoment',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Access event photos instantly with QR scan',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => context.router.root.push(const LoginRoute()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Theme.of(context).colorScheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Login',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      context.router.root.push(const RegisterRoute()),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Sign Up',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGuestQrCard(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const EventQrScanPage())),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.qr_code_scanner, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Scan QR Code',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Open event photos without login',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer
                            .withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeaturesList(BuildContext context) {
    return Column(
      children: [
        _FeatureRow(
          icon: Icons.qr_code,
          title: 'Scan QR Code',
          subtitle: 'Access event photos instantly',
        ),
        _FeatureRow(
          icon: Icons.cloud_upload,
          title: 'Easy Upload',
          subtitle: 'For photographers',
        ),
        _FeatureRow(
          icon: Icons.photo_library,
          title: 'Photo Gallery',
          subtitle: 'Browse and download',
        ),
        _FeatureRow(
          icon: Icons.share,
          title: 'Share Photos',
          subtitle: 'Share with friends & family',
        ),
      ],
    );
  }

  Widget _buildPlansSection(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadPlans(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final plans = snapshot.data ?? [];
        if (plans.isEmpty) return _buildDefaultPlans(context);

        final monthlyPlans = plans
            .where((p) => p['billingUnit'] != 'PER_YEAR')
            .toList();

        if (monthlyPlans.isEmpty) return _buildDefaultPlans(context);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: monthlyPlans.take(3).map((plan) {
            final title = plan['title']?.toString() ?? '';
            final price = (plan['discount_price'] ?? plan['price'] ?? 0)
                .toDouble();
            final isPopular = plan['isPopular'] == true;
            final features = FeatureMapping.normalizeFeatures(
              plan['features'] as List?,
            );
            final permissions = FeatureMapping.normalizePermissions(
              plan['permissions'] as List?,
            );
            final allItems = [...features, ...permissions];

            return _buildPlanCard(
              context,
              title: title,
              price: price,
              period: '/mo',
              features: allItems.isEmpty
                  ? ['View all features in Plans page']
                  : allItems,
              isPopular: isPopular,
              onBuy: () => _openMobilePaymentSheet(
                context: context,
                endpoint: '/subscription-plan/mobile-payment-sheet',
                verifyEndpoint: '/subscription-plan/verify-mobile-payment',
                data: {'id': plan['_id']},
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildDefaultPlans(BuildContext context) {
    return Column(
      children: [
        _buildPlanCard(
          context,
          title: 'Silver',
          price: 19.90,
          period: '/mo',
          features: ['50GB Storage', 'Unlimited Photographers', 'Brand Card'],
          isPopular: false,
          onBuy: () {},
        ),
        _buildPlanCard(
          context,
          title: 'Gold',
          price: 79.90,
          period: '/mo',
          features: [
            '300GB Storage',
            'AI Retouch',
            'Video Live',
            'Premium Features',
          ],
          isPopular: true,
          onBuy: () {},
        ),
        _buildPlanCard(
          context,
          title: 'Platinum',
          price: 299.90,
          period: '/mo',
          features: ['1TB Storage', 'API Access', 'Best for Events'],
          isPopular: false,
          onBuy: () {},
        ),
      ],
    );
  }

  Widget _buildPlanCard(
    BuildContext context, {
    required String title,
    required double price,
    required String period,
    required List<String> features,
    required bool isPopular,
    required VoidCallback onBuy,
  }) {
    final colors = {
      'Silver': Colors.grey,
      'Gold': Colors.amber,
      'Platinum': Colors.blue,
    };
    final color = colors[title] ?? Colors.grey;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: isPopular
            ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
            : Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.15),
              ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(18),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.workspace_premium, color: color, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          if (isPopular) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Popular',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '\$${price.toStringAsFixed(2)}',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: color,
                                ),
                          ),
                          Text(
                            period,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.6),
                                ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: features
                  .map(
                    (f) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, size: 18, color: color),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              f,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onBuy,
                style: FilledButton.styleFrom(
                  backgroundColor: isPopular
                      ? Theme.of(context).colorScheme.primary
                      : color,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Buy Now',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddonsSection(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadAddons(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final addons = snapshot.data ?? [];

        if (addons.isEmpty) {
          return Column(
            children: [
              _buildAddonCard(
                context,
                title: 'Starter Pack',
                credits: 100,
                price: 9.99,
                onBuy: () {},
              ),
              _buildAddonCard(
                context,
                title: 'Pro Pack',
                credits: 500,
                price: 39.99,
                onBuy: () {},
              ),
              _buildAddonCard(
                context,
                title: 'Enterprise',
                credits: 1000,
                price: 69.99,
                onBuy: () {},
              ),
            ],
          );
        }

        return Column(
          children: addons.take(3).map((addon) {
            return _buildAddonCard(
              context,
              title: addon['title']?.toString() ?? '',
              credits: addon['credit'] ?? 0,
              price: (addon['price'] ?? 0).toDouble(),
              onBuy: () => _openMobilePaymentSheet(
                context: context,
                endpoint: '/addon/mobile-payment-sheet',
                verifyEndpoint: '/addon/verify-mobile-payment',
                data: {'addonId': addon['_id']},
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildAddonCard(
    BuildContext context, {
    required String title,
    required int credits,
    required double price,
    required VoidCallback onBuy,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.add_circle,
              color: Theme.of(context).colorScheme.secondary,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$credits Credits',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$${price.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: onBuy,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text('Buy'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomCTA(BuildContext context) {
    return AppGradientHero(
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.photo_camera_outlined,
              size: 28,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Ready to get started?',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Join thousands of photographers and event guests',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 13,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              onPressed: () => context.router.root.push(const RegisterRoute()),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
              child: const Text('Create account'),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AppIconTile(
            icon: icon,
            size: 42,
            iconSize: 21,
            background: color.withValues(alpha: 0.12),
            foreground: color,
          ),
          const SizedBox(height: 9),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.foreground,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool isDisabled;
  final VoidCallback? onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.isDisabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tint = isDisabled ? AppColors.mutedForeground : color;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(
                  alpha: isDisabled ? 0 : 0.06,
                ),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppIconTile(
                icon: icon,
                size: 42,
                iconSize: 21,
                background: tint.withValues(alpha: isDisabled ? 0.08 : 0.13),
                foreground: tint,
              ),
              const SizedBox(height: 11),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.foreground,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.mutedForeground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppIconTile(icon: icon, size: 42, iconSize: 21),
              const SizedBox(height: 9),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          AppIconTile(icon: icon, size: 42, iconSize: 21),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    height: 1.4,
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
