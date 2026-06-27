import { Suspense } from "react";
import { CreateClient } from "@/components/CreateClient";

export const dynamic = "force-dynamic";

export default function Page() {
  return (
    <Suspense fallback={<div className="p-6 text-sm text-[var(--color-mut)]">Loading…</div>}>
      <CreateClient />
    </Suspense>
  );
}
