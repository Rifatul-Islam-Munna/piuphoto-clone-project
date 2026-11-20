import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import EventLiveGallery from "./EventLiveGallery";

const eventId = "507f1f77bcf86cd799439011";
const imageId = "507f1f77bcf86cd799439012";

vi.mock("@/api-hooks/api-hooks", () => ({
  GetRequestAxios: async (url: string) => {
    if (url.startsWith("/gallery-access/info")) {
      return [{
        title: "Nikos event",
        visibility: "public",
        unlocked: true,
        faceSearchEnabled: true,
        requiresFaceSearch: false,
        requiresPassword: false,
        requiresPrivateLink: false,
        branding: {},
      }, null];
    }
    if (url.startsWith("/eventImage/public")) {
      return [{ data: [{
        _id: imageId,
        imageUrl: "https://images.example.test/photo.jpg",
        mediaType: "photo",
        purchaseRequired: false,
      }], storeEnabled: false }, null];
    }
    if (url.startsWith("/album/public")) return [{ data: [] }, null];
    return [null, null];
  },
  PostRequestAxios: async () => [{}, null],
  PatchRequestAxios: async () => [{}, null],
}));

class MockEventSource {
  addEventListener() {}
  close() {}
}

beforeEach(() => {
  localStorage.clear();
  vi.stubGlobal("EventSource", MockEventSource);
  Object.defineProperty(window, "showDirectoryPicker", {
    configurable: true, value: undefined,
  });
});
afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

function renderGallery(faceLink = true) {
  const path = `/event/${eventId}${faceLink ? "?face=1" : ""}`;
  return render(
    <MemoryRouter initialEntries={[path]}>
      <Routes>
        <Route path="/event/:eventId" element={<EventLiveGallery />} />
      </Routes>
    </MemoryRouter>,
  );
}

describe("optional face and mobile download choices", () => {
  it("opens a face QR link to the event gallery without requiring a selfie", async () => {
    renderGallery();
    expect(await screen.findByText("Find your photos automatically (optional)")).toBeInTheDocument();
    expect(screen.getByText("Nikos event")).toBeInTheDocument();
    expect(screen.queryByText("Create or update your global face profile")).not.toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "Set up face delivery" }));
    expect(await screen.findByText("Create or update your global face profile")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: /Continue browsing without face setup/ }));
    expect(await screen.findByText("Find your photos automatically (optional)")).toBeInTheDocument();
    expect(screen.queryByText("Create or update your global face profile")).not.toBeInTheDocument();
  });

  it("shows ZIP and per-photo saving even when folder API is unavailable", async () => {
    renderGallery(false);
    await waitFor(() => expect(screen.getByRole("button", { name: "Choose photo download format" })).toBeEnabled());
    fireEvent.click(screen.getByRole("button", { name: "Choose photo download format" }));
    expect(screen.getByText("Choose download format")).toBeInTheDocument();
    expect(screen.getByText("Save pictures individually")).toBeInTheDocument();
    expect(screen.getByText(/cannot write directly into a folder/i)).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: /Save pictures individually/ }));
    expect(await screen.findByRole("link", { name: /Save picture 1/ })).toBeInTheDocument();
    const link = screen.getByRole("link", { name: /Save picture 1/ });
    expect(link).toHaveAttribute(
      "href",
      expect.stringContaining("/public-downloads/event-photo"),
    );
    expect(link).toHaveAttribute("target", "_blank");
  });
});
