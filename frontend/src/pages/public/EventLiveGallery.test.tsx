import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { FindMeDialog } from "./EventLiveGallery";

describe("FindMeDialog", () => {
  it("offers both camera capture and file upload", () => {
    const onCamera = vi.fn();
    const onUpload = vi.fn();

    render(
      <FindMeDialog
        busy={false}
        onClose={vi.fn()}
        onCamera={onCamera}
        onUpload={onUpload}
      />,
    );

    fireEvent.click(screen.getByRole("button", { name: "Take a photo" }));
    fireEvent.click(screen.getByRole("button", { name: "Upload a selfie" }));

    expect(onCamera).toHaveBeenCalledOnce();
    expect(onUpload).toHaveBeenCalledOnce();
    expect(screen.getByText("Find all your photos")).toBeInTheDocument();
  });
});
