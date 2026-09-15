import { useState, type ReactNode } from "react";
import { Link, useLocation, useNavigate } from "react-router-dom";
import {
  BarChart3,
  CalendarDays,
  Camera,
  Images,
  Inbox,
  KeyRound,
  LayoutDashboard,
  LogOut,
  Menu,
  Scissors,
  Settings,
  ShoppingBag,
  Users,
  X,
} from "lucide-react";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { useWorkspaceAccess } from "@/hooks/use-workspace-access";

type PlannerLayoutProps = { children: ReactNode };

const plannerNavItems = [
  { icon: LayoutDashboard, label: "Overview", href: "/planner/dashboard" },
  { icon: CalendarDays, label: "Events & Team", href: "/planner/events" },
  { icon: Images, label: "Galleries", href: "/planner/gallery" },
  { icon: Scissors, label: "Retouch", href: "/retouch" },
  { icon: ShoppingBag, label: "Store", href: "/planner/store" },
  { icon: BarChart3, label: "Analytics", href: "/planner/analytics" },
  { icon: KeyRound, label: "API", href: "/planner/api" },
  { icon: Settings, label: "Settings", href: "/planner/settings" },
];

const photographerNavItems = [
  { icon: Camera, label: "Shooting workspace", href: "/photographer/dashboard" },
  { icon: Inbox, label: "Invitations", href: "/photographer/invitations" },
  { icon: Images, label: "Galleries", href: "/planner/gallery" },
  { icon: Scissors, label: "Retouch", href: "/retouch" },
  { icon: ShoppingBag, label: "Store", href: "/planner/store" },
  { icon: BarChart3, label: "Analytics", href: "/planner/analytics" },
  { icon: KeyRound, label: "API", href: "/planner/api" },
  { icon: Settings, label: "Settings", href: "/planner/settings" },
];

export default function PlannerLayout({ children }: PlannerLayoutProps) {
  const location = useLocation();
  const navigate = useNavigate();
  const [open, setOpen] = useState(false);
  const workspaceAccess = useWorkspaceAccess();
  const userRaw = localStorage.getItem("user");
  const user = userRaw ? JSON.parse(userRaw) : null;
  const isPhotographer = user?.role === "photographer";
  const navItems = isPhotographer ? photographerNavItems : plannerNavItems;
  const homeHref = isPhotographer ? "/photographer/dashboard" : "/planner/dashboard";

  const logout = () => {
    localStorage.removeItem("access_token");
    localStorage.removeItem("user");
    navigate("/login");
  };

  const initials = (user?.name || user?.email || "EP")
    .split(/\s+/)
    .map((part: string) => part[0])
    .join("")
    .slice(0, 2)
    .toUpperCase();

  const Navigation = ({ close }: { close?: () => void }) => (
    <nav className="space-y-1">
      {navItems.map((item) => {
        const active =
          location.pathname === item.href ||
          location.pathname.startsWith(`${item.href}/`);
        return (
          <Link
            key={item.href}
            to={item.href}
            onClick={close}
            className={cn(
              "flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium transition-colors",
              active
                ? "bg-primary text-primary-foreground"
                : "text-muted-foreground hover:bg-muted hover:text-foreground",
            )}
          >
            <item.icon className="h-4 w-4" />
            {item.label}
          </Link>
        );
      })}
    </nav>
  );

  return (
    <div className="min-h-screen bg-muted/20">
      <header className="sticky top-0 z-40 flex h-16 items-center justify-between border-b bg-background/95 px-4 backdrop-blur lg:hidden">
        <Button variant="ghost" size="icon" onClick={() => setOpen(true)}>
          <Menu className="h-5 w-5" />
        </Button>
        <Link to={homeHref} className="font-bold">
          {isPhotographer ? "airpix photographer" : "airpix planner"}
        </Link>
        <Button variant="ghost" size="icon" onClick={logout}>
          <LogOut className="h-5 w-5" />
        </Button>
      </header>

      {open && (
        <div
          className="fixed inset-0 z-50 bg-black/40 lg:hidden"
          onClick={() => setOpen(false)}
        >
          <aside
            className="h-full w-72 border-r bg-background p-4"
            onClick={(event) => event.stopPropagation()}
          >
            <div className="mb-6 flex items-center justify-between">
              <div>
                <p className="font-bold">{isPhotographer ? "Photographer" : "Event Planner"}</p>
                <p className="text-xs text-muted-foreground">
                  {isPhotographer ? "Photo delivery workspace" : "Operations workspace"}
                </p>
              </div>
              <Button
                variant="ghost"
                size="icon"
                onClick={() => setOpen(false)}
              >
                <X className="h-5 w-5" />
              </Button>
            </div>
            <Navigation close={() => setOpen(false)} />
          </aside>
        </div>
      )}

      <aside className="fixed inset-y-0 left-0 z-30 hidden w-72 border-r bg-background lg:flex lg:flex-col">
        <div className="flex h-16 items-center border-b px-5">
          <Link to={homeHref} className="flex items-center gap-3">
            <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-primary text-primary-foreground">
              {isPhotographer ? <Camera className="h-5 w-5" /> : <CalendarDays className="h-5 w-5" />}
            </div>
            <div>
              <p className="font-bold leading-none">airpix</p>
              <p className="mt-1 text-xs text-muted-foreground">
                {isPhotographer ? "Photographer" : "Event Planner"}
              </p>
            </div>
          </Link>
        </div>
        <div className="flex flex-1 flex-col overflow-y-auto p-4">
          <Navigation />
          <div className="mt-auto space-y-3 border-t pt-4">
            {isPhotographer && workspaceAccess.data?.planner ? (
              <Button
                variant="outline"
                className="w-full justify-start"
                onClick={() => navigate("/planner/dashboard")}
              >
                <CalendarDays className="mr-2 h-4 w-4" />
                Solo events
              </Button>
            ) : !isPhotographer && workspaceAccess.data?.photographer ? (
              <Button
                variant="outline"
                className="w-full justify-start"
                onClick={() => navigate("/photographer/dashboard")}
              >
                <Camera className="mr-2 h-4 w-4" />
                Photographer workspace
              </Button>
            ) : null}
            <div className="flex items-center gap-3 rounded-xl bg-muted/50 p-3">
              <Avatar className="h-9 w-9">
                <AvatarFallback>{initials}</AvatarFallback>
              </Avatar>
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-semibold">
                  {user?.name || "Event Planner"}
                </p>
                <p className="truncate text-xs text-muted-foreground">
                  {user?.email || ""}
                </p>
              </div>
            </div>
            <Button
              variant="ghost"
              className="w-full justify-start text-muted-foreground"
              onClick={logout}
            >
              <LogOut className="mr-2 h-4 w-4" />
              Logout
            </Button>
          </div>
        </div>
      </aside>

      <main className="lg:pl-72">
        <div className="mx-auto w-full max-w-[1500px] px-4 py-5 sm:px-6 lg:px-8 lg:py-7">
          {children}
        </div>
      </main>
    </div>
  );
}
