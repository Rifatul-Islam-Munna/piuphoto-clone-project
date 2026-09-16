import { type ReactNode } from "react";
import PhotographerLayout from "@/pages/photographer/PhotographerLayout";
import PlannerLayout from "@/pages/planner/PlannerLayout";

type Props = { children: ReactNode };

export default function WorkspaceLayout({ children }: Props) {
  const raw = localStorage.getItem("user");
  const user = raw ? JSON.parse(raw) : null;

  return user?.role === "photographer" ? (
    <PhotographerLayout>{children}</PhotographerLayout>
  ) : (
    <PlannerLayout>{children}</PlannerLayout>
  );
}
