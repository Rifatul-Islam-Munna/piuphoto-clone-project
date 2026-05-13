import { useEffect, useMemo, useState } from "react";
import { Link, useParams } from "react-router-dom";
import {
  ArrowLeft,
  Check,
  Copy,
  Download,
  Folder,
  Image as ImageIcon,
  Images,
  Loader2,
} from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Checkbox } from "@/components/ui/checkbox";
import { GetRequestAxios } from "@/api-hooks/api-hooks";

type EventImage = {
  _id?: string;
  id?: string;
  imageUrl?: string;
  isEnhanced?: boolean;
  createdAt?: string;
  eventId?: {
    _id?: string;
    title?: string;
    description?: string;
  } | string;
  userTakenBy?: {
    name?: string;
  } | string;
};

type EventImageResponse = {
  data?: EventImage[];
};

type PublicAlbum = {
  _id?: string;
  id?: string;
  title?: string;
  description?: string;
  imagesCount?: number;
};

type PublicAlbumResponse = {
  data?: PublicAlbum[];
};

const pageSize = 18;

const getImageId = (image: EventImage) =>
  image._id || image.id || image.imageUrl || "";

const getEventTitle = (images: EventImage[], eventId?: string) => {
  const populatedEvent = images.find(
    (image) => typeof image.eventId === "object" && image.eventId?.title,
  )?.eventId;

  return typeof populatedEvent === "object" && populatedEvent?.title
    ? populatedEvent.title
    : `Event ${eventId || ""}`;
};

const filenameFromImage = (image: EventImage, index = 0) => {
  const id = getImageId(image).slice(-8) || `${index + 1}`;
  const enhanced = image.isEnhanced ? "-enhanced" : "";
  return `event-image-${id}${enhanced}.jpg`;
};

const currentPublicUrl = (eventId: string, imageId?: string) => {
  const imagePart = imageId ? `/image/${imageId}` : "";
  return `${window.location.origin}${window.location.pathname}#/event/${eventId}${imagePart}`;
};

async function downloadImage(url: string, filename: string) {
  try {
    const response = await fetch(url, { mode: "cors" });

    if (!response.ok) {
      throw new Error("Image download failed");
    }

    const blob = await response.blob();
    const objectUrl = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = objectUrl;
    link.download = filename;
    link.click();
    URL.revokeObjectURL(objectUrl);
  } catch {
    const link = document.createElement("a");
    link.href = url;
    link.download = filename;
    link.target = "_blank";
    link.rel = "noreferrer";
    link.click();
  }
}

export default function EventPublicGallery() {
  const { eventId, albumId, imageId } = useParams();
  const [images, setImages] = useState<EventImage[]>([]);
  const [albums, setAlbums] = useState<PublicAlbum[]>([]);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [visibleCount, setVisibleCount] = useState(pageSize);
  const [isLoading, setIsLoading] = useState(true);
  const [isDownloading, setIsDownloading] = useState(false);

  useEffect(() => {
    let isMounted = true;

    const loadImages = async () => {
      if (!eventId) {
        return;
      }

      setIsLoading(true);
      const [imageResponse, imageError] = await GetRequestAxios<EventImageResponse>(
        `/eventImage/public?eventId=${eventId}${albumId ? `&albumId=${albumId}` : ""}`,
        {
          withToken: false,
          withCredentials: false,
          redirectOnUnauthorized: false,
        },
      );
      const [albumResponse] = albumId
        ? [null]
        : await GetRequestAxios<PublicAlbumResponse>(
            `/album/public?eventId=${eventId}`,
            {
              withToken: false,
              withCredentials: false,
              redirectOnUnauthorized: false,
            },
          );

      if (!isMounted) {
        return;
      }

      if (imageError) {
        toast.error(imageError.message || "Failed to load event images");
        setImages([]);
      } else {
        setImages(imageResponse?.data || []);
      }
      setAlbums(albumResponse?.data || []);

      setIsLoading(false);
    };

    loadImages();

    return () => {
      isMounted = false;
    };
  }, [albumId, eventId]);

  useEffect(() => {
    const onScroll = () => {
      const nearBottom =
        window.innerHeight + window.scrollY >= document.body.offsetHeight - 500;

      if (nearBottom) {
        setVisibleCount((count) => Math.min(count + pageSize, images.length));
      }
    };

    window.addEventListener("scroll", onScroll);
    return () => window.removeEventListener("scroll", onScroll);
  }, [images.length]);

  const eventTitle = useMemo(
    () => getEventTitle(images, eventId),
    [eventId, images],
  );

  const visibleImages = images.slice(0, visibleCount);
  const focusedImage = imageId
    ? images.find((image) => getImageId(image) === imageId)
    : null;
  const hasMore = visibleCount < images.length;
  const selectedImages = images.filter((image) =>
    selectedIds.has(getImageId(image)),
  );

  const toggleImage = (id: string) => {
    setSelectedIds((current) => {
      const next = new Set(current);

      if (next.has(id)) {
        next.delete(id);
      } else {
        next.add(id);
      }

      return next;
    });
  };

  const copyImageLink = async (id: string) => {
    if (!eventId) {
      return;
    }

    await navigator.clipboard.writeText(currentPublicUrl(eventId, id));
    toast.success("Single image link copied");
  };

  const downloadImages = async (targetImages: EventImage[]) => {
    const downloadable = targetImages.filter((image) => image.imageUrl);

    if (!downloadable.length) {
      toast.error("No images available to download");
      return;
    }

    setIsDownloading(true);

    for (const [index, image] of downloadable.entries()) {
      await downloadImage(image.imageUrl!, filenameFromImage(image, index));
    }

    setIsDownloading(false);
    toast.success(
      downloadable.length === 1
        ? "Image download started"
        : "Image downloads started",
    );
  };

  if (imageId) {
    return (
      <main className="min-h-screen bg-background">
        <div className="mx-auto flex w-full max-w-6xl flex-col gap-5 px-4 py-6 sm:px-6 lg:px-8">
          <div className="flex items-center justify-between gap-3">
            <Button asChild variant="outline">
              <Link to={`/event/${eventId}`}>
                <ArrowLeft className="mr-2 h-4 w-4" />
                Gallery
              </Link>
            </Button>
            {focusedImage?.imageUrl && (
              <Button
                onClick={() => downloadImages([focusedImage])}
                disabled={isDownloading}
              >
                {isDownloading ? (
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                ) : (
                  <Download className="mr-2 h-4 w-4" />
                )}
                Download
              </Button>
            )}
          </div>

          {isLoading ? (
            <div className="flex min-h-96 items-center justify-center">
              <Loader2 className="h-10 w-10 animate-spin text-muted-foreground" />
            </div>
          ) : focusedImage?.imageUrl ? (
            <div className="overflow-hidden rounded-lg border bg-card">
              <img
                src={focusedImage.imageUrl}
                alt="Shared event image"
                className="max-h-[78vh] w-full object-contain"
              />
            </div>
          ) : (
            <div className="flex min-h-96 flex-col items-center justify-center rounded-lg border border-dashed text-center">
              <ImageIcon className="mb-3 h-12 w-12 text-muted-foreground" />
              <h1 className="text-xl font-semibold">Image not found</h1>
              <p className="text-muted-foreground">
                This image link may be expired or removed.
              </p>
            </div>
          )}
        </div>
      </main>
    );
  }

  return (
    <main className="min-h-screen bg-background">
      <div className="mx-auto flex w-full max-w-7xl flex-col gap-6 px-4 py-6 sm:px-6 lg:px-8">
        <section className="flex flex-col gap-4 border-b pb-5 lg:flex-row lg:items-end lg:justify-between">
          <div>
            <div className="mb-2 flex items-center gap-2">
              <Badge variant="outline">
                <Images className="mr-1 h-3.5 w-3.5" />
                Public Gallery
              </Badge>
              <Badge variant="secondary">{images.length} images</Badge>
              {!albumId && albums.length > 0 && (
                <Badge variant="secondary">{albums.length} albums</Badge>
              )}
            </div>
            <h1 className="text-2xl font-bold sm:text-3xl">{eventTitle}</h1>
            <p className="mt-1 max-w-2xl text-sm text-muted-foreground">
              {albumId
                ? "Album images are ready to view and download."
                : "Open an album folder or browse the full event set."}
            </p>
          </div>

          <div className="flex flex-wrap gap-2">
            <Button
              variant="outline"
              onClick={() => setSelectedIds(new Set(images.map(getImageId)))}
              disabled={!images.length}
            >
              <Check className="mr-2 h-4 w-4" />
              Select All
            </Button>
            <Button
              variant="outline"
              onClick={() => setSelectedIds(new Set())}
              disabled={!selectedIds.size}
            >
              Clear
            </Button>
            <Button
              onClick={() => downloadImages(selectedImages)}
              disabled={!selectedImages.length || isDownloading}
            >
              {isDownloading ? (
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
              ) : (
                <Download className="mr-2 h-4 w-4" />
              )}
              Download Selected
            </Button>
            <Button
              onClick={() => downloadImages(images)}
              disabled={!images.length || isDownloading}
            >
              <Download className="mr-2 h-4 w-4" />
              Download All
            </Button>
          </div>
        </section>

        {isLoading ? (
          <div className="flex min-h-96 items-center justify-center">
            <Loader2 className="h-10 w-10 animate-spin text-muted-foreground" />
          </div>
        ) : images.length === 0 && (albumId || albums.length === 0) ? (
          <div className="flex min-h-96 flex-col items-center justify-center rounded-lg border border-dashed text-center">
            <ImageIcon className="mb-3 h-12 w-12 text-muted-foreground" />
            <h2 className="text-xl font-semibold">No images uploaded yet</h2>
            <p className="text-muted-foreground">
              Event images will appear here after photographers upload them.
            </p>
          </div>
        ) : (
          <>
            {!albumId && albums.length > 0 && (
              <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
                {albums.map((album) => {
                  const id = album._id || album.id || "";

                  return (
                    <Link key={id} to={`/event/${eventId}/album/${id}`}>
                      <Card className="h-full transition-colors hover:bg-muted/50">
                        <CardContent className="flex items-center gap-4 p-4">
                          <div className="flex h-14 w-14 items-center justify-center rounded-md bg-primary/10 text-primary">
                            <Folder className="h-8 w-8" />
                          </div>
                          <div className="min-w-0">
                            <h2 className="truncate font-semibold">
                              {album.title || "Untitled album"}
                            </h2>
                            <p className="text-sm text-muted-foreground">
                              {album.imagesCount || 0} images
                            </p>
                          </div>
                        </CardContent>
                      </Card>
                    </Link>
                  );
                })}
              </section>
            )}

            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
              {visibleImages.map((image, index) => {
                const id = getImageId(image);
                const isSelected = selectedIds.has(id);

                return (
                  <Card key={id} className="overflow-hidden">
                    <div className="relative aspect-[4/3] bg-muted">
                      <img
                        src={image.imageUrl}
                        alt={`Event image ${index + 1}`}
                        className="h-full w-full object-cover"
                        loading="lazy"
                      />
                      <label className="absolute left-3 top-3 flex h-9 w-9 cursor-pointer items-center justify-center rounded-md bg-background/95 shadow">
                        <Checkbox
                          checked={isSelected}
                          onCheckedChange={() => toggleImage(id)}
                          aria-label="Select image"
                        />
                      </label>
                      {image.isEnhanced && (
                        <Badge className="absolute right-3 top-3">Enhanced</Badge>
                      )}
                    </div>
                    <CardContent className="flex items-center justify-between gap-2 p-3">
                      <Button asChild variant="outline" size="sm">
                        <Link to={`/event/${eventId}/image/${id}`}>Open</Link>
                      </Button>
                      <div className="flex gap-2">
                        <Button
                          variant="outline"
                          size="sm"
                          onClick={() => copyImageLink(id)}
                        >
                          <Copy className="h-4 w-4" />
                        </Button>
                        <Button
                          size="sm"
                          onClick={() => downloadImages([image])}
                          disabled={!image.imageUrl || isDownloading}
                        >
                          <Download className="h-4 w-4" />
                        </Button>
                      </div>
                    </CardContent>
                  </Card>
                );
              })}
            </div>

            {hasMore && (
              <div className="flex justify-center">
                <Button
                  variant="outline"
                  onClick={() =>
                    setVisibleCount((count) =>
                      Math.min(count + pageSize, images.length),
                    )
                  }
                >
                  Load More
                </Button>
              </div>
            )}
          </>
        )}
      </div>
    </main>
  );
}

