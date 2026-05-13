export const featureMapping = {
  "photo.upload": "Photo Upload",
  "photo.gallery": "Photo Gallery",
  "photo.download": "Photo Download",
  "photo.share": "Photo Sharing",
  "photo.qr": "QR Code Generation",
  "photo.aiRetouch": "AI Retouch",
  "photo.aiReview": "AI Reviewer",
  "photo.aiSearch": "AI Search",
  "photo.privacy": "Privacy Protection",
  "photo.watermark": "Photo Watermark",
  "photo.brandCard": "Brand Card",

  "event.create": "Create Events",
  "event.live": "Live Album",
  "event.realtime": "Real-time Photo Sync",
  "event.premium": "Unlock Album Premium Features",
  "event.videoLive": "Video Live",
  "event.urlCustom": "Access URL Customization",

  "camera.otg": "OTG Cable Transfer",
  "camera.ftp": "FTP Wireless Transfer",

  "branding.premium": "Premium Branding",
  "branding.footerAd": "Footer Ad",
  "branding.sidebarAd": "Sidebar Ad",
  "branding.loadingPage": "Loading Page",
  "branding.pageTitleAd": "Page Title Ad",
  "api.access": "API Access",
  "analytics.view": "Analytics Dashboard",
};

export const limitMapping = {
  "credit": "Plan Credits",
  "photos.monthly": "Monthly Photo Upload Limit",
  "photographers.max": "Max Photographers",
  "events.active": "Max Active Events",
  "albums.categories": "Categories Per Album",
  "storage.gb": "PiuCloud Storage (GB)",
};

export function getFeatureDescription(key: string): string {
  return featureMapping[key as keyof typeof featureMapping] || key;
}

export function getLimitDescription(key: string): string {
  return limitMapping[key as keyof typeof limitMapping] || key;
}

export type FeatureKey = keyof typeof featureMapping;
export type LimitKey = keyof typeof limitMapping;
