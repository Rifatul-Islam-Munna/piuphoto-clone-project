import { Toaster } from "@/components/ui/toaster";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { HashRouter, Routes, Route, Navigate } from "react-router-dom";
import { ReactNode } from "react";
import QueryClint from "../lib/QueryClint";
import Index from "./pages/Index";
import Login from "./pages/Login";
import Register from "./pages/Register";
import NotFound from "./pages/NotFound";
import Dashboard from "./pages/admin/Dashboard";
import Plans from "./pages/admin/Plans";
import Addons from "./pages/admin/Addons";
import Billing from "./pages/admin/Billing";
import Users from "./pages/admin/Users";
import Events from "./pages/admin/Events";
import AdminSettings from "./pages/admin/AdminSettings";
import UserDashboard from "./pages/user/UserDashboard";
import UserInvitations from "./pages/user/UserInvitations";
import UserSettings from "./pages/user/UserSettings";
import UserGallery from "./pages/user/UserGallery";
import UserMyPictures from "./pages/user/UserMyPictures";
import LiveConsole from "./pages/planner/LiveConsole";
import PhotographerDashboard from "./pages/photographer/PhotographerDashboard";
import PhotographerSessions from "./pages/photographer/PhotographerSessions";
import PhotographerPlans from "./pages/photographer/PhotographerPlans";
import JoinEvent from "./pages/photographer/JoinEvent";
import Pricing from "./pages/Pricing";
import EventLiveGallery from "./pages/public/EventLiveGallery";
import GallerySlugRedirect from "./pages/public/GallerySlugRedirect";
import DomainRoot from "./pages/public/DomainRoot";
import Phase2Settings from "./pages/planner/Phase2Settings";
import Phase2Gallery from "./pages/planner/Phase2Gallery";
import RetouchConsole from "./pages/retouch/RetouchConsole";
import StoreManager from "./pages/planner/StoreManager";
import AnalyticsDashboard from "./pages/planner/AnalyticsDashboard";
import ApiPlatform from "./pages/planner/ApiPlatform";
import Storefront from "./pages/public/Storefront";
import StoreOrder from "./pages/public/StoreOrder";
import { SiteSettingsProvider } from "./components/landing/site-settings-context";
import PrivacyPolicy from "./pages/PrivacyPolicy";
import TermsAndConditions from "./pages/TermsAndConditions";
import { useWorkspaceAccess } from "./hooks/use-workspace-access";

const ProtectedAdminRoute = ({ children }: { children: ReactNode }) => {
  const token = localStorage.getItem("access_token");
  const userStr = localStorage.getItem("user");
  const user = userStr ? JSON.parse(userStr) : null;

  if (!token) {
    return <Navigate to="/login" replace />;
  }

  if (user?.role !== "admin") {
    return <Navigate to="/" replace />;
  }

  return <>{children}</>;
};

const ProtectedUserRoute = ({ children }: { children: ReactNode }) => {
  const token = localStorage.getItem("access_token");
  const userStr = localStorage.getItem("user");
  const user = userStr ? JSON.parse(userStr) : null;

  if (!token) {
    return <Navigate to="/login" replace />;
  }

  if (user?.role === "admin") {
    return <Navigate to="/admin/dashboard" replace />;
  }

  return <>{children}</>;
};

type WorkspaceName = "planner" | "photographer" | "retoucher" | "reviewer";

const WorkspaceRoute = ({
  workspace,
  children,
}: {
  workspace: WorkspaceName | WorkspaceName[];
  children: ReactNode;
}) => {
  const token = localStorage.getItem("access_token");
  const userStr = localStorage.getItem("user");
  const user = userStr ? JSON.parse(userStr) : null;
  const access = useWorkspaceAccess();

  if (!token) return <Navigate to="/login" replace />;
  if (user?.role === "admin") return <Navigate to="/admin/dashboard" replace />;
  if (access.isLoading) {
    return <div className="flex min-h-screen items-center justify-center text-sm text-muted-foreground">Loading workspace...</div>;
  }

  const requested = Array.isArray(workspace) ? workspace : [workspace];
  const allowed = requested.some((name) => Boolean(access.data?.[name]));
  if (!allowed) {
    const fallback = access.data?.planner
      ? "/planner/dashboard"
      : access.data?.photographer
        ? "/photographer/dashboard"
        : access.data?.retoucher || access.data?.reviewer
          ? "/retouch"
          : "/login";
    return <Navigate to={fallback} replace />;
  }
  return <>{children}</>;
};
const WorkspaceRedirect = () => {
  const token = localStorage.getItem("access_token");
  const userStr = localStorage.getItem("user");
  const user = userStr ? JSON.parse(userStr) : null;
  if (!token) return <Navigate to="/login" replace />;
  if (user?.role === "admin") return <Navigate to="/admin/dashboard" replace />;
  if (user?.role === "photographer") {
    return <Navigate to="/photographer/dashboard" replace />;
  }
  return <Navigate to="/planner/dashboard" replace />;
};
const App = () => (
  <QueryClint>
    <TooltipProvider>
      <SiteSettingsProvider>
        <Toaster />
        <Sonner />
        <HashRouter>
          <Routes>
            <Route path="/" element={<DomainRoot />} />
            <Route path="/login" element={<Login />} />
            <Route path="/register" element={<Register />} />
            <Route path="/pricing" element={<Pricing />} />
            <Route path="/privacy-policy" element={<PrivacyPolicy />} />
            <Route
              path="/terms-and-conditions"
              element={<TermsAndConditions />}
            />
            <Route path="/g/:slug" element={<GallerySlugRedirect />} />
            <Route path="/store/:eventId" element={<Storefront />} />
            <Route path="/store/order/:orderId" element={<StoreOrder />} />
            <Route path="/event/:eventId" element={<EventLiveGallery />} />
            <Route
              path="/event/:eventId/album/:albumId"
              element={<EventLiveGallery />}
            />
            <Route
              path="/event/:eventId/image/:imageId"
              element={<EventLiveGallery />}
            />
            <Route
              path="/admin/dashboard"
              element={
                <ProtectedAdminRoute>
                  <Dashboard />
                </ProtectedAdminRoute>
              }
            />
            <Route
              path="/admin/plans"
              element={
                <ProtectedAdminRoute>
                  <Plans />
                </ProtectedAdminRoute>
              }
            />
            <Route
              path="/admin/addons"
              element={
                <ProtectedAdminRoute>
                  <Addons />
                </ProtectedAdminRoute>
              }
            />
            <Route
              path="/admin/billing"
              element={
                <ProtectedAdminRoute>
                  <Billing />
                </ProtectedAdminRoute>
              }
            />
            <Route
              path="/admin/users"
              element={
                <ProtectedAdminRoute>
                  <Users />
                </ProtectedAdminRoute>
              }
            />
            <Route
              path="/admin/events"
              element={
                <ProtectedAdminRoute>
                  <Events />
                </ProtectedAdminRoute>
              }
            />
            <Route
              path="/admin/settings"
              element={
                <ProtectedAdminRoute>
                  <AdminSettings />
                </ProtectedAdminRoute>
              }
            />
            <Route
              path="/planner/dashboard"
              element={
                <WorkspaceRoute workspace="planner">
                  <UserDashboard />
                </WorkspaceRoute>
              }
            />
            <Route
              path="/planner/events"
              element={
                <WorkspaceRoute workspace="planner">
                  <UserDashboard />
                </WorkspaceRoute>
              }
            />
            <Route
              path="/planner/live/:eventId"
              element={
                <WorkspaceRoute workspace="planner">
                  <LiveConsole />
                </WorkspaceRoute>
              }
            />
            <Route
              path="/planner/event/:eventId/experience"
              element={
                <WorkspaceRoute workspace={["planner", "photographer"]}>
                  <Phase2Settings />
                </WorkspaceRoute>
              }
            />
            <Route
              path="/planner/gallery"
              element={
                <WorkspaceRoute workspace={["planner", "photographer"]}>
                  <Phase2Gallery />
                </WorkspaceRoute>
              }
            />
            <Route
              path="/planner/store"
              element={
                <WorkspaceRoute workspace={["planner", "photographer"]}>
                  <StoreManager />
                </WorkspaceRoute>
              }
            />
            <Route
              path="/planner/analytics"
              element={
                <WorkspaceRoute workspace={["planner", "photographer"]}>
                  <AnalyticsDashboard />
                </WorkspaceRoute>
              }
            />
            <Route
              path="/planner/api"
              element={
                <WorkspaceRoute workspace={["planner", "photographer"]}>
                  <ApiPlatform />
                </WorkspaceRoute>
              }
            />
            <Route
              path="/retouch"
              element={
                <WorkspaceRoute workspace={["planner", "photographer", "retoucher", "reviewer"]}>
                  <RetouchConsole />
                </WorkspaceRoute>
              }
            />            <Route
              path="/planner/settings"
              element={
                <WorkspaceRoute workspace={["planner", "photographer"]}>
                  <UserSettings />
                </WorkspaceRoute>
              }
            />
            <Route path="/join/:code" element={<JoinEvent />} />
            <Route
              path="/photographer/dashboard"
              element={
                <WorkspaceRoute workspace="photographer">
                  <PhotographerDashboard />
                </WorkspaceRoute>
              }
            />
            <Route
              path="/photographer/invitations"
              element={
                <WorkspaceRoute workspace="photographer">
                  <PhotographerDashboard />
                </WorkspaceRoute>
              }
            />
            <Route
              path="/photographer/sessions"
              element={
                <WorkspaceRoute workspace="photographer">
                  <PhotographerSessions />
                </WorkspaceRoute>
              }
            />
            <Route
              path="/photographer/plans"
              element={
                <WorkspaceRoute workspace="photographer">
                  <PhotographerPlans />
                </WorkspaceRoute>
              }
            />
            <Route
              path="/user/dashboard"
              element={
                <WorkspaceRoute workspace="planner">
                  <UserDashboard />
                </WorkspaceRoute>
              }
            />
            <Route
              path="/user/events"
              element={
                <WorkspaceRoute workspace="planner">
                  <UserDashboard />
                </WorkspaceRoute>
              }
            />
            <Route
              path="/user/gallery"
              element={
                <WorkspaceRoute workspace="planner">
                  <UserGallery />
                </WorkspaceRoute>
              }
            />
            <Route
              path="/user/my-pictures"
              element={
                <ProtectedUserRoute>
                  <UserMyPictures />
                </ProtectedUserRoute>
              }
            />
            <Route
              path="/user/invitations"
              element={
                <ProtectedUserRoute>
                  <UserInvitations />
                </ProtectedUserRoute>
              }
            />
            <Route
              path="/user/settings"
              element={
                <WorkspaceRoute workspace="planner">
                  <UserSettings />
                </WorkspaceRoute>
              }
            />
            {/* ADD ALL CUSTOM ROUTES ABOVE THE CATCH-ALL "*" ROUTE */}
            <Route path="*" element={<NotFound />} />
          </Routes>
        </HashRouter>
      </SiteSettingsProvider>
    </TooltipProvider>
  </QueryClint>
);

export default App;
