import { describe, expect, it } from "vitest";
import { shouldGateGalleryForFace } from "./gallery-face-options";

const defaults = {
  isFaceDeliveryLink: true,
  userSelectedFaceSetup: false,
  eventRequiresFaceSearch: false,
  isFacialOnlyGallery: false,
  hasGuestToken: false,
};

describe("optional face enrollment on shared photo links", () => {
  it("opens ordinary and face-invite links as galleries without demanding a selfie", () => {
    expect(shouldGateGalleryForFace(defaults)).toBe(false);
    expect(shouldGateGalleryForFace({ ...defaults, isFaceDeliveryLink: false })).toBe(false);
  });

  it("opens enrollment only after the guest explicitly selects face delivery", () => {
    expect(shouldGateGalleryForFace({ ...defaults, userSelectedFaceSetup: true })).toBe(true);
    expect(shouldGateGalleryForFace({
      ...defaults, isFaceDeliveryLink: false, userSelectedFaceSetup: true,
    })).toBe(false);
  });

  it("respects an event organizer's separate facial-only/privacy access policy", () => {
    expect(shouldGateGalleryForFace({
      ...defaults, eventRequiresFaceSearch: true,
    })).toBe(true);
    expect(shouldGateGalleryForFace({
      ...defaults, isFacialOnlyGallery: true,
    })).toBe(true);
  });

  it("does not ask already-enrolled guests to enroll again", () => {
    expect(shouldGateGalleryForFace({
      ...defaults, eventRequiresFaceSearch: true, hasGuestToken: true,
    })).toBe(false);
  });
});
