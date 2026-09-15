import { type ReactNode } from "react";
import { Link, useLocation, useNavigate } from "react-router-dom";
import {
  BarChart3,
  CalendarDays,
  Camera,
  CreditCard,
  Images,
  Inbox,
  KeyRound,
  LogOut,
  Monitor,
  Scissors,
  Settings,
  ShoppingBag,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { useWorkspaceAccess } from "@/hooks/use-workspace-access";

type Props = { children: ReactNode };

const items = [
  {
    icon: Camera,
    label: "Shooting workspace",
    href: "/photographer/dashboard",
  },
  { icon: CalendarDays, label: "My sessions", href: "/photographer/sessions" },
  { icon: CreditCard, label: "Plans & billing", href: "/photographer/plans" },
  { icon: Inbox, label: "Invitations", href: "/photographer/invitations" },
  { icon: Images, label: "Galleries", href: "/planner/gallery" },
  { icon: Scissors, label: "Retouch", href: "/retouch" },
  { icon: ShoppingBag, label: "Store", href: "/planner/store" },
  { icon: BarChart3, label: "Analytics", href: "/planner/analytics" },
  { icon: KeyRound, label: "API", href: "/planner/api" },
  { icon: Settings, label: "Settings", href: "/planner/settings" },
];

export default function PhotographerLayout({ children }: Props) {
  const location = useLocation();
  const navigate = useNavigate();
  const workspaceAccess = useWorkspaceAccess();
  const userRaw = localStorage.getItem("user");
  const user = userRaw ? JSON.parse(userRaw) : null;

  const logout = () => {
    localStorage.removeItem("access_token");
    localStorage.removeItem("user");
    navigate("/login");
  };

  return (
    <div className="min-h-screen bg-muted/20">
      <header className="border-b bg-background">
        <div className="mx-auto flex h-16 max-w-[1500px] items-center justify-between px-4 sm:px-6">
          <Link
            to="/photographer/dashboard"
            className="flex items-center gap-3 font-bold"
          >
            <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-foreground text-background">
              <Camera className="h-5 w-5" />
            </span>
            <span>airpix photographer</span>
          </Link>
          <div className="flex items-center gap-2">
            <Button
              variant="outline"
              size="sm"
              onClick={() => navigate("/photographer/sessions")}
            >
              <CalendarDays className="mr-2 h-4 w-4" />
              {workspaceAccess.data?.planner ? "Solo sessions" : "Start solo work"}
            </Button>
            <Button variant="ghost" size="icon" onClick={logout}>
              <LogOut className="h-4 w-4" />
            </Button>
          </div>
        </div>
      </header>

      <div className="mx-auto grid w-full max-w-[1500px] gap-6 px-4 py-5 sm:px-6 lg:grid-cols-[230px_minmax(0,1fr)] lg:py-7">
        <aside className="h-fit rounded-2xl border bg-background p-3">
          <div className="mb-3 rounded-xl bg-muted/50 p-3">
            <p className="text-sm font-semibold">
              {user?.name || "Photographer"}
            </p>
            <p className="truncate text-xs text-muted-foreground">
              {user?.email || ""}
            </p>
          </div>
          <nav className="space-y-1">
            {items.map((item) => {
              const active =
                location.pathname === item.href ||
                location.pathname.startsWith(`${item.href}/`);
              return (
                <Link
                  key={item.href}
                  to={item.href}
                  className={cn(
                    "flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium",
                    active
                      ? "bg-foreground text-background"
                      : "text-muted-foreground hover:bg-muted hover:text-foreground",
                  )}
                >
                  <item.icon className="h-4 w-4" />
                  {item.label}
                </Link>
              );
            })}
          </nav>
          <div className="mt-4 border-t pt-4">
            <p className="mb-2 px-2 text-xs font-semibold uppercase tracking-wide text-muted-foreground">
              Camera transfer
            </p>
            <div className="flex items-start gap-2 rounded-xl bg-muted/40 p-3 text-xs text-muted-foreground">
              <Monitor className="mt-0.5 h-4 w-4 shrink-0" />
              Connect and shoot from the mobile app. This web workspace stays
              focused on assignments and delivery status.
            </div>
          </div>
        </aside>
        <main className="min-w-0">{children}</main>
      </div>
    </div>
  );
}


