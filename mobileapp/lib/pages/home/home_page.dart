import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart' hide Card;
import 'package:mobileapp/core/constants/feature_mapping.dart';
import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:mobileapp/core/router/app_router.dart';
import 'package:mobileapp/core/storage/active_event_storage.dart';
import 'package:mobileapp/core/storage/user_storage.dart';
import 'package:mobileapp/core/theme/app_theme.dart';
import 'package:mobileapp/core/upload/transfer_ledger_storage.dart';
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
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
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
    final displayName = isLoggedIn ? user.displayLabel.toString() : 'Airpix';
    final subtitle = !isLoggedIn
        ? 'Live photo delivery'
        : isPhotographer
        ? 'Photographer workspace'
        : 'Event planner · ${user.credits ?? 0} credits';

    return SliverAppBar(
      pinned: true,
      toolbarHeight: 82,
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      titleSpacing: 20,
      title: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.darkSection,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.camera_alt_rounded,
              color: Colors.white,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16.5,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.35,
                    color: AppColors.foreground,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.mutedForeground,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (isLoggedIn) ...[
            const SizedBox(width: 8),
            Container(
              width: 39,
              height: 39,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.cream,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                user.avatarText.toString(),
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPhotographerHome(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: ActiveEventStorage.activeEvent,
      builder: (context, activeEvent, _) {
        final hasPlannerAccess =
            UserStorage.currentUser.value?.hasPlannerAccess ?? false;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPhotographerWorkspaceHero(context, activeEvent),
            const SizedBox(height: 18),
            AppPrimaryActionCard(
              icon: activeEvent == null
                  ? Icons.event_available_outlined
                  : Icons.cloud_upload_outlined,
              title: activeEvent == null
                  ? 'Connect a shoot'
                  : 'Continue photo delivery',
              subtitle: activeEvent == null
                  ? 'Choose an event or accept an invitation before shooting.'
                  : 'Upload new photos to ${activeEvent.title}.',
              actionLabel: activeEvent == null ? 'Choose' : 'Upload',
              onTap: () {
                if (activeEvent != null) {
                  context.router.root.push(const UploadRoute());
                } else if (hasPlannerAccess) {
                  context.router.root.push(const EventsRoute());
                } else {
                  context.router.root.push(const InvitationsRoute());
                }
              },
            ),
            const SizedBox(height: 26),
            _buildSectionTitle(context, 'Today'),
            const SizedBox(height: 12),
            _buildStatsRow(activeEvent),
            const SizedBox(height: 26),
            _buildSectionTitle(context, 'Active event'),
            const SizedBox(height: 12),
            _buildEventCard(context, activeEvent),
            const SizedBox(height: 26),
            _buildSectionTitle(context, 'Quick tools'),
            const SizedBox(height: 12),
            _buildActionsGrid(context, activeEvent),
            const SizedBox(height: 26),
            _buildSectionTitle(context, 'Camera connection help'),
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
            const SizedBox(height: 18),
            AppPrimaryActionCard(
              icon: activeEvent == null
                  ? Icons.add_circle_outline_rounded
                  : Icons.event_available_outlined,
              title: activeEvent == null
                  ? 'Create your next event'
                  : 'Manage ${activeEvent.title}',
              subtitle: activeEvent == null
                  ? 'Set up an event, invite photographers and start delivery.'
                  : 'Open events to manage galleries, guests and photographers.',
              actionLabel: activeEvent == null ? 'Create' : 'Manage',
              onTap: () => context.router.root.push(const EventsRoute()),
            ),
            const SizedBox(height: 26),
            _buildSectionTitle(context, 'Workspace shortcuts'),
            const SizedBox(height: 12),
            _buildUserQuickActions(context),
            const SizedBox(height: 28),
            _buildSectionTitle(context, 'Plans'),
            const SizedBox(height: 12),
            _buildPlansSection(context),
            const SizedBox(height: 26),
            _buildSectionTitle(context, 'Extra credits'),
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
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 22,
            offset: const Offset(0, 10),
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
              AppPill(label: 'Planner', icon: Icons.workspace_premium_outlined),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppPill(
                label: '$credits credits',
                icon: Icons.toll_outlined,
                color: AppColors.tertiary,
              ),
              AppPill(
                label: activeEvent == null
                    ? 'No active event'
                    : activeEvent.title,
                icon: activeEvent == null
                    ? Icons.event_busy_outlined
                    : Icons.event_available_outlined,
                color: activeEvent == null
                    ? AppColors.mutedForeground
                    : AppColors.secondary,
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
        _buildGuestQrCard(context),
        const SizedBox(height: 18),
        _buildHeroSection(context),
        const SizedBox(height: 26),
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

  Widget _buildStatsRow(dynamic activeEvent) {
    final eventId = activeEvent?.id?.toString();

    return ValueListenableBuilder<List<TransferLedgerItem>>(
      valueListenable: TransferLedgerStorage.items,
      builder: (context, items, _) {
        final eventTransfers = eventId == null
            ? const <TransferLedgerItem>[]
            : items.where((item) => item.eventId == eventId).toList();
        final pending = eventTransfers.where((item) => item.isPending).length;
        final uploaded = eventTransfers.where((item) => item.isUploaded).length;
        final photos = activeEvent?.photosCount ?? 0;

        return Row(
          children: [
            Expanded(
              child: _StatTile(
                icon: Icons.photo_library_outlined,
                value: '$photos',
                label: 'Event photos',
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatTile(
                icon: Icons.schedule_rounded,
                value: '$pending',
                label: 'Pending',
                color: AppColors.tertiary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatTile(
                icon: Icons.cloud_done_outlined,
                value: '$uploaded',
                label: 'Delivered',
                color: AppColors.secondary,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEventCard(BuildContext context, dynamic event) {
    final hasEvent = event != null;
    final isSolo = UserStorage.currentUser.value?.hasPlannerAccess ?? false;
    final title = hasEvent
        ? event.title.toString()
        : isSolo
        ? 'Solo Photographer'
        : 'No active event';
    final detail = hasEvent
        ? '${event.photosCount} photos ready in this workspace'
        : isSolo
        ? 'Your solo workspace is ready for capture and delivery.'
        : 'Accept an invitation to connect a live event.';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 82,
            height: 82,
            decoration: BoxDecoration(
              gradient: hasEvent ? AppGradients.studio : null,
              color: hasEvent ? null : AppColors.muted,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Stack(
              children: [
                Center(
                  child: Icon(
                    hasEvent
                        ? Icons.photo_library_outlined
                        : Icons.event_note_outlined,
                    color: hasEvent ? Colors.white : AppColors.mutedForeground,
                    size: 28,
                  ),
                ),
                if (hasEvent)
                  Positioned(
                    right: 9,
                    bottom: 9,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(width: 8),
                    AppPill(
                      label: hasEvent
                          ? 'Live'
                          : isSolo
                          ? 'Solo'
                          : 'Waiting',
                      color: hasEvent
                          ? AppColors.success
                          : AppColors.mutedForeground,
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Icon(
                      hasEvent
                          ? Icons.cloud_done_outlined
                          : Icons.cloud_queue_outlined,
                      size: 15,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      hasEvent
                          ? 'Delivery workspace connected'
                          : 'Not connected',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.mutedForeground,
                      ),
                    ),
                  ],
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
          icon: Icons.photo_library_outlined,
          title: 'Gallery',
          subtitle: 'Review uploaded media',
          color: AppColors.secondary,
          isDisabled: isDisabled,
          onTap: isDisabled
              ? null
              : activeEvent == null
              ? () => context.router.root.push(const EventsRoute())
              : () => context.router.root.push(const EventImagesRoute()),
        ),
        _ActionTile(
          icon: Icons.camera_alt_outlined,
          title: 'Camera',
          subtitle: 'Open capture tools',
          color: AppColors.primary,
          isDisabled: false,
          onTap: () => context.router.root.push(const CameraRoute()),
        ),
        _ActionTile(
          icon: Icons.qr_code_scanner_rounded,
          title: 'Scan QR',
          subtitle: 'Guest delivery QR',
          color: AppColors.secondary,
          isDisabled: false,
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const EventQrScanPage())),
        ),
        _ActionTile(
          icon: Icons.workspace_premium_outlined,
          title: 'Plans',
          subtitle: 'Storage & billing',
          color: AppColors.tertiary,
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
                color: AppColors.secondarySoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.wifi,
                color: AppColors.secondary,
                size: 20,
              ),
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
    return Column(
      children: [
        AppActionCard(
          icon: Icons.qr_code_scanner_rounded,
          title: 'Scan guest QR',
          subtitle: 'Open a guest gallery or delivery link instantly.',
          trailing: const AppPill(
            label: 'Fast',
            icon: Icons.bolt_rounded,
            color: AppColors.secondary,
          ),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const EventQrScanPage())),
        ),
        const SizedBox(height: 10),
        AppActionCard(
          icon: Icons.workspace_premium_outlined,
          title: 'Plans & billing',
          subtitle: 'Manage storage, subscription features and credits.',
          onTap: () => context.router.root.push(const PlansRoute()),
        ),
        const SizedBox(height: 10),
        AppActionCard(
          icon: Icons.person_outline_rounded,
          title: 'Account & contact',
          subtitle: 'Keep your planner profile and contact details current.',
          onTap: () => context.router.root.push(const ProfileRoute()),
        ),
      ],
    );
  }

  Widget _buildHeroSection(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: AppGradients.brand,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.18),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -54,
            top: -58,
            child: Container(
              width: 170,
              height: 170,
              decoration: BoxDecoration(
                color: AppColors.secondary.withValues(alpha: 0.24),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            right: 26,
            bottom: -34,
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: AppColors.tertiary.withValues(alpha: 0.22),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const AppGlassPill(
                      label: 'Live photo delivery',
                      icon: Icons.bolt_rounded,
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.tertiary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'FREE TO START',
                        style: TextStyle(
                          color: Color(0xFF422006),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.7,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                const Text(
                  'Your event photos,\nready in seconds.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    height: 1.06,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.9,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Photographers upload while guests discover and download through a simple QR experience.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 13.5,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () =>
                            context.router.root.push(const RegisterRoute()),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: AppColors.primaryDark,
                        ),
                        child: const Text('Create account'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            context.router.root.push(const LoginRoute()),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                        child: const Text('Sign in'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
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
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: AppGradients.discovery,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            boxShadow: [
              BoxShadow(
                color: AppColors.secondary.withValues(alpha: 0.16),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.qr_code_scanner_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Have an event QR?',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        AppGlassPill(label: 'No login'),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Scan once to open your event gallery and find your photos.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white,
                size: 20,
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
      'Silver': const Color(0xFF78716C),
      'Gold': const Color(0xFFA16207),
      'Platinum': AppColors.secondary,
    };
    final color = colors[title] ?? AppColors.primary;

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
            boxShadow: isDisabled
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.025),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
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
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
