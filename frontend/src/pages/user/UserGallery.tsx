import { useMemo, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Loader2, Share2, Sparkles, Trash2 } from "lucide-react";
import { toast } from "sonner";
import UserLayout from "./UserLayout";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { DeleteRequestAxios, PostRequestAxios } from "@/api-hooks/api-hooks";
import { useQueryWrapper } from "@/api-hooks/react-query-wrapper";

type EventType = {
  _id: string;
  title: string;
};

type EventsResponse = {
  data: EventType[];
};

type ImageType = {
  _id: string;
  imageUrl: string;
  isEnhanced?: boolean;
  createdAt?: string;
};

type ImagesResponse = {
  data: ImageType[];
  page: number;
  totalPages: number;
  hasNextPage: boolean;
  hasPreviousPage: boolean;
};

export default function UserGallery() {
  const queryClient = useQueryClient();
  const [eventId, setEventId] = useState("");
  const [page, setPage] = useState(1);
  const [enhanceImage, setEnhanceImage] = useState<ImageType | null>(null);
  const [prompt, setPrompt] = useState("");

  const eventsQuery = useQueryWrapper<EventsResponse>(
    ["user-gallery-events"],
    "/event/my-events?page=1&limit=100",
    { withToken: true, withCredentials: true },
  );

  const events = eventsQuery.data?.data || [];
  const selectedEventId = eventId || events[0]?._id || "";

  const imagesQuery = useQueryWrapper<ImagesResponse>(
    ["user-gallery-images", selectedEventId, page],
    selectedEventId
      ? `/eventImage/get-all?eventId=${selectedEventId}&page=${page}&limit=18`
      : "/eventImage/get-all?page=1&limit=18",
    {
      withToken: true,
      withCredentials: true,
      enabled: !!selectedEventId,
    },
  );

  const selectedEvent = useMemo(
    () => events.find((event) => event._id === selectedEventId),
    [events, selectedEventId],
  );

  const deleteMutation = useMutation({
    mutationFn: async (id: string) => {
      const [response, error] = await DeleteRequestAxios<{ message: string }>(
        `/eventImage/delete?id=${id}`,
        { withToken: true, withCredentials: true },
      );
      if (error || !response) throw new Error(error?.message || "Delete failed");
      return response;
    },
    onSuccess: () => {
      toast.success("Image deleted");
      queryClient.invalidateQueries({ queryKey: ["user-gallery-images"] });
    },
    onError: (error: Error) => toast.error(error.message),
  });

  const enhanceMutation = useMutation({
    mutationFn: async () => {
      if (!enhanceImage) return null;
      const [response, error] = await PostRequestAxios<{
        skipped?: boolean;
        message: string;
      }>(
        "/eventImage/enhance",
        {
          id: enhanceImage._id,
          ...(prompt.trim() ? { prompt: prompt.trim() } : {}),
        },
        { withToken: true, withCredentials: true },
      );
      if (error || !response) throw new Error(error?.message || "Enhance failed");
      return response;
    },
    onSuccess: (response) => {
      if (response?.skipped) {
        toast.error("Enhance skipped. Not enough credits.");
      } else {
        toast.success("Image enhanced");
      }
      setEnhanceImage(null);
      setPrompt("");
      queryClient.invalidateQueries({ queryKey: ["user-gallery-images"] });
    },
    onError: (error: Error) => toast.error(error.message),
  });

  const shareImage = async (image: ImageType) => {
    if (navigator.share) {
      await navigator.share({ url: image.imageUrl });
      return;
    }
    await navigator.clipboard.writeText(image.imageUrl);
    toast.success("Image URL copied");
  };

  return (
    <UserLayout>
      <div className="space-y-6">
        <div className="flex flex-col gap-4 md:flex-row md:items-end md:justify-between">
          <div>
            <h1 className="text-2xl font-bold">Gallery</h1>
            <p className="text-muted-foreground">
              Filter event images, share, delete, or enhance.
            </p>
          </div>
          <div className="w-full md:w-72">
            <Label>Event</Label>
            <Select
              value={selectedEventId}
              onValueChange={(value) => {
                setEventId(value);
                setPage(1);
              }}
            >
              <SelectTrigger>
                <SelectValue placeholder="Select event" />
              </SelectTrigger>
              <SelectContent>
                {events.map((event) => (
                  <SelectItem key={event._id} value={event._id}>
                    {event.title}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        </div>

        <Card>
          <CardHeader>
            <CardTitle>{selectedEvent?.title || "Event images"}</CardTitle>
            <CardDescription>Images for selected event.</CardDescription>
          </CardHeader>
          <CardContent>
            {imagesQuery.isLoading ? (
              <div className="flex h-48 items-center justify-center">
                <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
              </div>
            ) : !selectedEventId ? (
              <div className="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
                No event found.
              </div>
            ) : (imagesQuery.data?.data || []).length === 0 ? (
              <div className="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
                No images found.
              </div>
            ) : (
              <div className="grid gap-4 md:grid-cols-3">
                {(imagesQuery.data?.data || []).map((image) => (
                  <div key={image._id} className="overflow-hidden rounded-lg border">
                    <img
                      src={image.imageUrl}
                      alt="Event"
                      className="aspect-square w-full object-cover"
                    />
                    <div className="flex items-center justify-between p-2">
                      <span className="text-xs text-muted-foreground">
                        {image.isEnhanced ? "Enhanced" : "Original"}
                      </span>
                      <div className="flex gap-1">
                        <Button variant="ghost" size="icon" onClick={() => shareImage(image)}>
                          <Share2 className="h-4 w-4" />
                        </Button>
                        <Button
                          variant="ghost"
                          size="icon"
                          onClick={() => setEnhanceImage(image)}
                        >
                          <Sparkles className="h-4 w-4" />
                        </Button>
                        <Button
                          variant="ghost"
                          size="icon"
                          onClick={() => deleteMutation.mutate(image._id)}
                        >
                          <Trash2 className="h-4 w-4 text-destructive" />
                        </Button>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            )}

            {imagesQuery.data && imagesQuery.data.totalPages > 1 ? (
              <div className="mt-4 flex items-center justify-end gap-2">
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => setPage((value) => Math.max(1, value - 1))}
                  disabled={!imagesQuery.data.hasPreviousPage}
                >
                  Previous
                </Button>
                <span className="text-sm text-muted-foreground">
                  Page {imagesQuery.data.page} of {imagesQuery.data.totalPages}
                </span>
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => setPage((value) => value + 1)}
                  disabled={!imagesQuery.data.hasNextPage}
                >
                  Next
                </Button>
              </div>
            ) : null}
          </CardContent>
        </Card>

        <Dialog open={!!enhanceImage} onOpenChange={(open) => !open && setEnhanceImage(null)}>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Enhance Image</DialogTitle>
            </DialogHeader>
            <div className="space-y-2">
              <Label>Custom prompt</Label>
              <Input
                value={prompt}
                onChange={(event) => setPrompt(event.target.value)}
                placeholder="Optional. Needs custom.enhancer plan feature."
              />
            </div>
            <DialogFooter>
              <Button variant="outline" onClick={() => setEnhanceImage(null)}>
                Cancel
              </Button>
              <Button onClick={() => enhanceMutation.mutate()} disabled={enhanceMutation.isPending}>
                {enhanceMutation.isPending ? (
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                ) : (
                  <Sparkles className="mr-2 h-4 w-4" />
                )}
                Enhance
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </div>
    </UserLayout>
  );
}
