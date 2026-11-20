/** All purchased-photo delivery links remain valid for 30 x 24 hours. */
export const PURCHASE_LINK_LIFETIME_HOURS = 30 * 24;
export const PURCHASE_LINK_LIFETIME_MS = PURCHASE_LINK_LIFETIME_HOURS * 60 * 60 * 1000;

export function purchasedPhotoLinkExpiresAt(paidAt: Date): Date {
  if (!(paidAt instanceof Date) || !Number.isFinite(paidAt.getTime())) {
    throw new Error('A valid payment timestamp is required');
  }
  return new Date(paidAt.getTime() + PURCHASE_LINK_LIFETIME_MS);
}
