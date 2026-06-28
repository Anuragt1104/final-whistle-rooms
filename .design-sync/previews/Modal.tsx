import * as React from "react";
import { Modal } from "final-whistle-rooms";

// Modal is a fixed, full-screen overlay (dim backdrop + centered .card sheet),
// so it renders as a single card (see cfg.overrides.Modal — the viewport is
// ≥640px wide so the component's sm:items-center centering applies). The dark
// full-height wrapper stands in for the room content the dim sits over.
export function IdentitySheet() {
  return (
    <div
      style={{
        minHeight: "100vh",
        background:
          "radial-gradient(900px 500px at 50% -10%, #14233d 0%, rgba(20,35,61,0) 60%), linear-gradient(180deg, #0a1019 0%, #070b14 100%)",
        color: "#eaf1fb",
      }}
    >
      <Modal open title="Your room identity" onClose={() => {}}>
        <p className="text-[13px] text-[var(--color-mut)]">
          Pick a display name. We generate a device wallet so your picks and points are provably yours.
        </p>
        <div className="mt-3 space-y-2">
          <input className="input" defaultValue="Mariana" placeholder="Display name" />
          <div className="flex items-center justify-between rounded-lg bg-black/20 px-3 py-2 text-xs">
            <span className="text-[var(--color-mut)]">Device wallet</span>
            <span className="font-semibold">7Ftd…9kQ2</span>
          </div>
        </div>
        <button className="btn btn-primary mt-4 w-full">Connect &amp; continue</button>
      </Modal>
    </div>
  );
}
