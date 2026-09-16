import { useMemo, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import {
  Check,
  Eye,
  EyeOff,
  Loader2,
  Search,
  ShieldCheck,
  Sparkles,
  ThumbsDown,
  ThumbsUp,
  WandSparkles,
} from "lucide-react";
import { toast } from "sonner";
import WorkspaceLayout from "@/components/WorkspaceLayout";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  GetRequestAxios,
  PatchRequestAxios,
  PostRequestAxios,
} from "@/api-hooks/api-hooks";
import { useQueryWrapper } from "@/api-hooks/react-query-wrapper";

type EventType = { _id: string; title: string };
type EventsResponse = { data: EventType[] };
type AlbumType = { _id: string; title: string };
type ImageType = {
  _id: string;
  imageUrl: string;
  isEnhanced?: boolean;
  isPublished?: boolean;
  mediaType?: "photo" | "video";
  aiRecommended?: boolean;
  aiReviewStatus?: "pending" | "approved" | "flagged" | "rejected";
  aiQualityScore?: number;
  aiBlurScore?: number;
  aiReviewReasons?: string[];
  aiDescription?: string;
  aiTags?: string[];
  recognizedNumbers?: string[];
  outfitTags?: string[];
  duplicateOfId?: string;
  reviewerDecision?: string;
  enhancedFromId?: string;
};
type EnhancementJob = {
  _id: string;
  status: "pending" | "completed" | "failed";
  error?: string;
  sourceEventImageId?: { _id?: string; imageUrl?: string } | string;
};
type EnhancementJobsResponse = { data: EnhancementJob[]; totalItems: number };

type ImagesResponse = {
  data: ImageType[];
  page: number;
  totalPages: number;
  hasNextPage: boolean;
  hasPreviousPage: boolean;
};

const enhancePresets = [
  "Colour Enhancement",
  "Skin Beautification",
  "Facial Beautification",
  "Body Beautification",
  "Vehicle Privacy Protection",
];

export default function Phase2Gallery() {
  const queryClient = useQueryClient();
  const [eventId, setEventId] = useState("");
  const [page, setPage] = useState(1);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [preset, setPreset] = useState(enhancePresets[0]);
  const [moveAlbumId, setMoveAlbumId] = useState("");
  const [searchText, setSearchText] = useState("");
  const [searchType, setSearchType] = useState("all");
  const [searchResults, setSearchResults] = useState<ImageType[] | null>(null);
  const [searching, setSearching] = useState(false);
  const [faceFile, setFaceFile] = useState<File | null>(null);
  const [compare, setCompare] = useState<{ before: ImageType; after: ImageType } | null>(null);

  const eventsQuery = useQueryWrapper<EventsResponse>(
    ["phase2-gallery-events"],
    "/event/my-events?page=1&limit=100",
    { withToken: true, withCredentials: true },
  );
  const events = eventsQuery.data?.data || [];
  const selectedEventId = eventId || events[0]?._id || "";
  const imagesQuery = useQueryWrapper<ImagesResponse>(
    ["phase2-gallery-images", selectedEventId, page],
    selectedEventId
      ? `/eventImage/get-all?eventId=${selectedEventId}&page=${page}&limit=24`
      : "/eventImage/get-all?page=1&limit=24",
    {
      withToken: true,
      withCredentials: true,
      enabled: Boolean(selectedEventId),
    },
  );
  const jobsQuery = useQueryWrapper<EnhancementJobsResponse>(
    ["phase2-enhancement-jobs", selectedEventId],
    selectedEventId ? `/eventImage/enhancement-jobs?eventId=${selectedEventId}` : "/eventImage/enhancement-jobs",
    { withToken: true, withCredentials: true, enabled: Boolean(selectedEventId), refetchInterval: 5000 },
  );
  const albumsQuery = useQueryWrapper<{ data: AlbumType[] }>(
    ["phase2-gallery-albums", selectedEventId],
    selectedEventId ? `/album/get-all?eventId=${selectedEventId}` : "/album/get-all",
    { withToken: true, withCredentials: true, enabled: Boolean(selectedEventId) },
  );  const jobByImageId = useMemo(() => {
    const map = new Map<string, EnhancementJob>();
    for (const job of jobsQuery.data?.data || []) {
      const sourceId = typeof job.sourceEventImageId === "object" ? job.sourceEventImageId?._id : job.sourceEventImageId;
      if (sourceId && !map.has(sourceId)) map.set(sourceId, job);
    }
    return map;
  }, [jobsQuery.data?.data]);

  const selectedEvent = useMemo(
    () => events.find((event) => event._id === selectedEventId),
    [events, selectedEventId],
  );
  const visibleImages = searchResults ?? imagesQuery.data?.data ?? [];
  const selectedIds = [...selected];

  const refresh = () => {
    setSearchResults(null);
    queryClient.invalidateQueries({ queryKey: ["phase2-gallery-images"] });
    queryClient.invalidateQueries({ queryKey: ["phase2-enhancement-jobs"] });
  };

  const openCompare = async (after: ImageType) => {
    if (!after.enhancedFromId) return;
    let before = (imagesQuery.data?.data || []).find((item) => item._id === after.enhancedFromId);
    if (!before) {
      const [data, error] = await GetRequestAxios<ImageType>(`/eventImage/get-one?id=${after.enhancedFromId}`, { withToken: true, withCredentials: true });
      if (error || !data) { toast.error(error?.message || "Original could not be loaded"); return; }
      before = data;
    }
    setCompare({ before, after });
  };

  const bulkPublish = useMutation({
    mutationFn: async (isPublished: boolean) => {
      if (!selectedIds.length) throw new Error("Select at least one photo");
      const [response, error] = await PatchRequestAxios<{ updated: number }>(
        "/eventImage/publish-batch",
        { ids: selectedIds, isPublished },
        { withToken: true, withCredentials: true },
      );
      if (error || !response)
        throw new Error(error?.message || "Bulk publish failed");
      return { response, isPublished };
    },
    onSuccess: ({ response, isPublished }) => {
      toast.success(
        `${response.updated} photos ${isPublished ? "published" : "hidden"}`,
      );
      setSelected(new Set());
      refresh();
    },
    onError: (error: Error) => toast.error(error.message),
  });

  const moveCategory = useMutation({
    mutationFn: async () => {
      if (!selectedIds.length) throw new Error("Select at least one photo");
      if (!moveAlbumId) throw new Error("Choose a category");
      const results = await Promise.all(
        selectedIds.map((id) =>
          PatchRequestAxios(
            `/eventImage/update?id=${id}`,
            { albumId: moveAlbumId },
            { withToken: true, withCredentials: true },
          ),
        ),
      );
      const failed = results.find(([response, error]) => error || !response);
      if (failed) throw new Error(failed[1]?.message || "Could not move selected photos");
      return results.length;
    },
    onSuccess: (count) => {
      toast.success(`${count} photos moved to category`);
      setSelected(new Set());
      refresh();
    },
    onError: (error: Error) => toast.error(error.message),
  });
  const bulkEnhance = useMutation({
    mutationFn: async () => {
      if (!selectedIds.length) throw new Error("Select at least one photo");
      const [response, error] = await PostRequestAxios<{
        completed: number;
        failed: number;
      }>(
        "/eventImage/enhance-batch",
        { ids: selectedIds, prompt: preset },
        { withToken: true, withCredentials: true },
      );
      if (error || !response)
        throw new Error(error?.message || "Batch enhance failed");
      return response;
    },
    onSuccess: (response) => {
      toast.success(
        `${response.completed} enhancement jobs started/completed${response.failed ? `, ${response.failed} failed` : ""}`,
      );
      setSelected(new Set());
      refresh();
    },
    onError: (error: Error) => toast.error(error.message),
  });

  const retryEnhancement = useMutation({
    mutationFn: async (jobId: string) => {
      const [response, error] = await PostRequestAxios(
        "/eventImage/enhancement-jobs/retry", { jobId },
        { withToken: true, withCredentials: true },
      );
      if (error || !response) throw new Error(error?.message || "Enhancement retry failed");
      return response;
    },
    onSuccess: () => { toast.success("Enhancement retry started"); refresh(); },
    onError: (error: Error) => toast.error(error.message),
  });

  const analyze = useMutation({
    mutationFn: async () => {
      const ids = selectedIds.length
        ? selectedIds
        : visibleImages.map((image) => image._id);
      if (!ids.length) throw new Error("No photos to analyze");
      const [response, error] = await PostRequestAxios<{
        completed: number;
        failed: number;
      }>(
        "/eventImage/ai/analyze",
        { ids },
        { withToken: true, withCredentials: true },
      );
      if (error || !response)
        throw new Error(error?.message || "AI review failed");
      return response;
    },
    onSuccess: (response) => {
      toast.success(`AI reviewed ${response.completed} photos`);
      refresh();
    },
    onError: (error: Error) => toast.error(error.message),
  });

  const review = useMutation({
    mutationFn: async ({
      id,
      decision,
    }: {
      id: string;
      decision: "approve" | "reject" | "clear";
    }) => {
      const [response, error] = await PatchRequestAxios(
        "/eventImage/ai/review",
        { id, decision },
        { withToken: true, withCredentials: true },
      );
      if (error || !response)
        throw new Error(error?.message || "Review override failed");
      return response;
    },
    onSuccess: () => refresh(),
    onError: (error: Error) => toast.error(error.message),
  });

  const runSearch = async () => {
    if (!selectedEventId) return;
    if (searchType === "face") {
      if (!faceFile) {
        toast.info("Choose a selfie or face photo first.");
        return;
      }
      setSearching(true);
      const form = new FormData();
      form.append("image", faceFile);
      const [response, error] = await PostRequestAxios<{ data: ImageType[] }>(
        `/eventImage/my-picture?eventId=${encodeURIComponent(selectedEventId)}&limit=500`,
        form,
        { withToken: true, withCredentials: true, headers: { "Content-Type": "multipart/form-data" } },
      );
      setSearching(false);
      if (error) {
        toast.error(error.message);
        return;
      }
      setSearchResults(response?.data || []);
      return;
    }
    const query = searchText.trim();
    if (!query) {
      setSearchResults(null);
      return;
    }
    setSearching(true);
    const qs = new URLSearchParams({
      eventId: selectedEventId,
      query,
      type: searchType,
      limit: "500",
    });
    const [response, error] = await GetRequestAxios<{ data: ImageType[] }>(
      `/eventImage/ai/search?${qs.toString()}`,
      { withToken: true, withCredentials: true },
    );
    setSearching(false);
    if (error) {
      toast.error(error.message);
      return;
    }
    setSearchResults(response?.data || []);
  };

  const toggleAll = () => {
    if (visibleImages.length && selected.size === visibleImages.length) {
      setSelected(new Set());
    } else {
      setSelected(new Set(visibleImages.map((image) => image._id)));
    }
  };
  const toggleOne = (id: string) => {
    setSelected((current) => {
      const next = new Set(current);
      next.has(id) ? next.delete(id) : next.add(id);
      return next;
    });
  };

  return (
    <WorkspaceLayout>
      <div className="space-y-6">
        <div className="flex flex-col gap-4 xl:flex-row xl:items-end xl:justify-between">
          <div>
            <p className="text-sm font-medium text-muted-foreground">
              Phase 2 AI workflow
            </p>
            <h1 className="text-2xl font-bold">AI Review, Enhance & Publish</h1>
            <p className="mt-1 text-sm text-muted-foreground">
              Cull blur/duplicates, search photo metadata, batch enhance,
              review, and publish while the event is live.
            </p>
          </div>
          <div className="w-full space-y-2 xl:w-72">
            <Label>Event</Label>
            <Select
              value={selectedEventId}
              onValueChange={(value) => {
                setEventId(value);
                setPage(1);
                setSelected(new Set());
                setSearchResults(null);
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
            <Button
              variant="outline"
              className="w-full"
              disabled={!selectedEventId}
              onClick={() => {
                if (selectedEventId) {
                  const role = JSON.parse(localStorage.getItem("user") || "{}").role;
                  window.location.hash = role === "photographer" ? `#/photographer/event/${selectedEventId}/experience` : `#/planner/event/${selectedEventId}/experience`;
                }
              }}
            >
              <ShieldCheck className="mr-2 h-4 w-4" />
              Privacy & gallery password
            </Button>
          </div>
        </div>

        <Card>
          <CardContent className="space-y-4 p-4">
            <div className="grid gap-3 lg:grid-cols-[1fr_180px_auto_auto]">
              {searchType === "face" ? (
                <Input
                  type="file"
                  accept="image/jpeg,image/png,image/webp,image/heic,image/heif"
                  onChange={(event) => setFaceFile(event.target.files?.[0] || null)}
                />
              ) : (
                <Input
                  value={searchText}
                  onChange={(event) => setSearchText(event.target.value)}
                  onKeyDown={(event) => event.key === "Enter" && void runSearch()}
                  placeholder="Search number 204, red jacket, bride on stage..."
                />
              )}
              <Select value={searchType} onValueChange={setSearchType}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">All AI metadata</SelectItem>
                  <SelectItem value="number">Number recognition</SelectItem>
                  <SelectItem value="semantic">Semantic</SelectItem>
                  <SelectItem value="outfit">Outfit</SelectItem>
                  <SelectItem value="face">Face</SelectItem>
                </SelectContent>
              </Select>
              <Button
                variant="outline"
                onClick={() => void runSearch()}
                disabled={searching}
              >
                {searching ? (
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                ) : (
                  <Search className="mr-2 h-4 w-4" />
                )}
                Search
              </Button>
              {searchResults ? (
                <Button
                  variant="ghost"
                  onClick={() => {
                    setSearchResults(null);
                    setSearchText("");
                  }}
                >
                  Clear search
                </Button>
              ) : null}
            </div>

            <div className="flex flex-wrap items-center gap-2 border-t pt-4">
              <Button size="sm" variant="outline" onClick={toggleAll}>
                <Check className="mr-2 h-4 w-4" />
                {selected.size === visibleImages.length && visibleImages.length
                  ? "Clear selection"
                  : "Select page"}
              </Button>
              <Badge variant="secondary">{selected.size} selected</Badge>
              <Button
                size="sm"
                variant="outline"
                disabled={!selected.size || bulkPublish.isPending}
                onClick={() => bulkPublish.mutate(true)}
              >
                <Eye className="mr-2 h-4 w-4" />
                Publish
              </Button>
              <Button
                size="sm"
                variant="outline"
                disabled={!selected.size || bulkPublish.isPending}
                onClick={() => bulkPublish.mutate(false)}
              >
                <EyeOff className="mr-2 h-4 w-4" />
                Hide
              </Button>
              <Select value={moveAlbumId} onValueChange={setMoveAlbumId}>
                <SelectTrigger className="h-9 w-48">
                  <SelectValue placeholder="Move to category" />
                </SelectTrigger>
                <SelectContent>
                  {(albumsQuery.data?.data || []).map((album) => (
                    <SelectItem key={album._id} value={album._id}>
                      {album.title}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <Button
                size="sm"
                variant="outline"
                disabled={!selected.size || !moveAlbumId || moveCategory.isPending}
                onClick={() => moveCategory.mutate()}
              >
                {moveCategory.isPending ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : null}
                Move category
              </Button>              <Select value={preset} onValueChange={setPreset}>
                <SelectTrigger className="h-9 w-56">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {enhancePresets.map((value) => (
                    <SelectItem key={value} value={value}>
                      {value}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <Button
                size="sm"
                disabled={!selected.size || bulkEnhance.isPending}
                onClick={() => bulkEnhance.mutate()}
              >
                {bulkEnhance.isPending ? (
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                ) : (
                  <WandSparkles className="mr-2 h-4 w-4" />
                )}
                Batch enhance
              </Button>
              <Button
                size="sm"
                variant="secondary"
                disabled={analyze.isPending || !visibleImages.length}
                onClick={() => analyze.mutate()}
              >
                {analyze.isPending ? (
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                ) : (
                  <Sparkles className="mr-2 h-4 w-4" />
                )}
                AI review {selected.size ? "selected" : "page"}
              </Button>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>{selectedEvent?.title || "Event photos"}</CardTitle>
          </CardHeader>
          <CardContent>
            {imagesQuery.isLoading && !searchResults ? (
              <div className="flex h-52 items-center justify-center">
                <Loader2 className="h-7 w-7 animate-spin" />
              </div>
            ) : !visibleImages.length ? (
              <div className="rounded-xl border border-dashed p-10 text-center text-sm text-muted-foreground">
                No photos found.
              </div>
            ) : (
              <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
                {visibleImages.map((image) => (
                  <div
                    key={image._id}
                    className="overflow-hidden rounded-xl border bg-background"
                  >
                    <div className="relative aspect-[4/3] bg-muted">
                      {image.mediaType === "video" ? (
                        <video src={image.imageUrl} controls preload="metadata" className="h-full w-full object-cover" />
                      ) : (
                        <img src={image.imageUrl} alt="" className="h-full w-full object-cover" />
                      )}
                      <label className="absolute left-3 top-3 rounded-full bg-background/90 p-2 shadow">
                        <Checkbox
                          checked={selected.has(image._id)}
                          onCheckedChange={() => toggleOne(image._id)}
                        />
                      </label>
                      <div className="absolute right-3 top-3 flex flex-wrap justify-end gap-1">
                        <Badge
                          variant={
                            image.isPublished === false
                              ? "secondary"
                              : "default"
                          }
                        >
                          {image.isPublished === false ? "Hidden" : "Live"}
                        </Badge>
                        {image.mediaType === "video" ? <Badge variant="outline">Video</Badge> : null}
                        {image.isEnhanced ? <Badge>Enhanced</Badge> : null}
                        {image.aiRecommended ? <Badge variant="secondary">Recommended</Badge> : null}
                      </div>
                    </div>
                    <div className="space-y-3 p-3">
                      <div className="flex flex-wrap items-center gap-2">
                        <ReviewBadge status={image.aiReviewStatus} />
                        {image.aiQualityScore !== undefined ? (
                          <Badge variant="outline">
                            Quality {image.aiQualityScore}
                          </Badge>
                        ) : null}
                        {image.duplicateOfId ? (
                          <Badge variant="destructive">Duplicate</Badge>
                        ) : null}
                        {jobByImageId.get(image._id) ? (
                          <Badge variant={jobByImageId.get(image._id)?.status === "failed" ? "destructive" : "outline"}>
                            Enhance {jobByImageId.get(image._id)?.status}
                          </Badge>
                        ) : null}
                      </div>
                      {jobByImageId.get(image._id)?.status === "failed" ? (
                        <div className="flex items-center justify-between gap-2 rounded-lg border border-destructive/30 p-2">
                          <p className="line-clamp-1 text-xs text-destructive">{jobByImageId.get(image._id)?.error || "Enhancement failed"}</p>
                          <Button size="sm" variant="outline" disabled={retryEnhancement.isPending} onClick={() => retryEnhancement.mutate(jobByImageId.get(image._id)!._id)}>Retry</Button>
                        </div>
                      ) : null}
                      {image.aiReviewReasons?.length ? (
                        <p className="text-xs text-destructive">
                          {image.aiReviewReasons.join(" · ")}
                        </p>
                      ) : null}
                      {image.aiDescription ? (
                        <p className="line-clamp-2 text-xs text-muted-foreground">
                          {image.aiDescription}
                        </p>
                      ) : null}
                      <div className="flex flex-wrap gap-1">
                        {(image.recognizedNumbers || []).map((value) => (
                          <Badge key={`n-${value}`} variant="outline">
                            #{value}
                          </Badge>
                        ))}
                        {(image.outfitTags || []).slice(0, 4).map((value) => (
                          <Badge key={`o-${value}`} variant="secondary">
                            {value}
                          </Badge>
                        ))}
                      </div>
                      <div className="flex flex-wrap gap-2 border-t pt-3">
                        {image.isEnhanced && image.enhancedFromId ? (
                          <Button size="sm" variant="outline" onClick={() => void openCompare(image)}>Before / after</Button>
                        ) : null}
                        <Button
                          size="sm"
                          variant="outline"
                          disabled={review.isPending}
                          onClick={() =>
                            review.mutate({
                              id: image._id,
                              decision: "approve",
                            })
                          }
                        >
                          <ThumbsUp className="mr-1 h-3.5 w-3.5" />
                          Approve
                        </Button>
                        <Button
                          size="sm"
                          variant="outline"
                          disabled={review.isPending}
                          onClick={() =>
                            review.mutate({ id: image._id, decision: "reject" })
                          }
                        >
                          <ThumbsDown className="mr-1 h-3.5 w-3.5" />
                          Reject
                        </Button>
                        {image.reviewerDecision ? (
                          <Button
                            size="sm"
                            variant="ghost"
                            disabled={review.isPending}
                            onClick={() =>
                              review.mutate({
                                id: image._id,
                                decision: "clear",
                              })
                            }
                          >
                            Return to AI
                          </Button>
                        ) : null}
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            )}

            {!searchResults &&
            imagesQuery.data &&
            imagesQuery.data.totalPages > 1 ? (
              <div className="mt-5 flex items-center justify-end gap-2">
                <Button
                  variant="outline"
                  size="sm"
                  disabled={!imagesQuery.data.hasPreviousPage}
                  onClick={() => setPage((value) => Math.max(1, value - 1))}
                >
                  Previous
                </Button>
                <span className="text-sm text-muted-foreground">
                  Page {imagesQuery.data.page} / {imagesQuery.data.totalPages}
                </span>
                <Button
                  variant="outline"
                  size="sm"
                  disabled={!imagesQuery.data.hasNextPage}
                  onClick={() => setPage((value) => value + 1)}
                >
                  Next
                </Button>
              </div>
            ) : null}
          </CardContent>
        </Card>

        {compare ? (
          <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4" onClick={() => setCompare(null)}>
            <div className="w-full max-w-5xl rounded-2xl bg-background p-4" onClick={(event) => event.stopPropagation()}>
              <div className="mb-3 flex items-center justify-between"><p className="font-semibold">Before / after</p><Button variant="ghost" onClick={() => setCompare(null)}>Close</Button></div>
              <div className="grid gap-3 md:grid-cols-2">
                <div><p className="mb-2 text-xs font-semibold text-muted-foreground">ORIGINAL</p><img src={compare.before.imageUrl} alt="Original" className="max-h-[70vh] w-full rounded-xl object-contain" /></div>
                <div><p className="mb-2 text-xs font-semibold text-muted-foreground">ENHANCED</p><img src={compare.after.imageUrl} alt="Enhanced" className="max-h-[70vh] w-full rounded-xl object-contain" /></div>
              </div>
            </div>
          </div>
        ) : null}

        <div className="rounded-xl border bg-muted/30 p-4 text-sm text-muted-foreground">
          <ShieldCheck className="mr-2 inline h-4 w-4" />
          Face search remains event-scoped. Use the public/live gallery selfie
          flow for face matching; this console handles culling,
          number/semantic/outfit metadata and reviewer overrides.
        </div>
      </div>
    </WorkspaceLayout>
  );
}

function ReviewBadge({ status }: { status?: ImageType["aiReviewStatus"] }) {
  if (!status || status === "pending")
    return <Badge variant="outline">AI pending</Badge>;
  if (status === "approved") return <Badge>AI approved</Badge>;
  if (status === "rejected")
    return <Badge variant="destructive">Rejected</Badge>;
  return <Badge variant="destructive">Needs review</Badge>;
}
