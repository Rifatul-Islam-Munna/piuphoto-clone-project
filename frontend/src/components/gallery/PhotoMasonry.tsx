import type { ReactNode } from "react";

/**
 * Gapless masonry matching the Pixieset-style gallery: photos keep their
 * natural proportions and fill independent columns without fixed row heights.
 * No JS image measuring or runtime masonry dependency is required.
 */
export const PHOTO_MASONRY_GAP = "5px";

export function PhotoMasonry({
  children,
  className,
  id,
}: {
  children: ReactNode;
  className?: string;
  id?: string;
}) {
  return (
    <div
      id={id}
      data-testid="photo-masonry-gallery"
      className={[
        // Each column packs photos top-to-bottom. Only a tiny 3px gutter
        // remains; no row tracks or time-group separators can create holes.
        "columns-2 gap-[3px] md:columns-3 xl:columns-4",
        // Block tiles avoid inline-line-height whitespace between images.
        "[&>*]:mb-[3px] [&>*]:block [&>*]:w-full",
        "[&>*]:break-inside-avoid-column",
        className || "",
      ].join(" ")}
    >
      {children}
    </div>
  );
}
