import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useNavigate } from "react-router-dom";
import { CalendarDays, Loader2, Plus, QrCode, Settings2, ShieldCheck } from "lucide-react";
import QRCode from "qrcode";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { useQueryWrapper } from "@/api-hooks/react-query-wrapper";
import { PostRequestAxios } from "@/api-hooks/api-hooks";
import { useWorkspaceAccess } from "@/hooks/use-workspace-access";
import PhotographerLayout from "./PhotographerLayout";

type Session = { _id: string; title: string; description?: string; isActive?: boolean; isPublished?: boolean; createdAt?: string };
type SessionsResponse = { data: Session[]; totalItems: number };

export default function PhotographerSessions() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const access = useWorkspaceAccess();
  const [open, setOpen] = useState(false);
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [qrSession, setQrSession] = useState<Session | null>(null);
  const [galleryQr, setGalleryQr] = useState("");
  const [faceQr, setFaceQr] = useState("");
  const sessions = useQueryWrapper<SessionsResponse>(["photographer-solo-sessions"], "/event/my-events?workspace=planner&page=1&limit=50", { withToken: true, withCredentials: true, enabled: Boolean(access.data?.planner) });
  const createSession = useMutation({
    mutationFn: async () => {
      const [response, error] = await PostRequestAxios<{ message: string; data: Session }>(
        "/event",
        { title: title.trim(), description: description.trim(), isPublished: true, autoPublishImages: true, requireReview: false },
        { withToken: true, withCredentials: true },
      );
      if (error || !response) throw new Error(error?.message || "Could not create session");
      return response;
    },
    onSuccess: () => {
      toast.success("Solo session created");
      setTitle(""); setDescription(""); setOpen(false);
      queryClient.invalidateQueries({ queryKey: ["photographer-solo-sessions"] });
    },
    onError: (error: Error) => toast.error(error.message),
  });

  const showQr = async (session: Session) => {
    const base = `${window.location.origin}${window.location.pathname}#/event/${session._id}`;
    const [gallery, face] = await Promise.all([
      QRCode.toDataURL(base, { width: 640, margin: 2 }),
      QRCode.toDataURL(`${base}?face=1`, { width: 640, margin: 2 }),
    ]);
    setQrSession(session); setGalleryQr(gallery); setFaceQr(face);
  };

  const downloadQr = (data: string, suffix: string) => {
    if (!qrSession || !data) return;
    const link = document.createElement("a");
    link.href = data; link.download = `${qrSession.title}-${suffix}.png`; link.click();
  };

  if (!access.isLoading && !access.data?.planner) {
    return <PhotographerLayout><Card className="border-primary/20"><CardContent className="p-8 text-center"><ShieldCheck className="mx-auto h-10 w-10" /><h1 className="mt-4 text-2xl font-bold">Create your own sessions</h1><p className="mx-auto mt-2 max-w-xl text-sm text-muted-foreground">You do not need an event-planner invitation. Activate a photographer plan that includes Create Events, then make street, portrait, wedding or mini sessions directly from your photographer workspace.</p><Button className="mt-5" onClick={() => navigate("/photographer/plans")}>View photographer plans</Button></CardContent></Card></PhotographerLayout>;
  }
  const rows = sessions.data?.data || [];

  return (
    <PhotographerLayout>
      <div className="space-y-6">
        <section className="flex flex-col gap-4 rounded-2xl border bg-background p-5 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <p className="text-sm font-medium text-muted-foreground">Independent photographer mode</p>
            <h1 className="mt-1 text-2xl font-bold">My solo sessions</h1>
            <p className="mt-2 max-w-2xl text-sm text-muted-foreground">Create street, portrait, wedding, sports or mini sessions yourself. No planner invitation is required. Each session gets a public gallery QR and a separate global face-delivery QR.</p>
          </div>
          <Button onClick={() => setOpen(true)}><Plus className="mr-2 h-4 w-4" />Create session</Button>
        </section>

        {sessions.isLoading ? (
          <div className="flex min-h-48 items-center justify-center rounded-2xl border bg-background"><Loader2 className="h-7 w-7 animate-spin" /></div>
        ) : rows.length === 0 ? (
          <Card><CardContent className="p-10 text-center"><CalendarDays className="mx-auto h-10 w-10 text-muted-foreground" /><h2 className="mt-4 text-lg font-semibold">No solo sessions yet</h2><p className="mt-1 text-sm text-muted-foreground">Create one and share its QR immediately with your client or people on the street.</p><Button className="mt-5" onClick={() => setOpen(true)}><Plus className="mr-2 h-4 w-4" />Create first session</Button></CardContent></Card>
        ) : (
          <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
            {rows.map((session) => (
              <Card key={session._id}>
                <CardHeader><CardTitle className="flex items-start justify-between gap-3"><span>{session.title}</span><span className="text-xs font-normal text-muted-foreground">{session.isActive === false ? "Inactive" : "Active"}</span></CardTitle></CardHeader>
                <CardContent className="space-y-4">
                  <p className="min-h-10 text-sm text-muted-foreground">{session.description || "Independent photo session"}</p>
                  <div className="grid gap-2 sm:grid-cols-2">
                    <Button variant="outline" onClick={() => showQr(session)}><QrCode className="mr-2 h-4 w-4" />Share QRs</Button>
                    <Button variant="outline" onClick={() => navigate(`/photographer/event/${session._id}/experience`)}><Settings2 className="mr-2 h-4 w-4" />Delivery settings</Button>
                  </div>
                  <Button className="w-full" onClick={() => window.open(`${window.location.origin}${window.location.pathname}#/event/${session._id}`, "_blank")}>
                    Open public gallery
                  </Button>
                </CardContent>
              </Card>
            ))}
          </div>
        )}
        <Dialog open={open} onOpenChange={setOpen}>
          <DialogContent>
            <DialogHeader><DialogTitle>Create solo session</DialogTitle><DialogDescription>This belongs to your photographer account. You can upload directly and manage delivery without accepting any invitation.</DialogDescription></DialogHeader>
            <div className="space-y-4 py-3">
              <div className="space-y-2"><Label htmlFor="solo-title">Session name</Label><Input id="solo-title" value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Street session - Marina Bay" /></div>
              <div className="space-y-2"><Label htmlFor="solo-description">Description</Label><Textarea id="solo-description" value={description} onChange={(e) => setDescription(e.target.value)} placeholder="Optional client or session note" /></div>
            </div>
            <DialogFooter><Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button><Button disabled={!title.trim() || createSession.isPending} onClick={() => createSession.mutate()}>{createSession.isPending ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : null}Create session</Button></DialogFooter>
          </DialogContent>
        </Dialog>

        <Dialog open={Boolean(qrSession)} onOpenChange={(next) => !next && setQrSession(null)}>
          <DialogContent className="max-w-2xl">
            <DialogHeader><DialogTitle>{qrSession?.title} sharing</DialogTitle><DialogDescription>Use the gallery QR when everyone should see the session. Use the face QR when a person should register 2-5 selfies, email and WhatsApp for their own automatically updated gallery.</DialogDescription></DialogHeader>
            <div className="grid gap-5 py-3 sm:grid-cols-2">
              <div className="rounded-xl border p-4 text-center"><p className="mb-3 font-semibold">Session gallery QR</p>{galleryQr ? <img className="mx-auto w-full max-w-56" src={galleryQr} alt="Session gallery QR" /> : null}<p className="mt-3 text-xs text-muted-foreground">Shows all published photos from this small session.</p><Button variant="outline" className="mt-3 w-full" onClick={() => downloadQr(galleryQr, "session-gallery")}>Download</Button></div>
              <div className="rounded-xl border border-primary/30 bg-primary/5 p-4 text-center"><p className="mb-3 font-semibold">Personal face-delivery QR</p>{faceQr ? <img className="mx-auto w-full max-w-56" src={faceQr} alt="Face delivery QR" /> : null}<p className="mt-3 text-xs text-muted-foreground">Creates or strengthens a global identity and sends future event matches by enabled channels.</p><Button className="mt-3 w-full" onClick={() => downloadQr(faceQr, "face-delivery")}>Download</Button></div>
            </div>
          </DialogContent>
        </Dialog>
      </div>
    </PhotographerLayout>
  );
}
