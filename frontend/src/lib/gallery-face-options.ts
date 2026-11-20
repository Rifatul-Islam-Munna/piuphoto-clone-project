/** Face enrollment is always opt-in on ordinary shared event links.
 * Event owners may separately configure a facial-only/private gallery;
 * that explicit access policy continues to apply.
 */
export function shouldGateGalleryForFace(options: {
  isFaceDeliveryLink: boolean;
  userSelectedFaceSetup: boolean;
  eventRequiresFaceSearch: boolean;
  isFacialOnlyGallery: boolean;
  hasGuestToken: boolean;
}): boolean {
  if (options.hasGuestToken) return false;
  return options.eventRequiresFaceSearch ||
    options.isFacialOnlyGallery ||
    (options.isFaceDeliveryLink && options.userSelectedFaceSetup);
}
