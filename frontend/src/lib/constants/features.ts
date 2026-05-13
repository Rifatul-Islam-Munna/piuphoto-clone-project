export const featureMapping = {
  "photo.upload": "Photo Upload",
  "photo.gallery": "Photo Gallery",
  "photo.download": "Photo Download",
  "photo.share": "Photo Sharing",
  "photo.qr": "QR Code Generation",
  "photo.aiRetouch": "AI Retouch",
  "custom.enhancer": "Custom AI Enhancer Prompt",
  "event.create": "Create Events",
  "event.live": "Live Album",
  "event.realtime": "Real-time Photo Sync",
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
