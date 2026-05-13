class FeatureMapping {
  static const Map<String, String> features = {
    'photo.upload': 'Photo Upload',
    'photo.gallery': 'Photo Gallery',
    'photo.download': 'Photo Download',
    'photo.share': 'Photo Sharing',
    'photo.qr': 'QR Code Generation',
    'photo.aiRetouch': 'AI Retouch',
    'photo.aiReview': 'AI Reviewer',
    'photo.aiSearch': 'AI Search',
    'photo.privacy': 'Privacy Protection',
    'photo.watermark': 'Photo Watermark',
    'photo.brandCard': 'Brand Card',
    'event.create': 'Create Events',
    'event.live': 'Live Album',
    'event.realtime': 'Real-time Photo Sync',
    'event.premium': 'Unlock Album Premium Features',
    'event.videoLive': 'Video Live',
    'event.urlCustom': 'Access URL Customization',
    'camera.otg': 'OTG Cable Transfer',
    'camera.ftp': 'FTP Wireless Transfer',
    'branding.premium': 'Premium Branding',
    'branding.footerAd': 'Footer Ad',
    'branding.sidebarAd': 'Sidebar Ad',
    'branding.loadingPage': 'Loading Page',
    'branding.pageTitleAd': 'Page Title Ad',
    'api.access': 'API Access',
    'analytics.view': 'Analytics Dashboard',
    'custom.enhancer': 'Custom AI Enhancer Prompt',
  };

  static const Map<String, String> limits = {
    'credit': 'Plan Credits',
    'photos.monthly': 'Monthly Photo Upload Limit',
    'photographers.max': 'Max Photographers',
    'events.active': 'Max Active Events',
    'albums.categories': 'Categories Per Album',
    'storage.gb': 'PiuCloud Storage (GB)',
  };

  static String getFeatureDescription(String key) {
    return features[key] ?? key;
  }

  static String getLimitDescription(String key) {
    return limits[key] ?? key;
  }

  static List<String> normalizeFeatures(List<dynamic>? featuresList) {
    if (featuresList == null) return [];
    return featuresList
        .map((f) => f is String ? getFeatureDescription(f) : f.toString())
        .toList();
  }

  static List<String> normalizePermissions(List<dynamic>? permissions) {
    if (permissions == null) return [];
    final List<String> result = [];
    for (final perm in permissions) {
      if (perm is Map) {
        final key = perm['key'];
        final value = perm['value'];
        if (key != null && value != null) {
          result.add('${getLimitDescription(key.toString())}: $value');
        } else {
          perm.forEach((k, v) {
            if (k != '_id' && k != 'id' && v != null) {
              result.add('${getLimitDescription(k.toString())}: $v');
            }
          });
        }
      }
    }
    return result;
  }
}
