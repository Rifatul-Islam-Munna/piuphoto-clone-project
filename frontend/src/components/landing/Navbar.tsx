import { useState, useEffect } from "react";
import { Link, useLocation, useNavigate } from "react-router-dom";
import { Button } from "@/components/ui/button";
import { Menu, X, ChevronDown, Globe, LogOut, LayoutDashboard, User } from "lucide-react";
import { cn } from "@/lib/utils";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { useSiteSettings } from "./site-settings-context";

type UserInfo = {
  _id: string;
  name?: string;
  email: string;
  role: string;
};

const Navbar = () => {
  const [isOpen, setIsOpen] = useState(false);
  const [user, setUser] = useState<UserInfo | null>(null);
  const navigate = useNavigate();
  const location = useLocation();
  const { settings, language, setLanguage, t } = useSiteSettings();
  const brandLetter = settings.site.title?.trim()?.charAt(0)?.toLowerCase() || "n";

  useEffect(() => {
    const token = localStorage.getItem("access_token");
    const userStr = localStorage.getItem("user");
    if (token && userStr) {
      try {
        setUser(JSON.parse(userStr));
      } catch {
        localStorage.removeItem("user");
      }
    }
  }, []);

  const handleLogout = () => {
    localStorage.removeItem("access_token");
    localStorage.removeItem("user");
    setUser(null);
    navigate("/login");
  };

  const getInitials = (name: string | undefined, email: string) => {
    if (name) {
      return name.split(" ").map((item) => item[0]).join("").toUpperCase().slice(0, 2);
    }
    return email[0].toUpperCase();
  };

  const goToSection = (href: string) => {
    const sectionId = href.replace(/^#/, "");
    const scrollToSection = () => {
      const element = document.getElementById(sectionId);
      if (!element) return;
      element.scrollIntoView({ behavior: "smooth", block: "start" });
    };

    setIsOpen(false);

    if (location.pathname === "/") {
      scrollToSection();
      return;
    }

    navigate(`/?section=${sectionId}`);
    window.setTimeout(scrollToSection, 120);
  };

  return (
    <nav className="fixed top-0 left-0 right-0 z-50 bg-card/80 backdrop-blur-md border-b border-border">
      <div className="container-custom">
        <div className="flex items-center justify-between h-16 lg:h-20">
          <a href="#" className="flex items-center gap-2">
            {settings.site.logoUrl ? (
              <img
                src={settings.site.logoUrl}
                alt={settings.site.title}
                className="h-8 w-8 rounded-lg object-cover"
              />
            ) : (
              <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-primary to-secondary flex items-center justify-center">
                <span className="text-primary-foreground font-bold text-lg">{brandLetter}</span>
              </div>
            )}
            <span className="font-bold text-xl text-foreground">{settings.site.title}</span>
          </a>

          <div className="hidden lg:flex items-center gap-1">
            {settings.navbar.menuItems.map((item) => (
              item.href.startsWith("#") ? (
                <a
                  key={`${item.href}-${item.label.en}`}
                  href={item.href}
                  className="px-3 py-2 text-sm font-medium text-muted-foreground hover:text-foreground transition-colors"
                  onClick={(event) => {
                    event.preventDefault();
                    goToSection(item.href);
                  }}
                >
                  {t(item.label)}
                </a>
              ) : (
                <Link
                  key={`${item.href}-${item.label.en}`}
                  to={item.href}
                  className="px-3 py-2 text-sm font-medium text-muted-foreground hover:text-foreground transition-colors"
                >
                  {t(item.label)}
                </Link>
              )
            ))}
          </div>

          <div className="hidden lg:flex items-center gap-4">
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <button className="flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground transition-colors">
                  <Globe className="w-4 h-4" />
                  {language.toUpperCase()}
                  <ChevronDown className="w-3 h-3" />
                </button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end">
                <DropdownMenuItem onClick={() => setLanguage("en")}>EN</DropdownMenuItem>
                <DropdownMenuItem onClick={() => setLanguage("gr")}>GR</DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
            {user ? (
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <button className="flex items-center gap-2 hover:opacity-80 transition-opacity">
                    <Avatar className="h-9 w-9 cursor-pointer">
                      <AvatarFallback className="bg-primary text-primary-foreground text-sm">
                        {getInitials(user.name, user.email)}
                      </AvatarFallback>
                    </Avatar>
                  </button>
                </DropdownMenuTrigger>
                <DropdownMenuContent align="end" className="w-48">
                  <div className="px-3 py-2">
                    <p className="text-sm font-medium">{user.name || user.email}</p>
                    <p className="text-xs text-muted-foreground capitalize">{user.role}</p>
                  </div>
                  <DropdownMenuSeparator />
                  {user.role === "admin" && (
                    <DropdownMenuItem onClick={() => navigate("/admin/dashboard")}>
                      <LayoutDashboard className="mr-2 h-4 w-4" />
                      {t(settings.navbar.dashboardLabel)}
                    </DropdownMenuItem>
                  )}
                  <DropdownMenuItem onClick={() => navigate("/user/dashboard")}>
                    <User className="mr-2 h-4 w-4" />
                    {t(settings.navbar.profileLabel)}
                  </DropdownMenuItem>
                  <DropdownMenuSeparator />
                  <DropdownMenuItem onClick={handleLogout} className="text-red-600 focus:text-red-600">
                    <LogOut className="mr-2 h-4 w-4" />
                    {t(settings.navbar.logoutLabel)}
                  </DropdownMenuItem>
                </DropdownMenuContent>
              </DropdownMenu>
            ) : (
              <Button variant="default" size="default" asChild>
                <Link to="/login">{t(settings.navbar.loginLabel)}</Link>
              </Button>
            )}
          </div>

          <button
            onClick={() => setIsOpen(!isOpen)}
            className="lg:hidden p-2 text-foreground"
            aria-label="Toggle menu"
          >
            {isOpen ? <X className="w-6 h-6" /> : <Menu className="w-6 h-6" />}
          </button>
        </div>

        <div
          className={cn(
            "lg:hidden overflow-hidden transition-all duration-300",
            isOpen ? "max-h-[500px] pb-6" : "max-h-0",
          )}
        >
          <div className="flex flex-col gap-2 pt-4">
            {settings.navbar.menuItems.map((item) => (
              item.href.startsWith("#") ? (
                <a
                  key={`${item.href}-${item.label.en}`}
                  href={item.href}
                  className="px-4 py-3 text-foreground font-medium hover:bg-muted rounded-lg transition-colors"
                  onClick={(event) => {
                    event.preventDefault();
                    goToSection(item.href);
                  }}
                >
                  {t(item.label)}
                </a>
              ) : (
                <Link
                  key={`${item.href}-${item.label.en}`}
                  to={item.href}
                  className="px-4 py-3 text-foreground font-medium hover:bg-muted rounded-lg transition-colors"
                  onClick={() => setIsOpen(false)}
                >
                  {t(item.label)}
                </Link>
              )
            ))}
            <div className="flex items-center gap-4 px-4 pt-4 border-t border-border mt-2">
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <button className="flex items-center gap-1 text-sm text-muted-foreground">
                    <Globe className="w-4 h-4" />
                    {language.toUpperCase()}
                    <ChevronDown className="w-3 h-3" />
                  </button>
                </DropdownMenuTrigger>
                <DropdownMenuContent align="start">
                  <DropdownMenuItem onClick={() => setLanguage("en")}>EN</DropdownMenuItem>
                  <DropdownMenuItem onClick={() => setLanguage("gr")}>GR</DropdownMenuItem>
                </DropdownMenuContent>
              </DropdownMenu>
              {user ? (
                <div className="flex flex-1 flex-col gap-2">
                  <div className="flex items-center gap-2 px-3 py-2 bg-muted rounded-lg">
                    <Avatar className="h-7 w-7">
                      <AvatarFallback className="bg-primary text-primary-foreground text-xs">
                        {getInitials(user.name, user.email)}
                      </AvatarFallback>
                    </Avatar>
                    <div className="flex-1">
                      <p className="text-sm font-medium">{user.name || user.email}</p>
                      <p className="text-xs text-muted-foreground capitalize">{user.role}</p>
                    </div>
                  </div>
                  {user.role === "admin" && (
                    <Button variant="outline" onClick={() => { navigate("/admin/dashboard"); setIsOpen(false); }}>
                      <LayoutDashboard className="mr-2 h-4 w-4" />
                      {t(settings.navbar.dashboardLabel)}
                    </Button>
                  )}
                  <Button variant="destructive" onClick={handleLogout}>
                    <LogOut className="mr-2 h-4 w-4" />
                    {t(settings.navbar.logoutLabel)}
                  </Button>
                </div>
              ) : (
                <Button variant="default" className="flex-1" asChild>
                  <Link to="/login" onClick={() => setIsOpen(false)}>
                    {t(settings.navbar.loginLabel)}
                  </Link>
                </Button>
              )}
            </div>
          </div>
        </div>
      </div>
    </nav>
  );
};

export default Navbar;
