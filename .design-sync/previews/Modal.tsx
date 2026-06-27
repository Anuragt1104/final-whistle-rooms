import * as React from "react";
import { Modal } from "final-whistle-rooms";

// Modal is a fixed, full-screen overlay (dim backdrop + centered .card sheet),
// so it renders as a single card (see cfg.overrides.Modal). Shown here with the
// kind of content the app drops inside it — the "set your identity" sheet.
export function IdentitySheet() {
  return (
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
  );
}
