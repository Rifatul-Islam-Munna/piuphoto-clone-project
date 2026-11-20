import { render, screen, within } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { PhotoMasonry } from "./PhotoMasonry";

describe("responsive continuous photo masonry", () => {
  it("packs every photo in the same multi-column gallery, without row slots or time groups", () => {
    render(
      <PhotoMasonry id="gallery-grid">
        {Array.from({ length: 150 }, (_, i) => (
          <article key={i} aria-label={`Photo ${i + 1}`}>
            <img
              src={`/fake/photo-${i + 1}.jpg`}
              alt={`Event photo ${i + 1}`}
              className="block h-auto w-full"
            />
          </article>
        ))}
      </PhotoMasonry>,
    );
    const grid = screen.getByTestId("photo-masonry-gallery");
    expect(grid.id).toBe("gallery-grid");
    expect(grid).toHaveClass("columns-2", "md:columns-3", "xl:columns-4");
    expect(grid).toHaveClass("gap-[3px]");
    expect(grid.className).toContain("[&>*]:break-inside-avoid-column");
    expect(grid.className).toContain("[&>*]:block");
    expect(grid.className).not.toContain("inline-block");
    expect(within(grid).getAllByRole("article")).toHaveLength(150);
    expect(within(grid).getAllByRole("img")).toHaveLength(150);
    expect(grid.querySelectorAll("[style*='grid-row'], [style*='height']").length).toBe(0);
  });
});
