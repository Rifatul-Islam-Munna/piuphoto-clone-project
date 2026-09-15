import { useState, type FormEvent } from "react";
import { Link, useNavigate } from "react-router-dom";
import { Camera, Mail, Lock, UserRound } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { useCommonMutationApi } from "@/api-hooks/use-api-mutation";

type Role = "event_planner" | "photographer";
type CreateResponse = { message: string };

export default function Register() {
  const navigate = useNavigate();
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [role, setRole] = useState<Role>("photographer");
  const mutation = useCommonMutationApi<CreateResponse, { name: string; email: string; password: string; role: Role }>({
    url: "/user",
    method: "POST",
    successMessage: "Account created. Sign in to continue.",
    onSuccess: () => navigate("/login"),
  });

  const submit = (event: FormEvent) => {
    event.preventDefault();
    mutation.mutate({ name: name.trim(), email: email.trim(), password, role });
  };
  return (
    <div className="min-h-screen bg-muted/30 px-4 py-10">
      <div className="mx-auto w-full max-w-lg rounded-2xl border bg-background p-6 shadow-sm sm:p-8">
        <Link to="/" className="mb-7 flex items-center gap-2 text-lg font-bold">
          <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-foreground text-background"><Camera className="h-5 w-5" /></span>
          airpix
        </Link>
        <h1 className="text-3xl font-bold">Create your workspace</h1>
        <p className="mt-2 text-sm text-muted-foreground">Choose Photographer for solo sessions and assignments, or Event Planner for full event operations.</p>
        <form onSubmit={submit} className="mt-7 space-y-5">
          <div className="space-y-2">
            <Label htmlFor="register-name">Name</Label>
            <div className="relative"><UserRound className="absolute left-3 top-3.5 h-4 w-4 text-muted-foreground" /><Input id="register-name" className="h-11 pl-10" value={name} onChange={(e) => setName(e.target.value)} required minLength={3} /></div>
          </div>
          <div className="space-y-2">
            <Label htmlFor="register-email">Email</Label>
            <div className="relative"><Mail className="absolute left-3 top-3.5 h-4 w-4 text-muted-foreground" /><Input id="register-email" type="email" className="h-11 pl-10" value={email} onChange={(e) => setEmail(e.target.value)} required /></div>
          </div>
          <div className="space-y-2">
            <Label htmlFor="register-password">Password</Label>
            <div className="relative"><Lock className="absolute left-3 top-3.5 h-4 w-4 text-muted-foreground" /><Input id="register-password" type="password" className="h-11 pl-10" value={password} onChange={(e) => setPassword(e.target.value)} required minLength={7} /></div>
          </div>
          <div className="space-y-2">
            <Label>Account type</Label>
            <Select value={role} onValueChange={(value: Role) => setRole(value)}>
              <SelectTrigger className="h-11"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="photographer">Photographer</SelectItem>
                <SelectItem value="event_planner">Event Planner</SelectItem>
              </SelectContent>
            </Select>
            <p className="text-xs text-muted-foreground">
              Photographers can shoot assignments immediately. A plan with Create Events unlocks independent street/mini sessions without an invitation.
            </p>
          </div>
          <Button type="submit" className="h-11 w-full" disabled={mutation.isPending || !name.trim() || !email.trim() || password.length < 7}>
            {mutation.isPending ? "Creating account..." : "Create account"}
          </Button>
        </form>
        <p className="mt-6 text-center text-sm text-muted-foreground">
          Already have an account? <Link to="/login" className="font-semibold text-primary">Sign in</Link>
        </p>
      </div>
    </div>
  );
}
