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
  ArrowLeft,
  Camera,
  Copy,
  Download,
  Folder,
  Image as ImageIcon,
  Images,
  Loader2,
  Lock,
  RefreshCw,
  Search,
  ShieldCheck,
  Trash2,
  UserRoundSearch,
} from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { GetRequestAxios, PatchRequestAxios, PostRequestAxios } from "@/api-hooks/api-hooks";

type Branding = {
  logoUrl?: string;
  coverUrl?: string;
  watermarkUrl?: string;
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
};

type GalleryImageResponse = {
  data?: GalleryImage[];
  totalItems?: number;
};

type Album = {
  _id?: string;
  id?: string;
  title?: string;
  imagesCount?: number;
};

type PersonalGalleryResponse = GalleryImageResponse & {
  event?: { branding?: Branding };
  notificationPreferences?: { email?: string; whatsapp?: string; notifyEmail?: boolean; notifyWhatsapp?: boolean };
};

const pageSize = 24;
const imageAccept = "image/jpeg,image/png,image/webp";
const baseUrl = import.meta.env.VITE_BASE_URL ?? "";
const imageId = (image: GalleryImage) =>
  image._id || image.id || image.imageUrl || "";

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
  const { eventId = "", albumId } = useParams();
  const [params, setParams] = useSearchParams();
  const faceInput = useRef<HTMLInputElement>(null);
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
  const [selfie, setSelfie] = useState<File>();
  const [registering, setRegistering] = useState(false);
  const [email, setEmail] = useState("");
  const [whatsapp, setWhatsapp] = useState("");
  const [notifyEmail, setNotifyEmail] = useState(true);
  const [notifyWhatsapp, setNotifyWhatsapp] = useState(false);
  const [consent, setConsent] = useState(false);
  const [blurredIds, setBlurredIds] = useState<string[]>([]);
  const [savingPreferences, setSavingPreferences] = useState(false);

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
  }, [eventId, albumId]);
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
    if (!eventId || guestToken || info?.visibility !== "facial" || info?.facialPrivacyMode !== "blur_non_matches") {
      setBlurredIds([]);
      return;
    }
    const query = new URLSearchParams({ eventId });
    if (albumId) query.set("albumId", albumId);
    void GetRequestAxios<{ data?: Array<{ _id: string }> }>(
      `/eventImage/public/blur-list?${query.toString()}`,
      { withCredentials: false, redirectOnUnauthorized: false },
    ).then(([data]) => setBlurredIds((data?.data || []).map((item) => item._id)));
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

  const updateUrlToken = (key: "access" | "guest", value: string) => {
    const next = new URLSearchParams(params);
    value ? next.set(key, value) : next.delete(key);
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
    if (!selfie || !consent) {
      toast.error("Add a selfie and accept face-search consent");
      return;
    }
    setRegistering(true);
    const body = new FormData();
    body.append("selfie", selfie);
    body.append("eventId", eventId);
    if (albumId) body.append("albumId", albumId);
    body.append("consent", "true");
    body.append("notifyEmail", String(notifyEmail));
    body.append("notifyWhatsapp", String(notifyWhatsapp));
    if (email.trim()) body.append("email", email.trim());
    if (whatsapp.trim()) body.append("whatsapp", whatsapp.trim());
    if (accessToken) body.append("accessToken", accessToken);
    const [data, error] = await PostRequestAxios<{ guestToken?: string }>(
      "/guest-gallery/register",
      body,
      {
        withCredentials: false,
        redirectOnUnauthorized: false,
        headers: { "Content-Type": "multipart/form-data" },
      },
    );
    setRegistering(false);
    if (error || !data?.guestToken) {
      toast.error(error?.message || "Could not create personal gallery");
      return;
    }
    localStorage.setItem(guestStorageKey, data.guestToken);
    setGuestToken(data.guestToken);
    updateUrlToken("guest", data.guestToken);
    toast.success(
      "Personal gallery created. New matches will appear automatically.",
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
      { eventId, guestToken, ...(email.trim() ? { email: email.trim() } : {}), ...(whatsapp.trim() ? { whatsapp: whatsapp.trim() } : {}), notifyEmail, notifyWhatsapp },
      { withCredentials: false, redirectOnUnauthorized: false },
    );
    setSavingPreferences(false);
    error ? toast.error(error.message) : toast.success("Notification preferences saved");
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
    setFaceMatches(true);
    track("face_search");
  };

  const toggle = (id: string) => {
    setSelected((current) => {
      const next = new Set(current);
      next.has(id) ? next.delete(id) : next.add(id);
      return next;
    });
  };

  const download = async () => {
    const target = selected.size
      ? images.filter((image) => selected.has(imageId(image)))
      : images;
    setDownloading(true);
    for (const [index, image] of target.entries()) {
      if (image.imageUrl) {
        track("download", imageId(image));
        await downloadImage(
          image.imageUrl,
          `event-photo-${imageId(image).slice(-8) || index + 1}.${image.mediaType === "video" ? "mp4" : "jpg"}`,
        );
      }
    }
    setDownloading(false);
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
    (info?.requiresFaceSearch || info?.visibility === "facial") &&
    !guestToken
  ) {
    return (
      <AccessShell info={info} branding={branding} cover={cover} style={style}>
        <UserRoundSearch className="mb-4 h-10 w-10" />
        <h2 className="text-2xl font-bold">Find only your photos</h2>
        <p className="mt-2 text-sm text-muted-foreground">
          Take or upload one selfie. Your personal gallery updates while
          photographers keep shooting.
        </p>
        {info?.facialPrivacyMode === "blur_non_matches" && blurredIds.length ? (
          <div className="mt-4">
            <p className="mb-2 text-xs font-medium text-muted-foreground">Live gallery preview — photos stay blurred until they match you.</p>
            <div className="grid grid-cols-3 gap-2">
              {blurredIds.slice(0, 6).map((id) => (
                <img key={id} src={baseUrl + "/eventImage/public/blurred?id=" + encodeURIComponent(id) + "&eventId=" + encodeURIComponent(eventId) + (albumId ? "&albumId=" + encodeURIComponent(albumId) : "")} alt="Private blurred preview" className="aspect-square w-full rounded-lg object-cover" />
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
            className="hidden"
            onChange={(event) => setSelfie(event.target.files?.[0])}
          />
          <Button
            className="w-full"
            variant={selfie ? "outline" : "default"}
            onClick={() => registerInput.current?.click()}
          >
            <Camera className="mr-2 h-4 w-4" />
            {selfie ? selfie.name : "Take or upload selfie"}
          </Button>
          {info.guestNotificationsEnabled ? (
            <>
              <div className="grid gap-3 sm:grid-cols-2">
                <div className="space-y-2">
                  <Label>Email</Label>
                  <Input
                    value={email}
                    onChange={(event) => setEmail(event.target.value)}
                    placeholder="you@example.com"
                  />
                </div>
                <div className="space-y-2">
                  <Label>WhatsApp</Label>
                  <Input
                    value={whatsapp}
                    onChange={(event) => setWhatsapp(event.target.value)}
                    placeholder="+1..."
                  />
                </div>
              </div>
              <div className="grid gap-2 sm:grid-cols-2">
                <Toggle
                  label="Email new matches"
                  checked={notifyEmail}
                  onChange={setNotifyEmail}
                />
                <Toggle
                  label="WhatsApp new matches"
                  checked={notifyWhatsapp}
                  onChange={setNotifyWhatsapp}
                />
              </div>
            </>
          ) : null}
          <label className="flex items-start gap-3 rounded-xl border p-3 text-sm">
            <Checkbox
              checked={consent}
              onCheckedChange={(value) => setConsent(value === true)}
            />
            <span>
              I consent to an event-scoped face profile for this gallery. My
              original selfie is not stored and I can delete the profile later.
            </span>
          </label>
          <Button
            className="w-full"
            disabled={registering || !selfie || !consent}
            onClick={() => void registerPersonalGallery()}
          >
            {registering ? (
              <Loader2 className="mr-2 h-4 w-4 animate-spin" />
            ) : (
              <Search className="mr-2 h-4 w-4" />
            )}
            Create my personal gallery
          </Button>
        </div>
      </AccessShell>
    );
  }

  const visibleImages = images.slice(0, visibleCount);
  return (
    <div className="min-h-screen bg-muted/20" style={style}>
      <header className="sticky top-0 z-40 border-b bg-background/95 backdrop-blur">
        <div className="mx-auto flex h-16 max-w-[1500px] items-center justify-between gap-3 px-4 sm:px-6">
          <div className="flex min-w-0 items-center gap-3">
            {albumId ? (
              <Button variant="ghost" size="icon" asChild>
                <Link
                  to={`/event/${eventId}${accessToken ? `?access=${encodeURIComponent(accessToken)}` : ""}`}
                >
                  <ArrowLeft className="h-4 w-4" />
                </Link>
              </Button>
            ) : null}
            {branding.logoUrl ? (
              <img
                src={branding.logoUrl}
                alt=""
                className="h-9 max-w-28 object-contain"
              />
            ) : !branding.whiteLabel ? (
              <span className="font-bold">airpix</span>
            ) : null}
            <div className="min-w-0">
              <p className="truncate font-semibold">
                {info?.title || "Live Gallery"}
              </p>
              {guestToken ? (
                <p className="text-xs text-muted-foreground">
                  Your personal live gallery
                </p>
              ) : null}
            </div>
          </div>
          <div className="flex items-center gap-2">
            <Button
              variant="outline"
              size="sm"
              onClick={async () => {
                try {
                  if (navigator.share) {
                    await navigator.share({
                      title: info?.title || "Live Gallery",
                      url: window.location.href,
                    });
                    track("share");
                    return;
                  }
                } catch (error) {
                  if ((error as DOMException)?.name === "AbortError") return;
                }
                await navigator.clipboard.writeText(window.location.href);
                track("share");
                toast.success("Gallery link copied");
              }}
            >
              <Copy className="mr-2 h-4 w-4" /> Share
            </Button>
            {guestToken ? (
              <Button
                variant="ghost"
                size="icon"
                title="Delete selfie profile"
                onClick={() => void deletePersonalGallery()}
              >
                <Trash2 className="h-4 w-4" />
              </Button>
            ) : null}
          </div>
        </div>
      </header>

      <section className="relative overflow-hidden border-b bg-background">
        {cover ? (
          <img
            src={cover}
            alt=""
            className="absolute inset-0 h-full w-full object-cover"
          />
        ) : null}
        {cover ? <div className="absolute inset-0 bg-black/50" /> : null}
        <div
          className={`relative mx-auto max-w-[1500px] px-4 py-12 sm:px-6 sm:py-16 ${cover ? "text-white" : ""}`}
        >
          <Badge className="mb-3" variant={cover ? "secondary" : "outline"}>
            {guestToken ? "Personal gallery" : "Live gallery"}
          </Badge>
          <h1 className="max-w-3xl text-3xl font-bold sm:text-4xl">
            {info?.title}
          </h1>
          {info?.description ? (
            <p
              className={`mt-3 max-w-2xl ${cover ? "text-white/80" : "text-muted-foreground"}`}
            >
              {info.description}
            </p>
          ) : null}
        </div>
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
            {info?.faceSearchEnabled && !guestToken ? (
              <>
                <input
                  ref={faceInput}
                  type="file"
                  accept={imageAccept}
                  capture="user"
                  className="hidden"
                  onChange={runFaceSearch}
                />
                <Button
                  variant="outline"
                  disabled={faceSearching}
                  onClick={() => faceInput.current?.click()}
                >
                  {faceSearching ? (
                    <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                  ) : (
                    <Camera className="mr-2 h-4 w-4" />
                  )}
                  Find my photos
                </Button>
                {faceMatches ? (
                  <Button variant="outline" onClick={() => void loadPublic()}>
                    <RefreshCw className="mr-2 h-4 w-4" /> Show all
                  </Button>
                ) : null}
              </>
            ) : null}
            <Button
              disabled={downloading || images.length === 0}
              onClick={() => void download()}
            >
              {downloading ? (
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
              ) : (
                <Download className="mr-2 h-4 w-4" />
              )}
              {selected.size ? `Download ${selected.size}` : "Download all"}
            </Button>
          </div>
        </div>

        {guestToken && info?.guestNotificationsEnabled ? (
          <Card>
            <CardContent className="space-y-3 p-4">
              <div><p className="font-semibold">New photo alerts</p><p className="text-xs text-muted-foreground">Change how we notify you when new face matches arrive.</p></div>
              <div className="grid gap-3 sm:grid-cols-2"><Input value={email} onChange={(event) => setEmail(event.target.value)} placeholder="Email" /><Input value={whatsapp} onChange={(event) => setWhatsapp(event.target.value)} placeholder="WhatsApp" /></div>
              <div className="grid gap-2 sm:grid-cols-2"><Toggle label="Email alerts" checked={notifyEmail} onChange={setNotifyEmail} /><Toggle label="WhatsApp alerts" checked={notifyWhatsapp} onChange={setNotifyWhatsapp} /></div>
              <Button size="sm" disabled={savingPreferences} onClick={() => void saveGuestPreferences()}>{savingPreferences ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : null}Save alerts</Button>
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
          <div className="grid grid-cols-2 gap-3 md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5">
            {visibleImages.map((image, index) => {
              const id = imageId(image);
              const isSelected = selected.has(id);
              return (
                <Card key={id || index} className="overflow-hidden">
                  <div className="group relative aspect-[4/3] bg-muted">
                    {image.imageUrl ? (
                      image.mediaType === "video" ? (
                        <video src={image.imageUrl} controls preload="metadata" className="h-full w-full object-cover" />
                      ) : (
                        <a href={image.imageUrl} target="_blank" rel="noreferrer" onClick={() => track("image_view", id)}>
                          <img src={image.imageUrl} alt="" className="h-full w-full object-cover" />
                        </a>
                      )
                    ) : (
                      <div className="flex h-full items-center justify-center">
                        <ImageIcon className="h-8 w-8 text-muted-foreground" />
                      </div>
                    )}
                    {branding.watermarkUrl ? (
                      <img
                        src={branding.watermarkUrl}
                        alt=""
                        className="pointer-events-none absolute bottom-3 right-3 max-h-10 max-w-[40%] object-contain opacity-80"
                      />
                    ) : null}
                    <label className="absolute left-3 top-3 rounded-full bg-background/90 p-1.5 shadow">
                      <Checkbox
                        checked={isSelected}
                        onCheckedChange={() => toggle(id)}
                        aria-label="Select image"
                      />
                    </label>
                    {image.isEnhanced ? (
                      <Badge className="absolute right-3 top-3">Enhanced</Badge>
                    ) : null}
                  </div>
                  <CardContent className="flex items-center justify-between gap-2 p-3">
                    <p className="truncate text-xs text-muted-foreground">
                      {typeof image.userTakenBy === "object"
                        ? image.userTakenBy?.name || "Photographer"
                        : "Live upload"}
                    </p>
                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-7 w-7"
                      disabled={!image.imageUrl}
                      onClick={() =>
                        image.imageUrl &&
                        void downloadImage(
                          image.imageUrl,
                          `event-photo-${id.slice(-8)}.${image.mediaType === "video" ? "mp4" : "jpg"}`,
                        )
                      }
                    >
                      <Download className="h-3.5 w-3.5" />
                    </Button>
                  </CardContent>
                </Card>
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
