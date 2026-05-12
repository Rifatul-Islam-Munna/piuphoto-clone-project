import { useState, type FormEvent } from "react";
import { Link, useNavigate } from "react-router-dom";
import { Apple, Camera, Image, Lock, Mail, Sparkles } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { useCommonMutationApi } from "../../api-hooks/use-api-mutation";

type LoginResponse = {
  message: string;
  access_token?: string;
  user: {
    _id: string;
    email: string;
    name?: string;
    role?: string;
    isActive?: boolean;
  };
};

const Login = () => {
  const navigate = useNavigate();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");

  const loginMutation = useCommonMutationApi<LoginResponse, { email: string; password: string }>({
    url: "/user/login",
    method: "POST",
    successMessage: "Login success",
    withCredentials: true,
    onSuccess: (data) => {
      if (data?.access_token) {
        window.localStorage.setItem("access_token", data.access_token);
      }
      if (data?.user) {
        window.localStorage.setItem("user", JSON.stringify(data.user));
      }

      if (data?.user?.role === "admin") {
        navigate("/admin/dashboard");
      } else {
        navigate("/user/dashboard");
      }
    },
  });

  const handleSubmit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    loginMutation.mutate({ email, password });
  };

  return (
    <div className="min-h-screen gradient-hero">
      <header className="border-b border-border bg-card/80 backdrop-blur-md">
        <div className="container-custom flex h-16 items-center justify-between">
          <Link to="/" className="flex items-center gap-2">
            <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-gradient-to-br from-primary to-secondary">
              <span className="text-lg font-bold text-primary-foreground">n</span>
            </div>
            <span className="text-xl font-bold text-foreground">nikofly</span>
          </Link>

          <Button variant="hero-outline" size="sm" asChild>
            <Link to="/">Home</Link>
          </Button>
        </div>
      </header>

      <main className="container-custom grid min-h-[calc(100vh-4rem)] items-center gap-10 py-10 lg:grid-cols-[minmax(0,1fr)_440px] lg:py-16">
        <section className="hidden lg:block">
          <div className="mb-5 inline-flex items-center gap-2 rounded-lg border border-primary/20 bg-card px-3 py-2 text-sm font-semibold text-primary">
            <Sparkles className="h-4 w-4" />
            Live event workspace
          </div>

          <h1 className="mb-5 max-w-xl text-5xl font-bold leading-tight text-foreground">
            Sign in to manage event photos in real time.
          </h1>
          <p className="max-w-lg text-lg leading-8 text-muted-foreground">
            Keep galleries, camera transfers, guest sharing, and client delivery ready from one quiet dashboard.
          </p>

          <div className="mt-10 grid max-w-2xl grid-cols-2 gap-4">
            <div className="rounded-lg border border-border bg-card p-5">
              <div className="mb-5 flex h-11 w-11 items-center justify-center rounded-lg bg-primary/10">
                <Camera className="h-5 w-5 text-primary" />
              </div>
              <p className="text-sm text-muted-foreground">Live uploads</p>
              <p className="mt-1 text-2xl font-bold text-foreground">8.4k</p>
            </div>

            <div className="rounded-lg border border-border bg-card p-5">
              <div className="mb-5 flex h-11 w-11 items-center justify-center rounded-lg bg-secondary/10">
                <Image className="h-5 w-5 text-secondary" />
              </div>
              <p className="text-sm text-muted-foreground">Shared galleries</p>
              <p className="mt-1 text-2xl font-bold text-foreground">126</p>
            </div>
          </div>
        </section>

        <section className="rounded-lg border border-border bg-card p-6 md:p-8">
          <div className="mb-8">
            <div className="mb-4 flex h-11 w-11 items-center justify-center rounded-lg bg-gradient-to-br from-primary to-secondary">
              <span className="text-xl font-bold text-primary-foreground">n</span>
            </div>
            <h2 className="text-3xl font-bold text-foreground">Welcome back</h2>
            <p className="mt-2 text-sm text-muted-foreground">Login to your nikofly account.</p>
          </div>

          <form className="space-y-5" onSubmit={handleSubmit}>
            <div className="space-y-2">
              <Label htmlFor="email">Email</Label>
              <div className="relative">
                <Mail className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
                <Input
                  id="email"
                  type="email"
                  autoComplete="email"
                  placeholder="you@example.com"
                  className="h-12 pl-10"
                  value={email}
                  onChange={(event) => setEmail(event.target.value)}
                />
              </div>
            </div>

            <div className="space-y-2">
              <Label htmlFor="password">Password</Label>
              <div className="relative">
                <Lock className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
                <Input
                  id="password"
                  type="password"
                  autoComplete="current-password"
                  placeholder="Enter password"
                  className="h-12 pl-10"
                  value={password}
                  onChange={(event) => setPassword(event.target.value)}
                />
              </div>
            </div>

            <div className="flex items-center justify-between gap-4 text-sm">
              <Label htmlFor="remember" className="flex items-center gap-2 font-normal text-muted-foreground">
                <Checkbox id="remember" />
                Remember me
              </Label>
              <a href="#" className="font-semibold text-primary hover:text-primary/80">
                Forgot?
              </a>
            </div>

            <Button type="submit" className="h-12 w-full" disabled={loginMutation.isPending}>
              {loginMutation.isPending ? "Logging in..." : "Login"}
            </Button>
          </form>

          <div className="my-6 flex items-center gap-3">
            <div className="h-px flex-1 bg-border" />
            <span className="text-xs font-semibold uppercase text-muted-foreground">or</span>
            <div className="h-px flex-1 bg-border" />
          </div>

          <Button variant="hero-outline" className="h-12 w-full gap-3">
            <Apple className="h-5 w-5" />
            Continue with Apple
          </Button>

          <p className="mt-6 text-center text-sm text-muted-foreground">
            New to nikofly?{" "}
            <a href="#" className="font-semibold text-primary hover:text-primary/80">
              Create account
            </a>
          </p>
        </section>
      </main>
    </div>
  );
};

export default Login;
