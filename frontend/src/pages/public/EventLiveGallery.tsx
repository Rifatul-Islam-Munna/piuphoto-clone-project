import {
  type ChangeEvent,
  type CSSProperties,
  type ReactNode,
  useCallback,
  useEffect,
  useRef,
  useState,
} from "react";
import { Link, useParams, useSearchParams } from "react-router-dom";
import {
  ArrowDown,
  ArrowLeft,
  Camera,
  CheckCircle2,
  ChevronLeft,
  ChevronRight,
  Copy,
  Download,
  Folder,
  Image as ImageIcon,
  Images,
  Loader2,
  Lock,
  RefreshCw,
  Search,
  Share2,
  ShieldCheck,
  ShoppingCart,
  Trash2,
  Upload,
  UserRoundSearch,
  X,
} from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import {
  GetRequestAxios,
  PatchRequestAxios,
  PostRequestAxios,
} from "@/api-hooks/api-hooks";

type Branding = {
  logoUrl?: string;
  coverUrl?: string;
  coverText?: string;
  watermarkUrl?: string;
  watermarkPosition?: string;
  watermarkOpacity?: number;
  watermarkScale?: number;
  primaryColor?: string;
  accentColor?: string;
  fontFamily?: string;
  footerText?: string;
  sponsorText?: string;
  whiteLabel?: boolean;
};

type GalleryInfo = {
  title: string;
  description?: string;
  image?: { url?: string };
  visibility: "public" | "private" | "password" | "facial";
  unlocked: boolean;
  requiresPassword: boolean;
  requiresPrivateLink: boolean;
  requiresFaceSearch: boolean;
  faceSearchEnabled: boolean;
  faceConsentRequired: boolean;
  guestNotificationsEnabled: boolean;
  emailNotificationsEnabled?: boolean;
  whatsappNotificationsEnabled?: boolean;
  facialPrivacyMode?: "off" | "hide_non_matches" | "blur_non_matches";
  branding?: Branding;
};

type GalleryImage = {
  _id?: string;
  id?: string;
  imageUrl?: string;
  isEnhanced?: boolean;
  mediaType?: "photo" | "video";
  userTakenBy?: { name?: string } | string;
  purchaseRequired?: boolean;
  storeImageId?: string;
};

type GalleryImageResponse = {
  data?: GalleryImage[];
  totalItems?: number;
  storeEnabled?: boolean;
};

type Album = {
  _id?: string;
  id?: string;
  title?: string;
  imagesCount?: number;
};

type PersonalGalleryResponse = GalleryImageResponse & {
  event?: { branding?: Branding };
  notificationPreferences?: {
    email?: string;
    whatsapp?: string;
    notifyEmail?: boolean;
    notifyWhatsapp?: boolean;
  };
};

const pageSize = 24;
const imageAccept = "image/jpeg,image/png,image/webp";
const baseUrl = import.meta.env.VITE_BASE_URL ?? "";
const imageId = (image: GalleryImage) =>
  image._id || image.id || image.imageUrl || "";
const assetUrl = (url?: string) => {
  if (!url) return "";
  return /^https?:\/\//i.test(url) ? url : `${baseUrl}${url}`;
};
const publicImageUrl = (eventId: string, id: string) =>
  `${window.location.origin}${window.location.pathname}#/event/${eventId}/image/${id}`;

const watermarkPositionClass = (position?: string) => {
  switch (position) {
    case "top_left":
      return "left-3 top-3";
    case "top_center":
      return "left-1/2 top-3 -translate-x-1/2";
    case "top_right":
      return "right-3 top-3";
    case "center_left":
      return "left-3 top-1/2 -translate-y-1/2";
    case "center":
      return "left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2";
    case "center_right":
      return "right-3 top-1/2 -translate-y-1/2";
    case "bottom_left":
      return "bottom-3 left-3";
    case "bottom_center":
      return "bottom-3 left-1/2 -translate-x-1/2";
    default:
      return "bottom-3 right-3";
  }
};

async function downloadImage(url: string, filename: string) {
  try {
    const response = await fetch(url, { mode: "cors" });
    if (!response.ok) throw new Error("download failed");
    const blob = await response.blob();
    const localUrl = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = localUrl;
    link.download = filename;
    link.click();
    URL.revokeObjectURL(localUrl);
  } catch {
    window.open(url, "_blank", "noopener,noreferrer");
  }
}

export default function EventLiveGallery() {
  const { eventId = "", albumId, imageId: routeImageId } = useParams();
  const [params, setParams] = useSearchParams();
  const faceEnrollment = params.get("face") === "1";
  const faceInput = useRef<HTMLInputElement>(null);
  const faceUploadInput = useRef<HTMLInputElement>(null);
  const registerInput = useRef<HTMLInputElement>(null);
  const storageKey = `gallery_access_${eventId}_${albumId || "all"}`;
  const guestStorageKey = `personal_gallery_${eventId}_${albumId || "all"}`;

  const [accessToken, setAccessToken] = useState(
    params.get("access") || localStorage.getItem(storageKey) || "",
  );
  const [guestToken, setGuestToken] = useState(
    params.get("guest") || localStorage.getItem(guestStorageKey) || "",
  );
  const [info, setInfo] = useState<GalleryInfo>();
  const [images, setImages] = useState<GalleryImage[]>([]);
  const [albums, setAlbums] = useState<Album[]>([]);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [visibleCount, setVisibleCount] = useState(pageSize);
  const [loading, setLoading] = useState(true);
  const [password, setPassword] = useState("");
  const [unlocking, setUnlocking] = useState(false);
  const [faceSearching, setFaceSearching] = useState(false);
  const [faceMatches, setFaceMatches] = useState(false);
  const [downloading, setDownloading] = useState(false);
  const [selfies, setSelfies] = useState<File[]>([]);
  const [registering, setRegistering] = useState(false);
  const [email, setEmail] = useState("");
  const [whatsapp, setWhatsapp] = useState("");
  const [notifyEmail, setNotifyEmail] = useState(true);
  const [notifyWhatsapp, setNotifyWhatsapp] = useState(faceEnrollment);
  const [consent, setConsent] = useState(false);
  const [blurredIds, setBlurredIds] = useState<string[]>([]);
  const [savingPreferences, setSavingPreferences] = useState(false);
  const [storeEnabled, setStoreEnabled] = useState(false);
  const [focusedIndex, setFocusedIndex] = useState(-1);
  const [findMeOpen, setFindMeOpen] = useState(false);

  const commonParams = useCallback(
    (includeAccess = true) => {
      const query = new URLSearchParams({ eventId });
      if (albumId) query.set("albumId", albumId);
      if (includeAccess && accessToken) query.set("accessToken", accessToken);
      return query;
    },
    [accessToken, albumId, eventId],
  );

  const track = useCallback(
    (type: string, targetImageId?: string) => {
      if (!eventId) return;
      void PostRequestAxios(
        "/analytics/track",
        {
          eventId,
          type,
          ...(albumId ? { albumId } : {}),
          ...(targetImageId ? { imageId: targetImageId } : {}),
          channel: guestToken ? "personal_gallery" : "live_gallery",
        },
        { withCredentials: false, redirectOnUnauthorized: false },
      );
    },
    [albumId, eventId, guestToken],
  );

  useEffect(() => {
    if (eventId) track("gallery_visit");
  }, [eventId, track]);
  const loadInfo = useCallback(async () => {
    if (!eventId) return undefined;
    const [data, error] = await GetRequestAxios<GalleryInfo>(
      `/gallery-access/info?${commonParams().toString()}`,
      { withCredentials: false, redirectOnUnauthorized: false },
    );
    if (error || !data) {
      toast.error(error?.message || "Gallery unavailable");
      return undefined;
    }
    setInfo(data);
    return data;
  }, [commonParams, eventId]);

  const loadPublic = useCallback(async () => {
    if (!eventId) return;
    const [data, error] = await GetRequestAxios<GalleryImageResponse>(
      `/eventImage/public?${commonParams().toString()}`,
      { withCredentials: false, redirectOnUnauthorized: false },
    );
    if (!error) {
      setImages(data?.data || []);
      setStoreEnabled(Boolean(data?.storeEnabled));
      setFaceMatches(false);
    }
    if (!albumId) {
      const albumQuery = new URLSearchParams({ eventId });
      if (accessToken) albumQuery.set("accessToken", accessToken);
      const [albumData] = await GetRequestAxios<{ data?: Album[] }>(
        `/album/public?${albumQuery.toString()}`,
        { withCredentials: false, redirectOnUnauthorized: false },
      );
      setAlbums(albumData?.data || []);
    }
  }, [accessToken, albumId, commonParams, eventId]);

  const loadPersonal = useCallback(async () => {
    if (!guestToken || !eventId) return;
    const query = commonParams(false);
    query.set("guestToken", guestToken);
    const [data, error] = await GetRequestAxios<PersonalGalleryResponse>(
      `/guest-gallery/personal?${query.toString()}`,
      { withCredentials: false, redirectOnUnauthorized: false },
    );
    if (error || !data) {
      if (error?.statusCode === 401) {
        localStorage.removeItem(guestStorageKey);
        setGuestToken("");
      }
      return;
    }
    setImages(data.data || []);
    setStoreEnabled(Boolean(data.storeEnabled));
    setFaceMatches(true);
    if (data.notificationPreferences) {
      setEmail(data.notificationPreferences.email || "");
      setWhatsapp(data.notificationPreferences.whatsapp || "");
      setNotifyEmail(Boolean(data.notificationPreferences.notifyEmail));
      setNotifyWhatsapp(Boolean(data.notificationPreferences.notifyWhatsapp));
    }
  }, [commonParams, eventId, guestStorageKey, guestToken]);

  useEffect(() => {
    let mounted = true;
    void (async () => {
      setLoading(true);
      const galleryInfo = await loadInfo();
      if (!mounted || !galleryInfo) {
        if (mounted) setLoading(false);
        return;
      }
      if (guestToken) await loadPersonal();
      else if (galleryInfo.unlocked) await loadPublic();
      if (mounted) setLoading(false);
    })();
    return () => {
      mounted = false;
    };
  }, [guestToken, loadInfo, loadPersonal, loadPublic]);

  useEffect(() => {
    if (!eventId || guestToken || !info?.unlocked) return;
    const source = new EventSource(
      `${baseUrl}/eventImage/public/stream?${commonParams().toString()}`,
    );
    const sync = () => void loadPublic();
    source.addEventListener("gallery", sync);
    const fallback = window.setInterval(sync, 15000);
    return () => {
      source.close();
      window.clearInterval(fallback);
    };
  }, [commonParams, eventId, guestToken, info?.unlocked, loadPublic]);

  useEffect(() => {
    if (!guestToken) return;
    const timer = window.setInterval(() => void loadPersonal(), 6000);
    return () => window.clearInterval(timer);
  }, [guestToken, loadPersonal]);

  useEffect(() => {
    if (
      !eventId ||
      guestToken ||
      info?.visibility !== "facial" ||
      info?.facialPrivacyMode !== "blur_non_matches"
    ) {
      setBlurredIds([]);
      return;
    }
    const query = new URLSearchParams({ eventId });
    if (albumId) query.set("albumId", albumId);
    void GetRequestAxios<{ data?: Array<{ _id: string }> }>(
      `/eventImage/public/blur-list?${query.toString()}`,
      { withCredentials: false, redirectOnUnauthorized: false },
    ).then(([data]) =>
      setBlurredIds((data?.data || []).map((item) => item._id)),
    );
  }, [albumId, eventId, guestToken, info?.facialPrivacyMode, info?.visibility]);

  useEffect(() => {
    const onScroll = () => {
      if (
        window.innerHeight + window.scrollY >=
        document.body.offsetHeight - 500
      ) {
        setVisibleCount((count) => Math.min(count + pageSize, images.length));
      }
    };
    window.addEventListener("scroll", onScroll);
    return () => window.removeEventListener("scroll", onScroll);
  }, [images.length]);

  useEffect(() => {
    if (!routeImageId || !images.length) return;
    const index = images.findIndex((image) => imageId(image) === routeImageId);
    if (index >= 0) setFocusedIndex(index);
  }, [images, routeImageId]);

  useEffect(() => {
    if (focusedIndex < 0) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") setFocusedIndex(-1);
      if (images.length && event.key === "ArrowLeft") {
        setFocusedIndex((index) => (index - 1 + images.length) % images.length);
      }
      if (images.length && event.key === "ArrowRight") {
        setFocusedIndex((index) => (index + 1) % images.length);
      }
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [focusedIndex, images.length]);

  const updateUrlToken = (key: "access" | "guest", value: string) => {
    const next = new URLSearchParams(params);
    if (value) next.set(key, value);
    else next.delete(key);
    setParams(next, { replace: true });
  };

  const unlock = async () => {
    if (!password.trim()) return;
    setUnlocking(true);
    const [data, error] = await PostRequestAxios<{ accessToken?: string }>(
      "/gallery-access/unlock",
      { eventId, ...(albumId ? { albumId } : {}), password: password.trim() },
      { withCredentials: false, redirectOnUnauthorized: false },
    );
    setUnlocking(false);
    if (error || !data?.accessToken) {
      toast.error(error?.message || "Wrong password");
      return;
    }
    localStorage.setItem(storageKey, data.accessToken);
    setAccessToken(data.accessToken);
    updateUrlToken("access", data.accessToken);
    setPassword("");
  };

  const registerPersonalGallery = async () => {
    const minimumSelfies = faceEnrollment ? 2 : 1;
    if (selfies.length < minimumSelfies || !consent) {
      toast.error(
        `Add at least ${minimumSelfies} selfie${minimumSelfies > 1 ? "s" : ""} and accept face-search consent`,
      );
      return;
    }
    if (faceEnrollment && (!email.trim() || !whatsapp.trim())) {
      toast.error("Email and WhatsApp are required for global face delivery");
      return;
    }
    setRegistering(true);
    const body = new FormData();
    selfies.slice(0, 5).forEach((file) => body.append("selfies", file));
    body.append("eventId", eventId);
    if (albumId) body.append("albumId", albumId);
    body.append("consent", "true");
    body.append("globalProfile", String(faceEnrollment));
    body.append("notifyEmail", String(notifyEmail));
    body.append("notifyWhatsapp", String(notifyWhatsapp));
    if (email.trim()) body.append("email", email.trim());
    if (whatsapp.trim()) body.append("whatsapp", whatsapp.trim());
    if (accessToken) body.append("accessToken", accessToken);
    const [data, error] = await PostRequestAxios<{
      guestToken?: string;
      updatedGlobalProfile?: boolean;
    }>("/guest-gallery/register", body, {
      withCredentials: false,
      redirectOnUnauthorized: false,
      headers: { "Content-Type": "multipart/form-data" },
    });
    setRegistering(false);
    if (error || !data?.guestToken) {
      toast.error(error?.message || "Could not create personal gallery");
      return;
    }
    localStorage.setItem(guestStorageKey, data.guestToken);
    setGuestToken(data.guestToken);
    updateUrlToken("guest", data.guestToken);
    toast.success(
      data.updatedGlobalProfile
        ? "Your global face profile was updated with the new selfies."
        : faceEnrollment
          ? "Global face profile created. Matching photos from enabled events can now reach you automatically."
          : "Personal gallery created. New matches will appear automatically.",
    );
  };

  const deletePersonalGallery = async () => {
    if (!guestToken) return;
    const [, error] = await PostRequestAxios(
      "/guest-gallery/delete",
      { eventId, guestToken },
      { withCredentials: false, redirectOnUnauthorized: false },
    );
    if (error) {
      toast.error(error.message);
      return;
    }
    localStorage.removeItem(guestStorageKey);
    setGuestToken("");
    setImages([]);
    updateUrlToken("guest", "");
    toast.success("Selfie profile removed");
  };

  const saveGuestPreferences = async () => {
    if (!guestToken) return;
    setSavingPreferences(true);
    const [, error] = await PatchRequestAxios(
      "/guest-gallery/preferences",
      {
        eventId,
        guestToken,
        ...(email.trim() ? { email: email.trim() } : {}),
        ...(whatsapp.trim() ? { whatsapp: whatsapp.trim() } : {}),
        notifyEmail,
        notifyWhatsapp,
      },
      { withCredentials: false, redirectOnUnauthorized: false },
    );
    setSavingPreferences(false);
    if (error) toast.error(error.message);
    else toast.success("Notification preferences saved");
  };

  const runFaceSearch = async (event: ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    event.target.value = "";
    if (!file) return;
    setFaceSearching(true);
    const body = new FormData();
    body.append("image", file);
    const query = commonParams();
    query.set("limit", "10000");
    const [data, error] = await PostRequestAxios<GalleryImageResponse>(
      `/eventImage/public/my-picture?${query.toString()}`,
      body,
      {
        withCredentials: false,
        redirectOnUnauthorized: false,
        headers: { "Content-Type": "multipart/form-data" },
      },
    );
    setFaceSearching(false);
    if (error) {
      toast.error(error.message || "Face search failed");
      return;
    }
    setImages(data?.data || []);
    setStoreEnabled(Boolean(data?.storeEnabled));
    setFaceMatches(true);
    track("face_search");
  };

  const toggle = (id: string) => {
    setSelected((current) => {
      const next = new Set(current);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const download = async (targetOverride?: GalleryImage[]) => {
    const target =
      targetOverride ||
      (selected.size
        ? images.filter((image) => selected.has(imageId(image)))
        : images);
    const paidIds = [
      ...new Set(
        target
          .filter((image) => image.purchaseRequired)
          .map((image) => image.storeImageId || imageId(image))
          .filter(Boolean),
      ),
    ];
    if (paidIds.length) {
      track("store_click");
      window.location.hash = `/store/${eventId}?photos=${encodeURIComponent(paidIds.join(","))}`;
      return;
    }

    setDownloading(true);
    for (const [index, image] of target.entries()) {
      if (image.imageUrl) {
        track("download", imageId(image));
        await downloadImage(
          assetUrl(image.imageUrl),
          `event-photo-${imageId(image).slice(-8) || index + 1}.${image.mediaType === "video" ? "mp4" : "jpg"}`,
        );
      }
    }
    setDownloading(false);
  };

  const focusedImage =
    focusedIndex >= 0 && focusedIndex < images.length
      ? images[focusedIndex]
      : undefined;
  const copyGalleryLink = async () => {
    const url = focusedImage
      ? publicImageUrl(eventId, imageId(focusedImage))
      : `${window.location.origin}${window.location.pathname}#/event/${eventId}`;
    await navigator.clipboard.writeText(url);
    track("share", focusedImage ? imageId(focusedImage) : undefined);
    toast.success("Share link copied");
  };
  const closeFocusedImage = () => {
    setFocusedIndex(-1);
    if (routeImageId) {
      window.location.hash = `/event/${eventId}`;
    }
  };

  const branding = info?.branding || {};
  const cover = branding.coverUrl || info?.image?.url;
  const style = {
    fontFamily: branding.fontFamily || undefined,
  } as CSSProperties;

  if (loading && !info) {
    return (
      <div className="flex min-h-screen items-center justify-center">
        <Loader2 className="h-8 w-8 animate-spin" />
      </div>
    );
  }

  if (info?.requiresPassword && !info.unlocked && !guestToken) {
    return (
      <AccessShell info={info} branding={branding} cover={cover} style={style}>
        <Lock className="mb-4 h-9 w-9" />
        <h2 className="text-2xl font-bold">Password protected gallery</h2>
        <p className="mt-2 text-sm text-muted-foreground">
          Only guests with the event password can view or download these photos.
        </p>
        <div className="mt-5 flex gap-2">
          <Input
            type="password"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            onKeyDown={(event) => event.key === "Enter" && void unlock()}
            placeholder="Gallery password"
          />
          <Button
            disabled={unlocking || !password.trim()}
            onClick={() => void unlock()}
          >
            {unlocking ? (
              <Loader2 className="h-4 w-4 animate-spin" />
            ) : (
              "Unlock"
            )}
          </Button>
        </div>
      </AccessShell>
    );
  }

  if (info?.requiresPrivateLink && !info.unlocked && !guestToken) {
    return (
      <AccessShell info={info} branding={branding} cover={cover} style={style}>
        <div className="text-center">
          <ShieldCheck className="mx-auto mb-4 h-10 w-10" />
          <h2 className="text-2xl font-bold">Private gallery</h2>
          <p className="mt-2 text-sm text-muted-foreground">
            Ask the event organizer for a secure gallery link.
          </p>
        </div>
      </AccessShell>
    );
  }

  if (
    (faceEnrollment ||
      info?.requiresFaceSearch ||
      info?.visibility === "facial") &&
    !guestToken
  ) {
    return (
      <AccessShell info={info} branding={branding} cover={cover} style={style}>
        <UserRoundSearch className="mb-4 h-10 w-10" />
        <h2 className="text-2xl font-bold">
          {faceEnrollment
            ? "Create or update your global face profile"
            : "Find only your photos"}
        </h2>
        <p className="mt-2 text-sm text-muted-foreground">
          {faceEnrollment
            ? "Take 2-5 clear selfies and add your email + WhatsApp. We reuse the private face profile at enabled events so new matching photos can reach you automatically."
            : "Take or upload a selfie. Your personal gallery updates while photographers keep shooting."}
        </p>
        {faceEnrollment ? (
          <div className="mt-5 grid grid-cols-3 gap-2">
            <EnrollmentStep number="1" label="Selfies" done={selfies.length >= 2} />
            <EnrollmentStep number="2" label="Contact" done={Boolean(email.trim() && whatsapp.trim())} />
            <EnrollmentStep number="3" label="Consent" done={consent} />
          </div>
        ) : null}
        {info?.facialPrivacyMode === "blur_non_matches" && blurredIds.length ? (
          <div className="mt-4">
            <p className="mb-2 text-xs font-medium text-muted-foreground">
              Live gallery preview — photos stay blurred until they match you.
            </p>
            <div className="grid grid-cols-3 gap-2">
              {blurredIds.slice(0, 6).map((id) => (
                <img
                  key={id}
                  src={
                    baseUrl +
                    "/eventImage/public/blurred?id=" +
                    encodeURIComponent(id) +
                    "&eventId=" +
                    encodeURIComponent(eventId) +
                    (albumId ? "&albumId=" + encodeURIComponent(albumId) : "")
                  }
                  alt="Private blurred preview"
                  className="aspect-square w-full rounded-lg object-cover"
                />
              ))}
            </div>
          </div>
        ) : null}
        <div className="mt-5 space-y-4">
          <input
            ref={registerInput}
            type="file"
            accept={imageAccept}
            capture="user"
            multiple
            className="hidden"
            onChange={(event) => {
              const incoming = Array.from(event.target.files || []);
              setSelfies((current) => [...current, ...incoming].slice(0, 5));
              event.currentTarget.value = "";
            }}
          />
          <Button
            className="w-full"
            variant={selfies.length ? "outline" : "default"}
            disabled={selfies.length >= 5}
            onClick={() => registerInput.current?.click()}
          >
            <Camera className="mr-2 h-4 w-4" />
            {selfies.length
              ? `Add another selfie (${selfies.length}/5)`
              : faceEnrollment
                ? "Take your first selfie"
                : "Take or upload selfie"}
          </Button>
          {faceEnrollment ? (
            <div className="rounded-xl border bg-muted/20 p-3">
              <div className="flex items-center justify-between text-xs">
                <span className="font-medium">Face samples</span>
                <span className="text-muted-foreground">{selfies.length}/5 · minimum 2</span>
              </div>
              <div className="mt-2 h-1.5 overflow-hidden rounded-full bg-muted">
                <div
                  className="h-full rounded-full bg-primary transition-all duration-300"
                  style={{ width: `${Math.max(8, (selfies.length / 5) * 100)}%` }}
                />
              </div>
            </div>
          ) : null}
          {selfies.length ? (
            <div className="flex flex-wrap gap-2">
              {selfies.map((file, index) => (
                <Badge
                  key={`${file.name}-${file.lastModified}-${index}`}
                  variant="outline"
                  className="gap-2 py-1.5"
                >
                  Selfie {index + 1}
                  <button
                    type="button"
                    aria-label={`Remove selfie ${index + 1}`}
                    onClick={() =>
                      setSelfies((current) =>
                        current.filter((_, itemIndex) => itemIndex !== index),
                      )
                    }
                  >
                    <Trash2 className="h-3 w-3" />
                  </button>
                </Badge>
              ))}
            </div>
          ) : null}
          {faceEnrollment || info.guestNotificationsEnabled ? (
            <>
              <div className="grid gap-3 sm:grid-cols-2">
                <div className="space-y-2">
                  <Label>Email {faceEnrollment ? "*" : ""}</Label>
                  <Input
                    type="email"
                    value={email}
                    onChange={(event) => setEmail(event.target.value)}
                    placeholder="you@example.com"
                  />
                </div>
                <div className="space-y-2">
                  <Label>WhatsApp {faceEnrollment ? "*" : ""}</Label>
                  <Input
                    value={whatsapp}
                    onChange={(event) => setWhatsapp(event.target.value)}
                    placeholder="+1..."
                  />
                </div>
              </div>
              {info.guestNotificationsEnabled ? (
                <div className="grid gap-2 sm:grid-cols-2">
                  {info.emailNotificationsEnabled !== false ? (
                    <Toggle
                      label="Email new matches"
                      checked={notifyEmail}
                      onChange={setNotifyEmail}
                    />
                  ) : (
                    <p className="rounded-xl border p-3 text-xs text-muted-foreground">
                      Email alerts are disabled for this event.
                    </p>
                  )}
                  {info.whatsappNotificationsEnabled === true ? (
                    <Toggle
                      label="WhatsApp new matches"
                      checked={notifyWhatsapp}
                      onChange={setNotifyWhatsapp}
                    />
                  ) : (
                    <p className="rounded-xl border p-3 text-xs text-muted-foreground">
                      WhatsApp alerts are disabled for this event.
                    </p>
                  )}
                </div>
              ) : (
                <p className="rounded-xl border p-3 text-xs text-muted-foreground">
                  This event has automatic match alerts turned off. Your
                  reusable face profile can still be created and used to find
                  matching photos.
                </p>
              )}
            </>
          ) : null}
          <label className="flex items-start gap-3 rounded-xl border p-3 text-sm">
            <Checkbox
              checked={consent}
              onCheckedChange={(value) => setConsent(value === true)}
            />
            <span>
              {faceEnrollment
                ? "I consent to a reusable global face profile. Face vectors and contact preferences can be reused at enabled events; original selfie files are not retained and I can delete the profile later."
                : "I consent to an event-scoped face profile for this gallery. My original selfie is not stored and I can delete the profile later."}
            </span>
          </label>
          <Button
            className="w-full"
            disabled={
              registering ||
              selfies.length < (faceEnrollment ? 2 : 1) ||
              !consent ||
              (faceEnrollment && (!email.trim() || !whatsapp.trim()))
            }
            onClick={() => void registerPersonalGallery()}
          >
            {registering ? (
              <Loader2 className="mr-2 h-4 w-4 animate-spin" />
            ) : (
              <Search className="mr-2 h-4 w-4" />
            )}
            {faceEnrollment
              ? "Create / update my global face profile"
              : "Create my personal gallery"}
          </Button>
        </div>
      </AccessShell>
    );
  }

  const visibleImages = images.slice(0, visibleCount);
  return (
    <div className="min-h-screen bg-muted/20" style={style}>
      <header
        className={`absolute inset-x-0 top-0 z-40 border-b ${cover ? "border-white/15 bg-black/10 text-white" : "border-border bg-background/95"} backdrop-blur-sm`}
      >
        <div className="mx-auto flex h-16 max-w-[1500px] items-center justify-between gap-3 px-4 sm:px-6">
          <div className="flex min-w-0 items-center gap-3">
            {albumId ? (
              <Button variant="ghost" size="icon" asChild aria-label="Back to gallery">
                <Link
                  to={`/event/${eventId}${accessToken ? `?access=${encodeURIComponent(accessToken)}` : ""}`}
                >
                  <ArrowLeft className="h-4 w-4" />
                </Link>
              </Button>
            ) : null}
            {branding.logoUrl ? (
              <img src={assetUrl(branding.logoUrl)} alt="" className="h-9 max-w-28 object-contain" />
            ) : !branding.whiteLabel ? (
              <span className="text-lg font-bold">airpix</span>
            ) : null}
          </div>
          <div className="flex items-center gap-1">
            <Button
              variant="ghost"
              size="icon"
              aria-label="Copy gallery share link"
              onClick={() => void copyGalleryLink()}
            >
              <Share2 className="h-4 w-4" />
            </Button>
            {guestToken ? (
              <Button
                variant="ghost"
                size="icon"
                aria-label="Delete selfie profile"
                onClick={() => void deletePersonalGallery()}
              >
                <Trash2 className="h-4 w-4" />
              </Button>
            ) : null}
          </div>
        </div>
      </header>

      <section
        className={`relative flex min-h-[72vh] items-center justify-center overflow-hidden border-b ${cover ? "bg-black text-white" : "bg-background pt-16"}`}
      >
        {cover ? (
          <img src={assetUrl(cover)} alt="" className="absolute inset-0 h-full w-full object-cover" />
        ) : null}
        {cover ? <div className="absolute inset-0 bg-black/55" /> : null}
        <div className="relative mx-auto max-w-4xl px-4 py-24 text-center sm:px-6">
          <Badge className="mb-4" variant={cover ? "secondary" : "outline"}>
            {guestToken ? "Your personal gallery" : "Event gallery"}
          </Badge>
          <h1 className="text-4xl font-bold tracking-tight sm:text-5xl">
            {branding.coverText || info?.title}
          </h1>
          {info?.description ? (
            <p className={`mx-auto mt-4 max-w-2xl text-base ${cover ? "text-white/80" : "text-muted-foreground"}`}>
              {info.description}
            </p>
          ) : null}
        </div>
        <button
          type="button"
          aria-label="View gallery photos"
          className={`absolute bottom-6 left-1/2 flex h-10 w-10 -translate-x-1/2 items-center justify-center rounded-full border ${cover ? "border-white/60 text-white" : "border-border"}`}
          onClick={() => document.getElementById("gallery-grid")?.scrollIntoView({ behavior: "smooth" })}
        >
          <ArrowDown className="h-4 w-4" />
        </button>
      </section>

      <main className="mx-auto max-w-[1500px] space-y-6 px-4 py-6 sm:px-6">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <p className="text-sm text-muted-foreground">
              {images.length} {guestToken ? "matching" : "published"} photos
            </p>
            {faceMatches ? (
              <Badge variant="outline" className="mt-1">
                Face matches
              </Badge>
            ) : null}
          </div>
          <div className="flex flex-wrap gap-2">
            {faceMatches ? (
              <Button variant="outline" onClick={() => void loadPublic()}>
                <RefreshCw className="mr-2 h-4 w-4" /> Show all
              </Button>
            ) : null}
            <Button
              disabled={downloading || images.length === 0}
              onClick={() => void download()}
            >
              {downloading ? (
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
              ) : storeEnabled ? (
                <ShoppingCart className="mr-2 h-4 w-4" />
              ) : (
                <Download className="mr-2 h-4 w-4" />
              )}
              {storeEnabled
                ? selected.size
                  ? `Buy ${selected.size} original${selected.size === 1 ? "" : "s"}`
                  : "Buy originals"
                : selected.size
                  ? `Download ${selected.size}`
                  : "Download all"}
            </Button>
          </div>
        </div>

        {guestToken && info?.guestNotificationsEnabled ? (
          <Card>
            <CardContent className="space-y-3 p-4">
              <div>
                <p className="font-semibold">New photo alerts</p>
                <p className="text-xs text-muted-foreground">
                  Change how we notify you when new face matches arrive.
                </p>
              </div>
              <div className="grid gap-3 sm:grid-cols-2">
                <Input
                  value={email}
                  onChange={(event) => setEmail(event.target.value)}
                  placeholder="Email"
                />
                <Input
                  value={whatsapp}
                  onChange={(event) => setWhatsapp(event.target.value)}
                  placeholder="WhatsApp"
                />
              </div>
              <div className="grid gap-2 sm:grid-cols-2">
                <Toggle
                  label="Email alerts"
                  checked={notifyEmail}
                  onChange={setNotifyEmail}
                />
                <Toggle
                  label="WhatsApp alerts"
                  checked={notifyWhatsapp}
                  onChange={setNotifyWhatsapp}
                />
              </div>
              <Button
                size="sm"
                disabled={savingPreferences}
                onClick={() => void saveGuestPreferences()}
              >
                {savingPreferences ? (
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                ) : null}
                Save alerts
              </Button>
            </CardContent>
          </Card>
        ) : null}

        {!albumId && albums.length && !guestToken ? (
          <section>
            <h2 className="mb-3 text-lg font-semibold">Albums</h2>
            <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
              {albums.map((album) => (
                <Link
                  key={album._id || album.id}
                  to={`/event/${eventId}/album/${album._id || album.id}${accessToken ? `?access=${encodeURIComponent(accessToken)}` : ""}`}
                  className="rounded-xl border bg-background p-4 transition hover:bg-muted/40"
                >
                  <Folder className="mb-3 h-6 w-6" />
                  <p className="font-semibold">{album.title || "Album"}</p>
                  <p className="mt-1 text-xs text-muted-foreground">
                    {album.imagesCount || 0} photos
                  </p>
                </Link>
              ))}
            </div>
          </section>
        ) : null}

        {loading ? (
          <div className="flex min-h-52 items-center justify-center">
            <Loader2 className="h-7 w-7 animate-spin" />
          </div>
        ) : visibleImages.length === 0 ? (
          <div className="flex min-h-64 flex-col items-center justify-center rounded-2xl border border-dashed bg-background text-center">
            <Images className="mb-3 h-10 w-10 text-muted-foreground" />
            <p className="font-semibold">
              {guestToken
                ? "No matching photos yet"
                : "No published photos yet"}
            </p>
            <p className="mt-1 max-w-md text-sm text-muted-foreground">
              {guestToken
                ? "Keep this page open. New matching photos appear automatically as the event continues."
                : "Published photos appear here in real time."}
            </p>
          </div>
        ) : (
          <div id="gallery-grid" className="columns-1 gap-1 sm:columns-2 lg:columns-3 xl:columns-4">
            {visibleImages.map((image, index) => {
              const id = imageId(image);
              if (!id) return null;
              const isSelected = selected.has(id);
              return (
                <article key={id} className="group relative mb-1 break-inside-avoid overflow-hidden bg-black">
                  {image.imageUrl ? (
                    image.mediaType === "video" ? (
                      <video
                        src={assetUrl(image.imageUrl)}
                        controls
                        preload="metadata"
                        className="aspect-video w-full object-cover"
                      />
                    ) : (
                      <button
                        type="button"
                        className="block w-full cursor-zoom-in"
                        aria-label={`Open event photo ${index + 1}`}
                        onClick={() => {
                          setFocusedIndex(index);
                          track("image_view", id);
                        }}
                      >
                        <img
                          src={assetUrl(image.imageUrl)}
                          alt={`Event photo ${index + 1}`}
                          loading="lazy"
                          className="h-auto w-full object-cover transition duration-300 group-hover:scale-[1.015]"
                        />
                      </button>
                    )
                  ) : (
                    <div className="flex aspect-[4/3] items-center justify-center bg-muted">
                      <ImageIcon className="h-8 w-8 text-muted-foreground" />
                    </div>
                  )}
                  {branding.watermarkUrl && branding.watermarkPosition === "tile" ? (
                    <div className="pointer-events-none absolute inset-0 grid grid-cols-3 grid-rows-2 place-items-center gap-3 p-4">
                      {Array.from({ length: 6 }, (_, watermarkIndex) => (
                        <img
                          key={watermarkIndex}
                          src={assetUrl(branding.watermarkUrl)}
                          alt=""
                          className="max-h-12 max-w-full object-contain"
                          style={{ opacity: branding.watermarkOpacity ?? 0.7, width: `${Math.min(branding.watermarkScale ?? 24, 45)}%` }}
                        />
                      ))}
                    </div>
                  ) : branding.watermarkUrl ? (
                    <img
                      src={assetUrl(branding.watermarkUrl)}
                      alt=""
                      className={`pointer-events-none absolute max-h-[60%] object-contain ${watermarkPositionClass(branding.watermarkPosition)}`}
                      style={{ opacity: branding.watermarkOpacity ?? 0.7, width: `${branding.watermarkScale ?? 24}%` }}
                    />
                  ) : null}
                  <label className="absolute left-3 top-3 rounded-full bg-background/90 p-1.5 opacity-0 shadow transition group-hover:opacity-100 has-[:checked]:opacity-100">
                    <Checkbox checked={isSelected} onCheckedChange={() => toggle(id)} aria-label="Select image" />
                  </label>
                  <Button
                    size="icon"
                    className="absolute bottom-3 right-3 h-9 w-9 rounded-full opacity-0 shadow transition group-hover:opacity-100"
                    aria-label={image.purchaseRequired ? "Buy original photo" : "Download original photo"}
                    onClick={() => void download([image])}
                  >
                    {image.purchaseRequired ? <ShoppingCart className="h-4 w-4" /> : <Download className="h-4 w-4" />}
                  </Button>
                  {image.isEnhanced ? <Badge className="absolute right-3 top-3">Enhanced</Badge> : null}
                </article>
              );
            })}
          </div>
        )}

        {visibleCount < images.length ? (
          <div className="flex justify-center">
            <Button
              variant="outline"
              onClick={() =>
                setVisibleCount((count) =>
                  Math.min(count + pageSize, images.length),
                )
              }
            >
              Load more
            </Button>
          </div>
        ) : null}
      </main>

      {info?.faceSearchEnabled && !guestToken ? (
        <>
          <input
            ref={faceInput}
            type="file"
            accept={imageAccept}
            capture="user"
            className="hidden"
            onChange={(event) => {
              setFindMeOpen(false);
              void runFaceSearch(event);
            }}
          />
          <input
            ref={faceUploadInput}
            type="file"
            accept={imageAccept}
            className="hidden"
            onChange={(event) => {
              setFindMeOpen(false);
              void runFaceSearch(event);
            }}
          />
          <Button
            size="lg"
            className="fixed bottom-5 right-5 z-40 rounded-full bg-white px-5 text-black shadow-2xl hover:bg-white/90"
            disabled={faceSearching}
            onClick={() => setFindMeOpen(true)}
          >
            {faceSearching ? <Loader2 className="mr-2 h-5 w-5 animate-spin" /> : <UserRoundSearch className="mr-2 h-5 w-5" />}
            Find Me
          </Button>
        </>
      ) : null}

      {findMeOpen ? (
        <FindMeDialog
          busy={faceSearching}
          onClose={() => setFindMeOpen(false)}
          onCamera={() => faceInput.current?.click()}
          onUpload={() => faceUploadInput.current?.click()}
        />
      ) : null}

      {focusedImage ? (
        <GalleryLightbox
          image={focusedImage}
          imageUrl={assetUrl(focusedImage.imageUrl)}
          position={focusedIndex + 1}
          total={images.length}
          onClose={closeFocusedImage}
          onPrevious={() => setFocusedIndex((index) => (index - 1 + images.length) % images.length)}
          onNext={() => setFocusedIndex((index) => (index + 1) % images.length)}
          onDownload={() => void download([focusedImage])}
          onCopyLink={() => void copyGalleryLink()}
        />
      ) : null}

      <footer className="border-t bg-background">
        <div className="mx-auto max-w-[1500px] px-4 py-6 text-sm text-muted-foreground sm:px-6">
          {branding.footerText ||
            (!branding.whiteLabel ? "Live photo delivery by airpix" : "")}
          {branding.sponsorText ? (
            <p className="mt-1">{branding.sponsorText}</p>
          ) : null}
        </div>
      </footer>
    </div>
  );
}

export function FindMeDialog({
  busy,
  onClose,
  onCamera,
  onUpload,
}: {
  busy: boolean;
  onClose: () => void;
  onCamera: () => void;
  onUpload: () => void;
}) {
  return (
    <div className="fixed inset-0 z-[70] flex items-center justify-center bg-black/65 p-4" role="dialog" aria-modal="true" aria-labelledby="find-me-title">
      <div className="relative w-full max-w-md rounded-3xl bg-background p-6 shadow-2xl">
        <Button variant="ghost" size="icon" className="absolute right-3 top-3" aria-label="Close Find Me" onClick={onClose}>
          <X className="h-5 w-5" />
        </Button>
        <UserRoundSearch className="mb-4 h-9 w-9" />
        <h2 id="find-me-title" className="text-2xl font-bold">Find all your photos</h2>
        <p className="mt-2 text-sm text-muted-foreground">
          Take a clear selfie now or upload one from your device. Face matching will show every photo of you in this event.
        </p>
        <div className="mt-6 grid gap-3 sm:grid-cols-2">
          <Button className="h-24 flex-col gap-2" disabled={busy} onClick={onCamera}>
            <Camera className="h-6 w-6" />
            Take a photo
          </Button>
          <Button className="h-24 flex-col gap-2" variant="outline" disabled={busy} onClick={onUpload}>
            <Upload className="h-6 w-6" />
            Upload a selfie
          </Button>
        </div>
        <p className="mt-4 text-xs text-muted-foreground">
          Your selfie is used only to search this gallery unless you explicitly create a reusable face profile.
        </p>
      </div>
    </div>
  );
}

function GalleryLightbox({
  image,
  imageUrl,
  position,
  total,
  onClose,
  onPrevious,
  onNext,
  onDownload,
  onCopyLink,
}: {
  image: GalleryImage;
  imageUrl: string;
  position: number;
  total: number;
  onClose: () => void;
  onPrevious: () => void;
  onNext: () => void;
  onDownload: () => void;
  onCopyLink: () => void;
}) {
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black text-white" role="dialog" aria-modal="true" aria-label="Photo viewer">
      <div className="absolute inset-x-0 top-0 z-10 flex items-center justify-between p-3 sm:p-5">
        <Button variant="ghost" size="icon" className="text-white hover:bg-white/10 hover:text-white" aria-label="Close photo" onClick={onClose}>
          <ArrowLeft className="h-6 w-6" />
        </Button>
        <div className="flex items-center gap-1">
          <Button variant="ghost" size="icon" className="text-white hover:bg-white/10 hover:text-white" aria-label="Copy photo link" onClick={onCopyLink}>
            <Copy className="h-5 w-5" />
          </Button>
          <Button variant="ghost" size="icon" className="text-white hover:bg-white/10 hover:text-white" aria-label={image.purchaseRequired ? "Buy original photo" : "Download original photo"} onClick={onDownload}>
            {image.purchaseRequired ? <ShoppingCart className="h-5 w-5" /> : <Download className="h-5 w-5" />}
          </Button>
        </div>
      </div>
      {total > 1 ? (
        <>
          <Button variant="ghost" size="icon" className="absolute left-2 z-10 text-white hover:bg-white/10 hover:text-white sm:left-5" aria-label="Previous photo" onClick={onPrevious}>
            <ChevronLeft className="h-8 w-8" />
          </Button>
          <Button variant="ghost" size="icon" className="absolute right-2 z-10 text-white hover:bg-white/10 hover:text-white sm:right-5" aria-label="Next photo" onClick={onNext}>
            <ChevronRight className="h-8 w-8" />
          </Button>
        </>
      ) : null}
      {image.mediaType === "video" ? (
        <video src={imageUrl} controls autoPlay className="max-h-screen max-w-full" />
      ) : (
        <img src={imageUrl} alt={`Event photo ${position}`} className="max-h-screen max-w-full object-contain" />
      )}
      <div className="absolute bottom-4 left-1/2 -translate-x-1/2 rounded-full bg-black/55 px-3 py-1.5 text-xs">
        {position} / {total}
        {image.purchaseRequired ? " · Preview — purchase unlocks original" : ""}
      </div>
    </div>
  );
}

function AccessShell({
  info,
  branding,
  cover,
  style,
  children,
}: {
  info?: GalleryInfo;
  branding: Branding;
  cover?: string;
  style: CSSProperties;
  children: ReactNode;
}) {
  return (
    <div className="min-h-screen bg-muted/20" style={style}>
      <div className="relative flex min-h-screen items-center justify-center overflow-hidden p-4">
        {cover ? (
          <img
            src={cover}
            alt=""
            className="absolute inset-0 h-full w-full object-cover"
          />
        ) : null}
        <div className="absolute inset-0 bg-black/50" />
        <div className="relative z-10 w-full">
          <div className="mx-auto mb-5 flex max-w-lg items-center justify-center gap-3">
            {branding.logoUrl ? (
              <img
                src={branding.logoUrl}
                alt=""
                className="max-h-12 max-w-40 object-contain"
              />
            ) : null}
            <p className="text-center text-lg font-bold text-white">
              {info?.title}
            </p>
          </div>
          <div className="mx-auto max-w-lg rounded-2xl border bg-background/95 p-6 shadow-sm">
            {children}
          </div>
        </div>
      </div>
    </div>
  );
}

function EnrollmentStep({
  number,
  label,
  done,
}: {
  number: string;
  label: string;
  done: boolean;
}) {
  return (
    <div className={`rounded-xl border p-2.5 text-center transition-all duration-200 ${done ? "border-primary/30 bg-primary/5" : "bg-muted/20"}`}>
      <div className="mx-auto flex h-7 w-7 items-center justify-center rounded-full border bg-background text-xs font-bold">
        {done ? <CheckCircle2 className="h-4 w-4 text-primary" /> : number}
      </div>
      <p className="mt-1.5 text-[11px] font-medium">{label}</p>
    </div>
  );
}

function Toggle({
  label,
  checked,
  onChange,
}: {
  label: string;
  checked: boolean;
  onChange: (value: boolean) => void;
}) {
  return (
    <div className="flex items-center justify-between rounded-xl border p-3">
      <span className="text-xs font-medium">{label}</span>
      <Switch checked={checked} onCheckedChange={onChange} />
    </div>
  );
}
