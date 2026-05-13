import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:mobileapp/core/constants/feature_mapping.dart';
import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:mobileapp/core/router/app_router.dart';
import 'package:mobileapp/core/storage/active_event_storage.dart';
import 'package:mobileapp/core/storage/user_storage.dart';
import 'package:mobileapp/models/user_model.dart';
import 'package:mobileapp/pages/event_gallery/event_qr_scan_page.dart';
import 'package:mobileapp/utilities/app_toast.dart';

@RoutePage()
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  Future<List<Map<String, dynamic>>> _loadPlans() async {
    final response = await DioHelper.get('/subscription-plan/get-all?limit=100&isActive=true');
    final data = response.data['data'] as List? ?? [];
    return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> _loadAddons() async {
    final response = await DioHelper.get('/addon/get-all?limit=100&isActive=true');
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
      final clientSecret =
          paymentData['paymentIntentClientSecret']?.toString();
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
          merchantDisplayName: 'Nikofly',
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
      } catch (_) {}
      AppToast.success('Payment successful');
    } on StripeException catch (e) {
      AppToast.error(e.error.localizedMessage ?? 'Payment cancelled');
    } catch (_) {
      AppToast.error('Payment failed');
    }
  }

  Future<void> _refreshCurrentUser() async {
    final response = await DioHelper.get('/user/get-my-profile');
    final rawUser = response.data['data'] ?? response.data;
    if (rawUser is Map) {
      await UserStorage.saveUser(
        UserModel.fromJson(Map<String, dynamic>.from(rawUser)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: UserStorage.currentUser,
      builder: (context, user, _) {
        final isPhotographer = user?.isPhotographer ?? false;
        return Scaffold(
          body: CustomScrollView(
            slivers: [
              _buildAppBar(context, user, isPhotographer),
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate(
                    isPhotographer 
                      ? [_buildPhotographerHome(context)]
                      : [_buildUserHome(context, user)],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  SliverAppBar _buildAppBar(BuildContext context, dynamic user, bool isPhotographer) {
    final isLoggedIn = user != null;
    final primaryColor = Theme.of(context).colorScheme.primary;
    
    return SliverAppBar(
      expandedHeight: 100,
      pinned: true,
      backgroundColor: primaryColor,
      automaticallyImplyLeading: false,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [primaryColor, primaryColor.withValues(alpha: 0.8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  if (isLoggedIn) ...[
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.white.withValues(alpha: 0.25),
                      child: const Icon(Icons.person, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isPhotographer ? 'Photographer' : (user.displayLabel ?? 'Welcome'),
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (!isPhotographer && isLoggedIn)
                            Text(
                              '${user.credits ?? 0} Credits',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.notifications_outlined, color: Colors.white, size: 22),
                      onPressed: () {},
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ] else ...[
                    const Icon(Icons.camera_alt, color: Colors.white, size: 24),
                    const SizedBox(width: 8),
                    const Text(
                      'Nikofly',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
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
            _buildSectionTitle(context, 'Dashboard'),
            const SizedBox(height: 12),
            _buildStatsRow(),
            const SizedBox(height: 24),
            _buildSectionTitle(context, 'Assigned Event'),
            const SizedBox(height: 12),
            _buildEventCard(context, activeEvent),
            const SizedBox(height: 24),
            _buildSectionTitle(context, 'Quick Actions'),
            const SizedBox(height: 12),
            _buildActionsGrid(context, activeEvent),
            const SizedBox(height: 24),
            _buildSectionTitle(context, 'Upload Methods'),
            const SizedBox(height: 12),
            _buildUploadMethods(context),
          ],
        );
      },
    );
  }

  Widget _buildUserHome(BuildContext context, dynamic user) {
    final isLoggedIn = user != null;
    if (!isLoggedIn) return _buildGuestHome(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildUserQuickActions(context),
        const SizedBox(height: 24),
        _buildSectionTitle(context, 'Your Plans'),
        const SizedBox(height: 12),
        _buildPlansSection(context),
        const SizedBox(height: 24),
        _buildSectionTitle(context, 'Credit Addons'),
        const SizedBox(height: 12),
        _buildAddonsSection(context),
      ],
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
        _buildSectionTitle(context, 'Why Nikofly?'),
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
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(child: _StatTile(icon: Icons.photo_library_outlined, value: '0', label: 'Photos', color: Colors.blue)),
        const SizedBox(width: 12),
        Expanded(child: _StatTile(icon: Icons.mail_outline, value: '0', label: 'Invites', color: Colors.purple)),
        const SizedBox(width: 12),
        Expanded(child: _StatTile(icon: Icons.cloud_done_outlined, value: '0', label: 'Uploaded', color: Colors.green)),
      ],
    );
  }

  Widget _buildEventCard(BuildContext context, dynamic event) {
    final hasEvent = event != null;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: hasEvent ? [Colors.green.shade400, Colors.green.shade600] : [Colors.grey.shade400, Colors.grey.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
            child: Icon(hasEvent ? Icons.event_available : Icons.event_busy, color: Colors.white, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(hasEvent ? event.title : 'No Active Event', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(hasEvent ? '${event.photosCount} photos' : 'Accept an invitation first', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 14)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: Text(hasEvent ? 'Active' : 'None', style: TextStyle(color: hasEvent ? Colors.green : Colors.grey, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsGrid(BuildContext context, dynamic activeEvent) {
    final isDisabled = activeEvent == null;
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.3,
      children: [
        _ActionTile(icon: Icons.cloud_upload, title: 'Upload', subtitle: 'Upload photos', color: Colors.blue, isDisabled: isDisabled, onTap: isDisabled ? null : () => context.router.root.push(const UploadRoute())),
        _ActionTile(icon: Icons.photo_library, title: 'Gallery', subtitle: 'View photos', color: Colors.teal, isDisabled: isDisabled, onTap: isDisabled ? null : () => context.router.root.push(const EventImagesRoute())),
        _ActionTile(icon: Icons.camera_alt, title: 'Camera', subtitle: 'Take photos', color: Colors.orange, isDisabled: false, onTap: () => context.router.root.push(const CameraRoute())),
        _ActionTile(icon: Icons.qr_code_scanner, title: 'Scan QR', subtitle: 'Event QR', color: Colors.purple, isDisabled: false, onTap: () {}),
      ],
    );
  }

  Widget _buildUploadMethods(BuildContext context) {
    return Column(
      children: [
        _MethodCard(icon: Icons.wifi, title: 'Auto Upload', description: 'Connect camera via WiFi - photos auto-upload', color: Colors.indigo),
        _MethodCard(icon: Icons.usb, title: 'OTG / USB', description: 'Use USB drive, card reader, or file picker', color: Colors.brown),
        _MethodCard(icon: Icons.photo_library, title: 'Phone Gallery', description: 'Manually select photos from phone', color: Colors.pink),
      ],
    );
  }

  Widget _buildUserQuickActions(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _QuickActionBtn(icon: Icons.qr_code_scanner, label: 'Scan QR', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EventQrScanPage())))),
        const SizedBox(width: 12),
        Expanded(child: _QuickActionBtn(icon: Icons.workspace_premium, label: 'My Plan', onTap: () {})),
        const SizedBox(width: 12),
        Expanded(child: _QuickActionBtn(icon: Icons.history, label: 'History', onTap: () {})),
      ],
    );
  }

  Widget _buildHeroSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.primary.withValues(alpha: 0.7)],
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
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.camera_alt, color: Colors.white, size: 32),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
                child: const Text('📸 Free to start', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text('Capture Every\nMoment', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold, height: 1.2)),
          const SizedBox(height: 8),
          Text('Access event photos instantly with QR scan', style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 14)),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => context.router.root.push(const LoginRoute()),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Theme.of(context).colorScheme.primary, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: const Text('Login', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => context.router.root.push(const RegisterRoute()),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: const Text('Sign Up', style: TextStyle(fontWeight: FontWeight.bold)),
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
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const EventQrScanPage()),
        ),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
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
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer
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
        _FeatureRow(icon: Icons.qr_code, title: 'Scan QR Code', subtitle: 'Access event photos instantly'),
        _FeatureRow(icon: Icons.cloud_upload, title: 'Easy Upload', subtitle: 'For photographers'),
        _FeatureRow(icon: Icons.photo_library, title: 'Photo Gallery', subtitle: 'Browse and download'),
        _FeatureRow(icon: Icons.share, title: 'Share Photos', subtitle: 'Share with friends & family'),
      ],
    );
  }

  Widget _buildPlansSection(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadPlans(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final plans = snapshot.data ?? [];
        if (plans.isEmpty) return _buildDefaultPlans(context);
        
        final monthlyPlans = plans.where((p) => p['billingUnit'] != 'PER_YEAR').toList();
        
        if (monthlyPlans.isEmpty) return _buildDefaultPlans(context);
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: monthlyPlans.take(3).map((plan) {
            final title = plan['title']?.toString() ?? '';
            final price = (plan['discount_price'] ?? plan['price'] ?? 0).toDouble();
            final isPopular = plan['isPopular'] == true;
            final features = FeatureMapping.normalizeFeatures(plan['features'] as List?);
            final permissions = FeatureMapping.normalizePermissions(plan['permissions'] as List?);
            final allItems = [...features, ...permissions];
            
            return _buildPlanCard(
              context,
              title: title,
              price: price,
              period: '/mo',
              features: allItems.isEmpty ? ['View all features in Plans page'] : allItems,
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
        _buildPlanCard(context, title: 'Silver', price: 19.90, period: '/mo', features: ['50GB Storage', 'Unlimited Photographers', 'Brand Card'], isPopular: false, onBuy: () {}),
        _buildPlanCard(context, title: 'Gold', price: 79.90, period: '/mo', features: ['300GB Storage', 'AI Retouch', 'Video Live', 'Premium Features'], isPopular: true, onBuy: () {}),
        _buildPlanCard(context, title: 'Platinum', price: 299.90, period: '/mo', features: ['1TB Storage', 'API Access', 'Best for Events'], isPopular: false, onBuy: () {}),
      ],
    );
  }

  Widget _buildPlanCard(BuildContext context, {required String title, required double price, required String period, required List<String> features, required bool isPopular, required VoidCallback onBuy}) {
    final colors = {'Silver': Colors.grey, 'Gold': Colors.amber, 'Platinum': Colors.blue};
    final color = colors[title] ?? Colors.grey;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: isPopular ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2) : Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.15)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.workspace_premium, color: color, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                          if (isPopular) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(8)),
                              child: const Text('Popular', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('\$${price.toStringAsFixed(2)}', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: color)),
                          Text(period, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
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
              children: features.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, size: 18, color: color),
                    const SizedBox(width: 10),
                    Expanded(child: Text(f, style: Theme.of(context).textTheme.bodyMedium)),
                  ],
                ),
              )).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onBuy,
                style: FilledButton.styleFrom(
                  backgroundColor: isPopular ? Theme.of(context).colorScheme.primary : color,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Buy Now', style: TextStyle(fontWeight: FontWeight.bold)),
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
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final addons = snapshot.data ?? [];
        
        if (addons.isEmpty) {
          return Column(
            children: [
              _buildAddonCard(context, title: 'Starter Pack', credits: 100, price: 9.99, onBuy: () {}),
              _buildAddonCard(context, title: 'Pro Pack', credits: 500, price: 39.99, onBuy: () {}),
              _buildAddonCard(context, title: 'Enterprise', credits: 1000, price: 69.99, onBuy: () {}),
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

  Widget _buildAddonCard(BuildContext context, {required String title, required int credits, required double price, required VoidCallback onBuy}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.add_circle, color: Theme.of(context).colorScheme.secondary, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(6)),
                  child: Text('$credits Credits', style: TextStyle(color: Theme.of(context).colorScheme.onSecondaryContainer, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('\$${price.toStringAsFixed(2)}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: onBuy,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          const Icon(Icons.photo_camera, size: 40),
          const SizedBox(height: 12),
          Text('Ready to get started?', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Join thousands of photographers and event guests', style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: () => context.router.root.push(const RegisterRoute()), child: const Text('Create Account'))),
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

  const _StatTile({required this.icon, required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.15)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: theme.colorScheme.primary, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
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

  const _ActionTile({required this.icon, required this.title, required this.subtitle, required this.color, required this.isDisabled, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 2))]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: isDisabled ? color.withValues(alpha: 0.3) : color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: isDisabled ? color.withValues(alpha: 0.5) : color, size: 24)),
            const SizedBox(height: 10),
            Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
          ]),
        ),
      ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color color;

  const _MethodCard({required this.icon, required this.title, required this.description, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.15))),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color, size: 24)),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)), const SizedBox(height: 2), Text(description, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)))])),
        Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)),
      ]),
    );
  }
}

class _QuickActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionBtn({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.15)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: theme.colorScheme.primary, size: 28),
              const SizedBox(height: 8),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
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

  const _FeatureRow({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20)),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)), Text(subtitle, style: Theme.of(context).textTheme.bodySmall)])),
      ]),
    );
  }
}
