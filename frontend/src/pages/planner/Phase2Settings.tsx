import { useEffect, useMemo, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import {
  ArrowLeft,
  Bell,
  Copy,
  ExternalLink,
  Image as ImageIcon,
  Loader2,
  Lock,
  RefreshCw,
  ShieldCheck,
  Sparkles,
  Upload,
  Users,
} from "lucide-react";
import {
  GetRequestAxios,
  PatchRequestAxios,
  PostRequestAxios,
} from "@/api-hooks/api-hooks";
import { useQueryWrapper } from "@/api-hooks/react-query-wrapper";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Switch } from "@/components/ui/switch";
import { Textarea } from "@/components/ui/textarea";
import { toast } from "sonner";
import PlannerLayout from "./PlannerLayout";

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

type EventSettings = {
  _id: string;
  title: string;
  galleryVisibility?: string;
  facialPrivacyMode?: string;
  faceSearchEnabled?: boolean;
  faceConsentRequired?: boolean;
  faceRetentionDays?: number;
  guestNotificationsEnabled?: boolean;
  emailNotificationsEnabled?: boolean;
  whatsappNotificationsEnabled?: boolean;
  publishPolicy?: "auto_upload" | "auto_ai" | "manual";
  gallerySlug?: string;
  customDomain?: string;
  branding?: Branding;
};

type Album = {
  _id: string;
  title: string;
  galleryVisibility?: string;
  publishPolicy?: "inherit" | "auto_upload" | "auto_ai" | "manual";
};

type NotificationStatus = {
  registrations: number;
  notifications: Record<string, number>;
  recent: Array<{
    _id: string;
    channel: string;
    status: string;
    photoIds?: string[];
  }>;
};

const accessModes = [
  ["public", "Public - anyone with the link"],
  ["private", "Private - secure invite link only"],
  ["password", "Password protected"],
  ["facial", "Facial privacy - guests see their own matches"],
] as const;

export default function Phase2Settings() {
  const { eventId = "" } = useParams();
  const queryClient = useQueryClient();
  const settingsQuery = useQueryWrapper<{ data: EventSettings }>(
    ["phase2-settings", eventId],
    `/gallery-access/settings?eventId=${eventId}`,
    { withToken: true, withCredentials: true, enabled: Boolean(eventId) },
  );
  const albumsQuery = useQueryWrapper<{ data: Album[] }>(
    ["phase2-albums", eventId],
    `/album/get-all?eventId=${eventId}`,
    { withToken: true, withCredentials: true, enabled: Boolean(eventId) },
  );
  const notificationQuery = useQueryWrapper<NotificationStatus>(
    ["phase2-notifications", eventId],
    `/guest-gallery/notifications?eventId=${eventId}`,
    { withToken: true, withCredentials: true, enabled: Boolean(eventId) },
  );

  const [visibility, setVisibility] = useState("public");
  const [password, setPassword] = useState("");
  const [faceSearchEnabled, setFaceSearchEnabled] = useState(false);
  const [facialPrivacyMode, setFacialPrivacyMode] =
    useState("hide_non_matches");
  const [retentionDays, setRetentionDays] = useState("30");
  const [guestNotificationsEnabled, setGuestNotificationsEnabled] =
    useState(false);
  const [emailNotificationsEnabled, setEmailNotificationsEnabled] =
    useState(true);
  const [whatsappNotificationsEnabled, setWhatsappNotificationsEnabled] =
    useState(false);
  const [gallerySlug, setGallerySlug] = useState("");
  const [customDomain, setCustomDomain] = useState("");
  const [publishPolicy, setPublishPolicy] = useState("auto_upload");
  const [branding, setBranding] = useState<Branding>({});
  const [uploadingAsset, setUploadingAsset] = useState<string>();
  const [albumPasswords, setAlbumPasswords] = useState<Record<string, string>>(
    {},
  );
  const [albumModes, setAlbumModes] = useState<Record<string, string>>({});
  const [albumPolicies, setAlbumPolicies] = useState<Record<string, string>>({});

  useEffect(() => {
    const rows = albumsQuery.data?.data || [];
    setAlbumModes((current) => {
      const next = { ...current };
      for (const album of rows) {
        if (!next[album._id]) next[album._id] = album.galleryVisibility || "inherit";
      }
      return next;
    });
  }, [albumsQuery.data?.data]);

  useEffect(() => {
    const rows = albumsQuery.data?.data || [];
    setAlbumPolicies((current) => {
      const next = { ...current };
      for (const album of rows) {
        if (!next[album._id]) next[album._id] = album.publishPolicy || "inherit";
      }
      return next;
    });
  }, [albumsQuery.data?.data]);

  useEffect(() => {
    const data = settingsQuery.data?.data;
    if (!data) return;
    setVisibility(data.galleryVisibility || "public");
    setFaceSearchEnabled(Boolean(data.faceSearchEnabled));
    setFacialPrivacyMode(data.facialPrivacyMode || "hide_non_matches");
    setRetentionDays(String(data.faceRetentionDays || 30));
    setGuestNotificationsEnabled(Boolean(data.guestNotificationsEnabled));
    setEmailNotificationsEnabled(data.emailNotificationsEnabled !== false);
    setWhatsappNotificationsEnabled(Boolean(data.whatsappNotificationsEnabled));
    setGallerySlug(data.gallerySlug || "");
    setCustomDomain(data.customDomain || "");
    setPublishPolicy(data.publishPolicy || "auto_upload");
    setBranding(data.branding || {});
  }, [settingsQuery.data?.data]);

  const saveMutation = useMutation({
    mutationFn: async (extra?: Record<string, unknown>) => {
      const payload: Record<string, unknown> = {
        eventId,
        visibility,
        faceSearchEnabled,
        faceConsentRequired: true,
        facialPrivacyMode,
        faceRetentionDays: Number(retentionDays) || 30,
        guestNotificationsEnabled,
        emailNotificationsEnabled,
        whatsappNotificationsEnabled,
        publishPolicy,
        gallerySlug,
        customDomain,
        branding,
        ...extra,
      };
      if (password.trim()) payload.password = password.trim();
      const [response, error] = await PatchRequestAxios(
        "/gallery-access/settings",
        payload,
        { withToken: true, withCredentials: true },
      );
      if (error || !response)
        throw new Error(error?.message || "Could not save settings");
      return response;
    },
    onSuccess: () => {
      setPassword("");
      queryClient.invalidateQueries({ queryKey: ["phase2-settings", eventId] });
      toast.success("Live gallery settings saved");
    },
    onError: (error: Error) => toast.error(error.message),
  });

  const albumMutation = useMutation({
    mutationFn: async ({
      albumId,
      mode,
      publishPolicy,
    }: {
      albumId: string;
      mode: string;
      publishPolicy: string;
    }) => {
      const [response, error] = await PatchRequestAxios(
        "/gallery-access/settings",
        {
          eventId,
          albumId,
          visibility: mode,
          publishPolicy,
          ...(albumPasswords[albumId]?.trim()
            ? { password: albumPasswords[albumId].trim() }
            : {}),
        },
        { withToken: true, withCredentials: true },
      );
      if (error || !response)
        throw new Error(error?.message || "Could not update album privacy");
      return response;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["phase2-albums", eventId] });
      toast.success("Album privacy updated");
    },
    onError: (error: Error) => toast.error(error.message),
  });

  const privateLinkMutation = useMutation({
    mutationFn: async () => {
      const [response, error] = await PostRequestAxios<{ accessToken: string }>(
        "/gallery-access/private-link",
        { eventId, ttlHours: 72 },
        { withToken: true, withCredentials: true },
      );
      if (error || !response?.accessToken)
        throw new Error(error?.message || "Could not create link");
      return response.accessToken;
    },
    onSuccess: async (token) => {
      const url = `${window.location.origin}${window.location.pathname}#/event/${eventId}?access=${encodeURIComponent(token)}`;
      await navigator.clipboard.writeText(url);
      toast.success("Secure 72-hour gallery link copied");
    },
    onError: (error: Error) => toast.error(error.message),
  });

  const revokeMutation = useMutation({
    mutationFn: async () => {
      const [response, error] = await PostRequestAxios(
        "/gallery-access/revoke",
        { eventId },
        { withToken: true, withCredentials: true },
      );
      if (error || !response)
        throw new Error(error?.message || "Could not revoke links");
      return response;
    },
    onSuccess: () => toast.success("Existing secure links revoked"),
    onError: (error: Error) => toast.error(error.message),
  });

  const uploadAsset = async (
    file: File,
    key: "logoUrl" | "coverUrl" | "watermarkUrl",
  ) => {
    setUploadingAsset(key);
    try {
      const formData = new FormData();
      formData.append("file", file);
      const [response, error] = await PostRequestAxios<{ url?: string }>(
        "/image/upload",
        formData,
        {
          withToken: true,
          withCredentials: true,
          headers: { "Content-Type": "multipart/form-data" },
        },
      );
      if (error || !response?.url)
        throw new Error(error?.message || "Upload failed");
      setBranding((current) => ({ ...current, [key]: response.url }));
      toast.success("Brand asset uploaded - save settings to publish it");
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "Upload failed");
    } finally {
      setUploadingAsset(undefined);
    }
  };

  const publicUrl = useMemo(
    () =>
      `${window.location.origin}${window.location.pathname}#/event/${eventId}`,
    [eventId],
  );
  const notificationTotal = Object.values(
    notificationQuery.data?.notifications || {},
  ).reduce((sum, value) => sum + Number(value || 0), 0);

  return (
    <PlannerLayout>
      <div className="space-y-6">
        <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
          <div className="flex items-center gap-3">
            <Button variant="outline" size="icon" asChild>
              <Link to={`/planner/live/${eventId}`}>
                <ArrowLeft className="h-4 w-4" />
              </Link>
            </Button>
            <div>
              <p className="text-sm font-medium text-muted-foreground">
                Phase 2 delivery
              </p>
              <h1 className="text-2xl font-bold">
                {settingsQuery.data?.data?.title || "Live gallery & AI"}
              </h1>
              <p className="mt-1 text-sm text-muted-foreground">
                Privacy, face delivery, notifications and branding for this
                event.
              </p>
            </div>
          </div>
          <div className="flex flex-wrap gap-2">
            <Button variant="outline" asChild>
              <a href={publicUrl} target="_blank" rel="noreferrer">
                <ExternalLink className="mr-2 h-4 w-4" />
                Open gallery
              </a>
            </Button>
            <Button
              onClick={() => saveMutation.mutate({})}
              disabled={saveMutation.isPending}
            >
              {saveMutation.isPending ? (
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
              ) : (
                <ShieldCheck className="mr-2 h-4 w-4" />
              )}
              Save Phase 2 settings
            </Button>
          </div>
        </div>

        <div className="grid gap-4 sm:grid-cols-3">
          <Card>
            <CardContent className="flex items-center gap-3 p-4">
              <Users className="h-5 w-5" />
              <div>
                <p className="text-2xl font-bold">
                  {notificationQuery.data?.registrations || 0}
                </p>
                <p className="text-xs text-muted-foreground">
                  Personal galleries
                </p>
              </div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="flex items-center gap-3 p-4">
              <Bell className="h-5 w-5" />
              <div>
                <p className="text-2xl font-bold">{notificationTotal}</p>
                <p className="text-xs text-muted-foreground">
                  Guest notifications
                </p>
              </div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="flex items-center gap-3 p-4">
              <Sparkles className="h-5 w-5" />
              <div>
                <p className="text-sm font-bold">AI review + face indexing</p>
                <p className="text-xs text-muted-foreground">
                  Runs as photos arrive
                </p>
              </div>
            </CardContent>
          </Card>
        </div>

        <div className="grid gap-5 xl:grid-cols-2">
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <Lock className="h-5 w-5" />
                Gallery privacy
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="space-y-2">
                <Label>Who can see this gallery?</Label>
                <Select value={visibility} onValueChange={setVisibility}>
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {accessModes.map(([value, label]) => (
                      <SelectItem key={value} value={value}>
                        {label}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-2">
                <Label>Publish workflow</Label>
                <Select value={publishPolicy} onValueChange={setPublishPolicy}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="auto_upload">Publish after upload</SelectItem>
                    <SelectItem value="auto_ai">Publish after AI enhancement</SelectItem>
                    <SelectItem value="manual">Manual review & publish</SelectItem>
                  </SelectContent>
                </Select>
                <p className="text-xs text-muted-foreground">Controls when new camera photos become visible to guests.</p>
              </div>
              {visibility === "password" ? (
                <div className="space-y-2">
                  <Label>New gallery password</Label>
                  <Input
                    type="password"
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    placeholder="Leave blank to keep current password"
                  />
                  <Button
                    size="sm"
                    variant="outline"
                    onClick={() => saveMutation.mutate({ password: "" })}
                  >
                    Remove saved password
                  </Button>
                </div>
              ) : null}
              <div className="grid gap-3 sm:grid-cols-2">
                <Button
                  variant="outline"
                  disabled={privateLinkMutation.isPending}
                  onClick={() => privateLinkMutation.mutate()}
                >
                  <Copy className="mr-2 h-4 w-4" />
                  Copy secure link
                </Button>
                <Button
                  variant="outline"
                  disabled={revokeMutation.isPending}
                  onClick={() => revokeMutation.mutate()}
                >
                  <RefreshCw className="mr-2 h-4 w-4" />
                  Revoke old links
                </Button>
              </div>
              <div className="space-y-2">
                <Label>Gallery slug</Label>
                <Input
                  value={gallerySlug}
                  onChange={(e) => setGallerySlug(e.target.value)}
                  placeholder="smith-wedding-2026"
                />
              </div>
              <div className="space-y-2">
                <Label>Custom domain</Label>
                <Input
                  value={customDomain}
                  onChange={(e) => setCustomDomain(e.target.value)}
                  placeholder="photos.example.com"
                />
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Face recognition & personal delivery</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <Toggle
                label="Enable face recognition"
                checked={faceSearchEnabled}
                onChange={setFaceSearchEnabled}
              />
              <div className="rounded-xl border p-3">
                <p className="text-sm font-medium">Explicit selfie consent required</p>
                <p className="mt-1 text-xs text-muted-foreground">
                  Face recognition always requires guest consent before a face profile is created.
                </p>
              </div>
              <div className="space-y-2">
                <Label>Facial privacy behavior</Label>
                <Select
                  value={facialPrivacyMode}
                  onValueChange={setFacialPrivacyMode}
                >
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="off">
                      Normal gallery after face search
                    </SelectItem>
                    <SelectItem value="hide_non_matches">
                      Hide non-matching photos
                    </SelectItem>
                    <SelectItem value="blur_non_matches">
                      Blur non-matching photos
                    </SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-2">
                <Label>Biometric retention days</Label>
                <Input
                  type="number"
                  min={1}
                  max={365}
                  value={retentionDays}
                  onChange={(e) => setRetentionDays(e.target.value)}
                />
              </div>
              <p className="rounded-xl border bg-muted/30 p-3 text-xs text-muted-foreground">
                Original guest selfies are processed for face vectors and are
                not retained by this Phase 2 flow. The private face profile
                expires automatically after this retention period.
              </p>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Automatic guest notifications</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <Toggle
                label="Enable automatic match notifications"
                checked={guestNotificationsEnabled}
                onChange={setGuestNotificationsEnabled}
              />
              <Toggle
                label="Email delivery"
                checked={emailNotificationsEnabled}
                onChange={setEmailNotificationsEnabled}
              />
              <Toggle
                label="WhatsApp delivery"
                checked={whatsappNotificationsEnabled}
                onChange={setWhatsappNotificationsEnabled}
              />
              <p className="text-xs text-muted-foreground">
                New face matches are grouped before sending, deduplicated per
                guest/photo, retried on failure, and linked to the guest's
                secure personal gallery.
              </p>
              <div className="flex flex-wrap gap-2">
                {Object.entries(
                  notificationQuery.data?.notifications || {},
                ).map(([status, count]) => (
                  <Badge key={status} variant="outline">
                    {status}: {count}
                  </Badge>
                ))}
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Branding</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <AssetInput
                label="Logo"
                value={branding.logoUrl}
                loading={uploadingAsset === "logoUrl"}
                onFile={(file) => uploadAsset(file, "logoUrl")}
              />
              <AssetInput
                label="Cover / banner"
                value={branding.coverUrl}
                loading={uploadingAsset === "coverUrl"}
                onFile={(file) => uploadAsset(file, "coverUrl")}
              />
              <AssetInput
                label="Watermark"
                value={branding.watermarkUrl}
                loading={uploadingAsset === "watermarkUrl"}
                onFile={(file) => uploadAsset(file, "watermarkUrl")}
              />
              <div className="grid gap-3 sm:grid-cols-2">
                <ColorField
                  label="Primary"
                  value={branding.primaryColor || "#111827"}
                  onChange={(value) =>
                    setBranding((current) => ({
                      ...current,
                      primaryColor: value,
                    }))
                  }
                />
                <ColorField
                  label="Accent"
                  value={branding.accentColor || "#2563eb"}
                  onChange={(value) =>
                    setBranding((current) => ({
                      ...current,
                      accentColor: value,
                    }))
                  }
                />
              </div>
              <div className="space-y-2">
                <Label>Footer text</Label>
                <Textarea
                  value={branding.footerText || ""}
                  onChange={(e) =>
                    setBranding((current) => ({
                      ...current,
                      footerText: e.target.value,
                    }))
                  }
                />
              </div>
              <div className="space-y-2">
                <Label>Sponsor text</Label>
                <Input
                  value={branding.sponsorText || ""}
                  onChange={(e) =>
                    setBranding((current) => ({
                      ...current,
                      sponsorText: e.target.value,
                    }))
                  }
                />
              </div>
              <Toggle
                label="White-label gallery"
                checked={Boolean(branding.whiteLabel)}
                onChange={(checked) => setBranding((current) => ({ ...current, whiteLabel: checked }))}
              />
              <div className="space-y-2 border-t pt-4">
                <Label>Live branding preview</Label>
                <div className="relative aspect-[16/9] overflow-hidden rounded-xl border bg-muted">
                  {branding.coverUrl ? <img src={branding.coverUrl} alt="" className="absolute inset-0 h-full w-full object-cover" /> : null}
                  <div className="absolute inset-0 bg-black/45" />
                  <div className="relative flex h-full flex-col justify-between p-4 text-white">
                    {branding.logoUrl ? <img src={branding.logoUrl} alt="" className="max-h-10 max-w-32 object-contain" /> : <span className="font-bold">{branding.whiteLabel ? "" : "airpix"}</span>}
                    <div><p className="text-xl font-bold">{settingsQuery.data?.data?.title || "Event gallery"}</p><p className="text-xs text-white/75">{branding.footerText || branding.sponsorText || "Your live branded gallery"}</p></div>
                  </div>
                  {branding.watermarkUrl ? <img src={branding.watermarkUrl} alt="" className="absolute bottom-3 right-3 max-h-10 max-w-[35%] object-contain opacity-80" /> : null}
                </div>
              </div>
            </CardContent>
          </Card>
        </div>

        <Card>
          <CardHeader>
            <CardTitle>Album-level privacy</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            {(albumsQuery.data?.data || []).length === 0 ? (
              <p className="text-sm text-muted-foreground">
                No categories/albums yet.
              </p>
            ) : (
              (albumsQuery.data?.data || []).map((album) => (
                <div
                  key={album._id}
                  className="grid gap-3 rounded-xl border p-3 md:grid-cols-[1fr_180px_200px_1fr_auto] md:items-center"
                >
                  <div>
                    <p className="font-medium">{album.title}</p>
                    <p className="text-xs text-muted-foreground">
                      Override event privacy only when needed.
                    </p>
                  </div>
                  <Select
                    value={albumModes[album._id] || album.galleryVisibility || "inherit"}
                    onValueChange={(mode) =>
                      setAlbumModes((current) => ({
                        ...current,
                        [album._id]: mode,
                      }))
                    }
                  >
                    <SelectTrigger>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="inherit">Inherit event</SelectItem>
                      {accessModes.map(([value, label]) => (
                        <SelectItem key={value} value={value}>
                          {label.split(" - ")[0]}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  <Select
                    value={albumPolicies[album._id] || album.publishPolicy || "inherit"}
                    onValueChange={(policy) => setAlbumPolicies((current) => ({ ...current, [album._id]: policy }))}
                  >
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="inherit">Inherit publishing</SelectItem>
                      <SelectItem value="auto_upload">After upload</SelectItem>
                      <SelectItem value="auto_ai">After AI</SelectItem>
                      <SelectItem value="manual">Manual</SelectItem>
                    </SelectContent>
                  </Select>
                  <Input
                    type="password"
                    placeholder="Optional new album password"
                    value={albumPasswords[album._id] || ""}
                    onChange={(e) =>
                      setAlbumPasswords((current) => ({
                        ...current,
                        [album._id]: e.target.value,
                      }))
                    }
                  />
                  <Button
                    size="sm"
                    variant="outline"
                    onClick={() =>
                      albumMutation.mutate({
                        albumId: album._id,
                        mode: albumModes[album._id] || album.galleryVisibility || "inherit",
                        publishPolicy: albumPolicies[album._id] || album.publishPolicy || "inherit",
                      })
                    }
                  >
                    Save
                  </Button>
                </div>
              ))
            )}
          </CardContent>
        </Card>
      </div>
    </PlannerLayout>
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
    <div className="flex items-center justify-between gap-4 rounded-xl border p-3">
      <Label className="font-medium">{label}</Label>
      <Switch checked={checked} onCheckedChange={onChange} />
    </div>
  );
}

function AssetInput({
  label,
  value,
  loading,
  onFile,
}: {
  label: string;
  value?: string;
  loading: boolean;
  onFile: (file: File) => void;
}) {
  return (
    <div className="space-y-2">
      <Label>{label}</Label>
      <div className="flex items-center gap-3 rounded-xl border p-3">
        {value ? (
          <img
            src={value}
            alt=""
            className="h-12 w-16 rounded-lg object-cover"
          />
        ) : (
          <span className="flex h-12 w-16 items-center justify-center rounded-lg bg-muted">
            <ImageIcon className="h-5 w-5" />
          </span>
        )}
        <label className="flex-1 cursor-pointer">
          <input
            type="file"
            accept="image/*"
            className="hidden"
            disabled={loading}
            onChange={(e) => e.target.files?.[0] && onFile(e.target.files[0])}
          />
          <span className="inline-flex items-center text-sm font-semibold">
            {loading ? (
              <Loader2 className="mr-2 h-4 w-4 animate-spin" />
            ) : (
              <Upload className="mr-2 h-4 w-4" />
            )}
            {value ? "Replace" : "Upload"} {label.toLowerCase()}
          </span>
        </label>
      </div>
    </div>
  );
}

function ColorField({
  label,
  value,
  onChange,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
}) {
  return (
    <div className="space-y-2">
      <Label>{label}</Label>
      <div className="flex gap-2">
        <Input
          type="color"
          value={value}
          onChange={(e) => onChange(e.target.value)}
          className="h-10 w-14 p-1"
        />
        <Input value={value} onChange={(e) => onChange(e.target.value)} />
      </div>
    </div>
  );
}
