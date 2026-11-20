import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import StoreOrder from "./StoreOrder";

const photoId = "507f1f77bcf86cd799439012";
const orderId = "507f1f77bcf86cd799439011";
const token = "purchased-photo-access-token";

vi.mock("@/api-hooks/api-hooks", () => ({
  GetRequestAxios: vi.fn(async () => [{
    data: {
      orderNo: "ORD-PAID-1",
      email: "buyer@example.test",
      currency: "USD",
      amount: 5,
      downloadExpiresAt: "2026-12-21T10:00:00.000Z",
      eventId: { _id: "507f1f77bcf86cd799439013", title: "Nikos event" },
      imageIds: [
        {
          _id: photoId,
          previewUrl: "/store/public/preview?eventId=event&imageId=photo",
          downloadUrl: `/store/public/download?orderId=${orderId}&imageId=${photoId}&token=${token}`,
        },
      ],
    },
  }, null]),
  PostRequestAxios: vi.fn(async () => [{}, null]),
}));

afterEach(() => cleanup());

describe("purchased photo delivery", () => {
  it("shows immediate native ZIP and individual photo links plus the email destination", async () => {
    render(
      <MemoryRouter initialEntries={[`/store/order/${orderId}?token=${token}`]}>
        <Routes>
          <Route path="/store/order/:orderId" element={<StoreOrder />} />
        </Routes>
      </MemoryRouter>,
    );

    expect(await screen.findByText("Your photos are ready")).toBeInTheDocument();
    expect(screen.getByText(/buyer@example.test/)).toBeInTheDocument();
    const zip = screen.getByRole("link", { name: /Download all originals/ });
    expect(zip.getAttribute("href")).toContain("/store/public/download-all.zip");
    expect(zip.getAttribute("href")).toContain(`token=${token}`);
    // Native same-tab attachment navigation works without a popup
    // (important for iPhone Safari, where new tabs can be blocked).
    expect(zip).not.toHaveAttribute("target", "_blank");
    expect(zip).toHaveAttribute("referrerpolicy", "no-referrer");
    expect(screen.getByRole("button", { name: /Save photos individually/ })).toBeInTheDocument();
    const original = screen.getByRole("link", { name: /Download purchased photo 1/ });
    expect(original.getAttribute("href")).toContain("/store/public/download");
    expect(original.getAttribute("href")).toContain(`token=${token}`);
    expect(original).not.toHaveAttribute("target", "_blank");
    expect(original).toHaveAttribute("referrerpolicy", "no-referrer");
    expect(screen.getByText(/even if the email is delayed or unavailable/)).toBeInTheDocument();
  });
});
