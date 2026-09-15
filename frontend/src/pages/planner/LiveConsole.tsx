import { useEffect, useMemo, useState } from "react";
import { Link, useParams } from "react-router-dom";
import {
  ArrowLeft,
  Camera,
  CheckCircle2,
  CircleAlert,
  Loader2,
  Radio,
  ShieldCheck,
  UploadCloud,
  type LucideIcon,
} from "lucide-react";
import { useQueryWrapper } from "@/api-hooks/react-query-wrapper";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Progress } from "@/components/ui/progress";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import PlannerLayout from "./PlannerLayout";

type TransferRow = {
  _id: string;
  clientTransferId: string;
  filename: string;
  source?: string;
  cameraId?: string;
  status: string;
  progress?: number;
  bytesSent?: number;
  bytesTotal?: number;
  bytesPerSecond?: number;
  error?: string;
  imageUrl?: string;
  createdAt?: string;
  updatedAt?: string;
  photographerId?: { name?: string; email?: string; userId?: string } | string;
  albumId?: { title?: string } | string;
};

type TransferResponse = {
  data: TransferRow[];
  totalItems: number;
  summary: Record<string, number>;
};

type UploadSessionRow = {
  _id: string;
  source: string;
  cameraId?: string;
  transferCount?: number;
  startedAt?: string;
  lastSeenAt?: string;
  isLive?: boolean;
  photographerId?: { name?: string; email?: string } | string;
  albumId?: { title?: string } | string;
};

type UploadSessionResponse = {
  data: UploadSessionRow[];
  totalItems: number;
  activeItems: number;
};

type EventResponse = {
  _id: string;
  title: string;
  description?: string;
};
type RetouchSummaryResponse = { summary: Record<string, number> };

type Filter = "all" | "uploading" | "processing" | "delivered" | "failed";

const baseUrl = import.meta.env.VITE_BASE_URL ?? "";

const formatTransferRate = (bytesPerSecond = 0) => {
  if (bytesPerSecond <= 0) return "";
  if (bytesPerSecond >= 1024 * 1024) {
    return `${(bytesPerSecond / (1024 * 1024)).toFixed(1)} MB/s`;
  }
  if (bytesPerSecond >= 1024) {
    return `${(bytesPerSecond / 1024).toFixed(0)} KB/s`;
  }
  return `${Math.round(bytesPerSecond)} B/s`;
};

const formatElapsed = (started?: string, ended?: string) => {
  if (!started) return "-";
  const ms = Math.max(0, new Date(ended || Date.now()).getTime() - new Date(started).getTime());
  const seconds = Math.floor(ms / 1000);
  if (seconds < 60) return `${seconds}s`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ${seconds % 60}s`;
  const hours = Math.floor(minutes / 60);
  return `${hours}h ${minutes % 60}m`;
};
export default function LiveConsole() {
  const { eventId = "" } = useParams();
  const [rows, setRows] = useState<TransferRow[]>([]);
  const [filter, setFilter] = useState<Filter>("all");
  const [connected, setConnected] = useState(false);
  const [sessionVersion, setSessionVersion] = useState(0);

  const transfers = useQueryWrapper<TransferResponse>(
    ["transfer-status", eventId],
    `/transfer-status?eventId=${eventId}&limit=1000`,
    { withToken: true, withCredentials: true, enabled: Boolean(eventId) },
  );
  const event = useQueryWrapper<EventResponse>(
    ["planner-event", eventId],
    `/event/get-one?id=${eventId}`,
    { withToken: true, withCredentials: true, enabled: Boolean(eventId) },
  );
  const sessions = useQueryWrapper<UploadSessionResponse>(
    ["upload-sessions", eventId, sessionVersion],
    `/upload-sessions?eventId=${eventId}`,
    { withToken: true, withCredentials: true, enabled: Boolean(eventId) },
  );
  const retouch = useQueryWrapper<RetouchSummaryResponse>(
    ["live-retouch-summary", eventId],
    eventId ? `/retouch/jobs?eventId=${eventId}&limit=1` : "/retouch/jobs?eventId=000000000000000000000000",
    { withToken: true, withCredentials: true, enabled: Boolean(eventId), refetchInterval: 3000 },
  );
  useEffect(() => {
    if (transfers.data?.data) setRows(transfers.data.data);
  }, [transfers.data?.data]);

  useEffect(() => {
    if (!eventId) return;
    const source = new EventSource(
      `${baseUrl}/transfer-status/stream?eventId=${encodeURIComponent(eventId)}`,
      { withCredentials: true },
    );
    source.onopen = () => setConnected(true);
    source.onerror = () => setConnected(false);
    source.addEventListener("transfer", (message) => {
      try {
        const payload = JSON.parse((message as MessageEvent).data) as {
          data?: TransferRow;
        };
        const incoming = payload?.data;
        if (!incoming?.clientTransferId) return;
        if (incoming.status === "detected") {
          setSessionVersion((value) => value + 1);
        }
        setRows((current) => {
          const index = current.findIndex(
            (row) => row.clientTransferId === incoming.clientTransferId,
          );
          if (index === -1) return [incoming, ...current].slice(0, 1000);
          const next = [...current];
          next[index] = incoming;
          return next;
        });
      } catch {
        // Ignore malformed heartbeat/event data and keep the console alive.
      }
    });
    return () => source.close();
  }, [eventId]);

  const summary = useMemo(() => {
    const count = (status: string) =>
      rows.filter((row) => row.status === status).length;
    return {
      incoming: rows.filter((row) =>
        ["detected", "stored", "queued"].includes(row.status),
      ).length,
      uploading: count("uploading"),
      processing: count("processing"),
      delivered: count("delivered") + count("published"),
      failed: count("failed"),
    };
  }, [rows]);

  const retouchSummary = retouch.data?.summary || {};
  const retouchWaiting = ["incoming", "assigned", "downloaded", "retouching", "ready_for_review", "rejected"]
    .reduce((total, key) => total + Number(retouchSummary[key] || 0), 0);

  const metrics: Array<{ label: string; value: number; icon: LucideIcon }> = [
    { label: "Incoming", value: summary.incoming, icon: UploadCloud },
    { label: "Uploading", value: summary.uploading, icon: Loader2 },
    { label: "Processing", value: summary.processing, icon: Loader2 },
    { label: "Delivered", value: summary.delivered, icon: CheckCircle2 },
    { label: "Retouch / review", value: retouchWaiting, icon: Camera },
    { label: "Failed", value: summary.failed, icon: CircleAlert },
  ];
  const activeSessions = (sessions.data?.data || []).filter(
    (session) => session.isLive,
  );

  const visibleRows = useMemo(() => {
    if (filter === "all") return rows;
    if (filter === "delivered") {
      return rows.filter((row) =>
        ["delivered", "published"].includes(row.status),
      );
    }
    return rows.filter((row) => row.status === filter);
  }, [filter, rows]);

  return (
    <PlannerLayout>
      <div className="space-y-5">
        <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
          <div className="flex items-center gap-3">
            <Button variant="outline" size="icon" asChild>
              <Link to="/planner/dashboard">
                <ArrowLeft className="h-4 w-4" />
              </Link>
            </Button>
            <div>
              <div className="flex items-center gap-2">
                <h1 className="text-2xl font-bold">
                  {event.data?.title || "Real-time photo status"}
                </h1>
                <Badge variant={connected ? "default" : "secondary"}>
                  <Radio className="mr-1 h-3.5 w-3.5" />
                  {connected ? "Live" : "Reconnecting"}
                </Badge>
              </div>
              <p className="mt-1 text-sm text-muted-foreground">
                Incoming, processing and delivered photos update without
                refreshing the browser.
              </p>
            </div>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <Button variant="outline" asChild>
              <Link to={`/planner/event/${eventId}/experience`}>
                <ShieldCheck className="mr-2 h-4 w-4" />
                Delivery & privacy
              </Link>
            </Button>
            <Badge variant="outline" className="w-fit">
              {rows.length} transfers tracked
            </Badge>
          </div>
        </div>

        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-6">
          {metrics.map(({ label, value, icon: Icon }) => (
            <Card key={label}>
              <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium">{label}</CardTitle>
                <Icon className="h-4 w-4 text-muted-foreground" />
              </CardHeader>
              <CardContent>
                <p className="text-2xl font-bold">{value}</p>
              </CardContent>
            </Card>
          ))}
        </div>

        <Card>
          <CardHeader className="pb-3">
            <div className="flex items-center justify-between gap-3">
              <div>
                <CardTitle className="text-base">
                  Live photographers & cameras
                </CardTitle>
                <p className="mt-1 text-sm text-muted-foreground">
                  Active shooting sessions seen during the last 45 minutes.
                </p>
              </div>
              <Badge variant="outline">{activeSessions.length} active</Badge>
            </div>
          </CardHeader>
          <CardContent>
            {activeSessions.length === 0 ? (
              <p className="rounded-xl border border-dashed p-4 text-sm text-muted-foreground">
                No active camera session yet. It appears here as soon as a
                photographer starts a transfer.
              </p>
            ) : (
              <div className="flex flex-wrap gap-2">
                {activeSessions.map((session) => {
                  const photographer =
                    typeof session.photographerId === "object"
                      ? session.photographerId?.name ||
                        session.photographerId?.email ||
                        "Photographer"
                      : "Photographer";
                  const category =
                    typeof session.albumId === "object"
                      ? session.albumId?.title
                      : undefined;
                  return (
                    <div
                      key={session._id}
                      className="flex items-center gap-3 rounded-xl border px-3 py-2"
                    >
                      <span className="flex h-8 w-8 items-center justify-center rounded-lg bg-muted">
                        <Camera className="h-4 w-4" />
                      </span>
                      <div>
                        <p className="text-sm font-semibold">{photographer}</p>
                        <p className="text-xs text-muted-foreground">
                          {session.source || "camera"}
                          {session.cameraId ? ` · ${session.cameraId}` : ""}
                          {category ? ` · ${category}` : ""} ·{" "}
                          {session.transferCount || 0} photos
                        </p>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="gap-4">
            <div className="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
              <div>
                <CardTitle>Photo pipeline</CardTitle>
                <p className="mt-1 text-sm text-muted-foreground">
                  Every device and photographer feeds this same event workflow.
                </p>
              </div>
              <Tabs
                value={filter}
                onValueChange={(value) => setFilter(value as Filter)}
              >
                <TabsList className="flex flex-wrap">
                  <TabsTrigger value="all">All</TabsTrigger>
                  <TabsTrigger value="uploading">Uploading</TabsTrigger>
                  <TabsTrigger value="processing">Processing</TabsTrigger>
                  <TabsTrigger value="delivered">Delivered</TabsTrigger>
                  <TabsTrigger value="failed">Failed</TabsTrigger>
                </TabsList>
              </Tabs>
            </div>
          </CardHeader>
          <CardContent>
            {transfers.isLoading && rows.length === 0 ? (
              <div className="flex min-h-52 items-center justify-center">
                <Loader2 className="h-7 w-7 animate-spin" />
              </div>
            ) : visibleRows.length === 0 ? (
              <div className="flex min-h-52 flex-col items-center justify-center rounded-xl border border-dashed text-center">
                <Camera className="mb-3 h-9 w-9 text-muted-foreground" />
                <p className="font-semibold">No photos in this status yet</p>
                <p className="mt-1 text-sm text-muted-foreground">
                  Start shooting from the photographer app and transfers appear
                  here.
                </p>
              </div>
            ) : (
              <div className="overflow-x-auto rounded-xl border">
                <table className="w-full min-w-[980px] text-sm">
                  <thead className="bg-muted/50 text-left text-xs uppercase tracking-wide text-muted-foreground">
                    <tr>
                      <th className="px-4 py-3">Photo</th>
                      <th className="px-4 py-3">Photographer</th>
                      <th className="px-4 py-3">Category</th>
                      <th className="px-4 py-3">Source</th>
                      <th className="px-4 py-3">Status</th>
                      <th className="px-4 py-3">Progress</th>
                      <th className="px-4 py-3">Elapsed</th>
                      <th className="px-4 py-3">Updated</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y">
                    {visibleRows.map((row) => {
                      const photographer =
                        typeof row.photographerId === "object"
                          ? row.photographerId?.name ||
                            row.photographerId?.email ||
                            "Photographer"
                          : "Photographer";
                      const category =
                        typeof row.albumId === "object"
                          ? row.albumId?.title || "All"
                          : "All";
                      return (
                        <tr
                          key={row.clientTransferId}
                          className="bg-background align-middle"
                        >
                          <td className="px-4 py-3">
                            <div className="flex items-center gap-3">
                              <div className="h-10 w-10 overflow-hidden rounded-lg bg-muted">
                                {row.imageUrl ? (
                                  <img
                                    src={row.imageUrl}
                                    alt=""
                                    className="h-full w-full object-cover"
                                  />
                                ) : null}
                              </div>
                              <div className="min-w-0">
                                <p className="max-w-52 truncate font-medium">
                                  {row.filename}
                                </p>
                                {row.error ? (
                                  <p className="max-w-52 truncate text-xs text-destructive">
                                    {row.error}
                                  </p>
                                ) : null}
                              </div>
                            </div>
                          </td>
                          <td className="px-4 py-3">{photographer}</td>
                          <td className="px-4 py-3">{category}</td>
                          <td className="px-4 py-3 text-muted-foreground">
                            <p>{row.source || "camera"}</p>
                            {row.cameraId ? (
                              <p className="mt-0.5 max-w-48 truncate text-[11px]">
                                {row.cameraId}
                              </p>
                            ) : null}
                          </td>
                          <td className="px-4 py-3">
                            <Badge
                              variant={
                                row.status === "failed"
                                  ? "destructive"
                                  : "secondary"
                              }
                            >
                              {row.status}
                            </Badge>
                          </td>
                          <td className="px-4 py-3">
                            <div className="w-40 space-y-1">
                              <div className="flex items-center gap-2">
                                <Progress
                                  value={row.progress || 0}
                                  className="h-1.5"
                                />
                                <span className="w-8 text-xs text-muted-foreground">
                                  {row.progress || 0}%
                                </span>
                              </div>
                              {row.status === "uploading" &&
                              row.bytesPerSecond ? (
                                <p className="text-[11px] text-muted-foreground">
                                  {formatTransferRate(row.bytesPerSecond)}
                                </p>
                              ) : null}
                            </div>
                          </td>
                          <td className="px-4 py-3 text-xs text-muted-foreground">
                            {formatElapsed(row.createdAt, row.updatedAt)}
                          </td>
                          <td className="px-4 py-3 text-xs text-muted-foreground">
                            {row.updatedAt
                              ? new Date(row.updatedAt).toLocaleTimeString()
                              : "Now"}
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    </PlannerLayout>
  );
}
