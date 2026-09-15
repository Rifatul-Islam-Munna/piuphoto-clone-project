import { useEffect, useRef } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Navigate, useNavigate, useParams } from "react-router-dom";
import { Camera, Loader2 } from "lucide-react";
import { PostRequestAxios } from "@/api-hooks/api-hooks";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { toast } from "sonner";

type JoinResponse = {
  message?: string;
  data?: {
    eventId?: { _id?: string; title?: string } | string;
  };
};

export default function JoinEvent() {
  const { code = "" } = useParams();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const attempted = useRef(false);
  const token = localStorage.getItem("access_token");

  const joinMutation = useMutation({
    mutationFn: async () => {
      const [response, error] = await PostRequestAxios<JoinResponse>(
        "/event-members/join",
        { code: code.trim().toUpperCase() },
        { withToken: true, withCredentials: true },
      );
      if (error || !response) {
        throw new Error(error?.message || "Could not join event");
      }
      return response;
    },
    onSuccess: (response) => {
      queryClient.invalidateQueries({ queryKey: ["workspace-access"] });
      queryClient.invalidateQueries({ queryKey: ["photographer-memberships"] });
      const event = response.data?.eventId;
      const title = typeof event === "object" ? event?.title : undefined;
      toast.success(title ? `Joined ${title}` : "Joined event as photographer");
      navigate("/photographer/dashboard", { replace: true });
    },
    onError: (error: Error) => toast.error(error.message),
  });

  useEffect(() => {
    if (!token || !code || attempted.current) return;
    attempted.current = true;
    joinMutation.mutate();
  }, [code, token]);

  if (!token) {
    const next = encodeURIComponent(`/join/${code}`);
    return <Navigate to={`/login?next=${next}`} replace />;
  }
  return (
    <main className="flex min-h-screen items-center justify-center bg-muted/30 p-4">
      <Card className="w-full max-w-md">
        <CardHeader>
          <div className="mb-2 flex h-11 w-11 items-center justify-center rounded-xl bg-primary/10 text-primary">
            <Camera className="h-5 w-5" />
          </div>
          <CardTitle>Joining event</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          {joinMutation.isPending ? (
            <div className="flex items-center gap-3 text-sm text-muted-foreground">
              <Loader2 className="h-5 w-5 animate-spin" />
              Adding this event to your Photographer workspace...
            </div>
          ) : joinMutation.isError ? (
            <Button className="w-full" onClick={() => joinMutation.mutate()}>
              Try join again
            </Button>
          ) : null}
        </CardContent>
      </Card>
    </main>
  );
}
