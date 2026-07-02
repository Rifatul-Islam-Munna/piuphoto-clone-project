import { Toaster } from "@/components/ui/toaster";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { HashRouter, Routes, Route, Navigate } from "react-router-dom";
import { ReactNode } from "react";
import QueryClint from "../lib/QueryClint";
import Index from "./pages/Index";
import Login from "./pages/Login";
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
import Pricing from "./pages/Pricing";
import EventPublicGallery from "./pages/public/EventPublicGallery";
import { SiteSettingsProvider } from "./components/landing/site-settings-context";
import PrivacyPolicy from "./pages/PrivacyPolicy";
import TermsAndConditions from "./pages/TermsAndConditions";

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

const App = () => (
  <QueryClint>
    <TooltipProvider>
      <SiteSettingsProvider>
        <Toaster />
        <Sonner />
        <HashRouter>
          <Routes>
          <Route path="/" element={<Index />} />
          <Route path="/login" element={<Login />} />
          <Route path="/pricing" element={<Pricing />} />
          <Route path="/privacy-policy" element={<PrivacyPolicy />} />
          <Route path="/terms-and-conditions" element={<TermsAndConditions />} />
          <Route path="/event/:eventId" element={<EventPublicGallery />} />
          <Route
            path="/event/:eventId/album/:albumId"
            element={<EventPublicGallery />}
          />
          <Route
            path="/event/:eventId/image/:imageId"
            element={<EventPublicGallery />}
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
            path="/user/dashboard"
            element={
              <ProtectedUserRoute>
                <UserDashboard />
              </ProtectedUserRoute>
            }
          />
          <Route
            path="/user/events"
            element={
              <ProtectedUserRoute>
                <UserDashboard />
              </ProtectedUserRoute>
            }
          />
          <Route
            path="/user/gallery"
            element={
              <ProtectedUserRoute>
                <UserGallery />
              </ProtectedUserRoute>
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
              <ProtectedUserRoute>
                <UserSettings />
              </ProtectedUserRoute>
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
