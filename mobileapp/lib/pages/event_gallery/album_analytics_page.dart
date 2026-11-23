import 'package:flutter/material.dart';
import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:mobileapp/core/theme/app_theme.dart';
import 'package:mobileapp/core/utils/image_loader.dart';

class AlbumAnalyticsPage extends StatefulWidget {
  const AlbumAnalyticsPage({
    super.key,
    required this.eventId,
    required this.eventTitle,
    required this.albumId,
    required this.albumTitle,
  });

  final String eventId;
  final String eventTitle;
  final String albumId;
  final String albumTitle;

  @override
  State<AlbumAnalyticsPage> createState() => _AlbumAnalyticsPageState();
}

class _AlbumAnalyticsPageState extends State<AlbumAnalyticsPage> {
  Map<String, dynamic> _summary = {};
  bool _loading = true;
  String? _error;

  int _number(dynamic value) => int.tryParse(value?.toString() ?? '') ?? 0;

  double _decimal(dynamic value) =>
      double.tryParse(value?.toString() ?? '') ?? 0;

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await DioHelper.get(
        '/analytics/summary',
        queryParameters: {'eventId': widget.eventId, 'albumId': widget.albumId},
      );
      if (!mounted) return;
      setState(() => _summary = _map(response.data));
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load album analytics.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _metric(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({required String title, required List<Widget> children}) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.mutedForeground,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final engagement = _map(_summary['engagement']);
    final photos = _map(_summary['photos']);
    final retouch = _map(_summary['retouch']);
    final store = _map(_summary['store']);
    final guests = _map(_summary['guests']);
    final transfers = _map(_summary['transfers']);
    final ai = _map(_summary['ai']);
    final retouchStatuses = _map(retouch['statuses']);
    final notificationStatuses = _map(guests['notifications']);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'PiuAlbum Analytics',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: [
                  Text(
                    widget.albumTitle,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    widget.eventTitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: 16),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 9,
                    crossAxisSpacing: 9,
                    childAspectRatio: 2.15,
                    children: [
                      _metric(
                        'Gallery visits',
                        _number(engagement['gallery_visit']).toString(),
                        Icons.visibility_outlined,
                      ),
                      _metric(
                        'Unique viewers',
                        _number(engagement['uniqueViewers']).toString(),
                        Icons.people_outline_rounded,
                      ),
                      _metric(
                        'Photo views',
                        _number(engagement['image_view']).toString(),
                        Icons.photo_outlined,
                      ),
                      _metric(
                        'Downloads',
                        _number(engagement['download']).toString(),
                        Icons.download_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _sectionCard(
                    title: 'Photo pipeline',
                    children: [
                      _row('Captured', _number(photos['captured']).toString()),
                      _row(
                        'Published',
                        _number(photos['published']).toString(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _sectionCard(
                    title: 'Retouch production',
                    children: [
                      _row(
                        'Average turnaround',
                        '${_decimal(retouch['averageTurnaroundMinutes']).toStringAsFixed(1)} min',
                      ),
                      for (final entry in retouchStatuses.entries)
                        _row(
                          entry.key.replaceAll('_', ' '),
                          _number(entry.value).toString(),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _sectionCard(
                    title: 'Store and AI',
                    children: [
                      _row(
                        'Revenue',
                        _decimal(store['revenue']).toStringAsFixed(2),
                      ),
                      _row(
                        'Paid orders',
                        _number(store['paidOrders']).toString(),
                      ),
                      _row(
                        'Purchased photos',
                        _number(store['purchasedPhotos']).toString(),
                      ),
                      for (final entry in ai.entries)
                        _row(
                          'AI ${entry.key.replaceAll('_', ' ')}',
                          _number(entry.value).toString(),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _sectionCard(
                    title: 'Guest activity',
                    children: [
                      _row(
                        'Active personal galleries',
                        _number(guests['activePersonalGalleries']).toString(),
                      ),
                      for (final entry in notificationStatuses.entries)
                        _row(
                          'Notifications ${entry.key.replaceAll('_', ' ')}',
                          _number(entry.value).toString(),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _sectionCard(
                    title: 'Transfers',
                    children: [
                      if (transfers.isEmpty)
                        const Text(
                          'No transfer activity yet.',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.mutedForeground,
                          ),
                        ),
                      for (final entry in transfers.entries)
                        _row(
                          entry.key.replaceAll('_', ' '),
                          _number(entry.value).toString(),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _sectionCard(
                    title: 'Popular photos',
                    children: [
                      for (final item
                          in (_summary['popularPhotos'] as List? ?? []).take(6))
                        _popularPhoto(_map(item)),
                      if ((_summary['popularPhotos'] as List? ?? []).isEmpty)
                        const Text(
                          'No photo engagement yet.',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.mutedForeground,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _popularPhoto(Map<String, dynamic> item) {
    final image = _map(item['image']);
    final imageUrl = image['imageUrl']?.toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 52,
              height: 52,
              child: imageUrl?.isNotEmpty == true
                  ? ImageLoader.loadImage(imageUrl!)
                  : const ColoredBox(
                      color: AppColors.accentSoft,
                      child: Icon(
                        Icons.photo_outlined,
                        color: AppColors.primary,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  image['userTakenBy'] is Map
                      ? (_map(image['userTakenBy'])['name']?.toString() ??
                            'Photo')
                      : 'Photo',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_number(item['views'])} views · ${_number(item['downloads'])} downloads · ${_number(item['shares'])} shares',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.mutedForeground,
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
