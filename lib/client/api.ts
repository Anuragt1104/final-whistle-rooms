/** Thin typed client for the room API. */
import type { RoomView } from "@/lib/store/types";
import type { Fixture } from "@/lib/txline/types";
import type { RoomSummary } from "@/lib/store/rooms";

async function post<T>(url: string, body: unknown): Promise<T> {
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error((data as { error?: string }).error ?? `Request failed (${res.status})`);
  return data as T;
}
async function get<T>(url: string): Promise<T> {
  const res = await fetch(url, { cache: "no-store" });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error((data as { error?: string }).error ?? `Request failed (${res.status})`);
  return data as T;
}

export interface AppConfig {
  mode: "simulation" | "live";
  anchorConfigured: boolean;
  recapAI: boolean;
  cluster: string;
}

export const api = {
  config: () => get<AppConfig>("/api/config"),
  fixtures: () => get<{ fixtures: Fixture[] }>("/api/fixtures"),
  listRooms: () => get<{ rooms: RoomSummary[] }>("/api/rooms"),
  room: (id: string) => get<{ room: RoomView }>(`/api/rooms/${id}`),
  resolveCode: (code: string) => get<{ id: string }>(`/api/rooms/resolve?code=${encodeURIComponent(code)}`),
  createRoom: (body: {
    name: string;
    fixtureId: string;
    modes: { draft: boolean; nextSwing: boolean };
    hostName: string;
    hostWallet?: string;
  }) => post<{ roomId: string; hostId: string }>("/api/rooms", body),
  join: (id: string, body: { name: string; walletPubkey?: string }) =>
    post<{ memberId: string }>(`/api/rooms/${id}/join`, body),
  pickSide: (id: string, memberId: string, side: "home" | "away") =>
    post<{ ok: boolean }>(`/api/rooms/${id}/side`, { memberId, side }),
  start: (id: string, memberId: string) => post<{ ok: boolean }>(`/api/rooms/${id}/start`, { memberId }),
  predict: (id: string, memberId: string, promptId: string, optionKey: string) =>
    post<{ ok: boolean }>(`/api/rooms/${id}/predict`, { memberId, promptId, optionKey }),
  chat: (id: string, memberId: string, text: string, kind: "chat" | "reaction" = "chat") =>
    post<{ ok: boolean }>(`/api/rooms/${id}/chat`, { memberId, text, kind }),
  proof: (id: string) =>
    get<{
      root: string;
      leafCount: number;
      leaves: string[];
      sample: { leaf: string; index: number; proof: { hash: string; position: string }[]; verified: boolean } | null;
      anchored: boolean;
      anchorSignature?: string;
      anchorAvailable: boolean;
      cluster: string;
    }>(`/api/rooms/${id}/proof`),
  anchor: (id: string) => post<{ signature: string; explorerUrl: string }>(`/api/rooms/${id}/proof`, {}),
};
