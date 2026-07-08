/**
 * Server-side fetch helpers for the Feed Explorer — raw passthrough of the
 * TxODDS scores product. All calls run on the server with txlineHeaders()
 * (guest JWT + X-Api-Token); the token never reaches the browser.
 */
import { refreshJwt, txlineBase, txlineHeaders } from "@/lib/txline/auth";
import type { LogResponse, RawFixture, RawRecord } from "./types";

/** GET with one JWT refresh retry on 401 (guest JWTs expire). */
async function get(path: string, accept = "application/json"): Promise<Response> {
  const url = `${txlineBase()}${path}`;
  let res = await fetch(url, { headers: await txlineHeaders({ Accept: accept }), cache: "no-store" });
  if (res.status === 401) {
    await refreshJwt();
    res = await fetch(url, { headers: await txlineHeaders({ Accept: accept }), cache: "no-store" });
  }
  return res;
}

export async function fetchFixturesForDay(epochDay: number): Promise<RawFixture[]> {
  const res = await get(`/api/fixtures/snapshot?startEpochDay=${epochDay}&competitionId=72`);
  if (!res.ok) return [];
  const data = await res.json();
  return Array.isArray(data) ? data : (data?.fixtures ?? []);
}

export async function fetchRawSnapshot(fixtureId: string | number): Promise<RawRecord[]> {
  const res = await get(`/api/scores/snapshot/${fixtureId}`);
  if (!res.ok) throw new Error(`snapshot ${fixtureId} -> ${res.status}`);
  const data = await res.json();
  return Array.isArray(data) ? data : [];
}

/**
 * Parse the /api/scores/updates payload. It LOOKS like SSE ("data: {...}"
 * frames separated by blank lines) but is a finite text document — the full
 * chronological match log (~1,100+ records). Never EventSource it.
 */
export function parseSseLog(text: string): RawRecord[] {
  const records: RawRecord[] = [];
  for (const frame of text.split(/\n\n/)) {
    if (frame.includes("event: heartbeat")) continue;
    for (const line of frame.split("\n")) {
      if (!line.startsWith("data:")) continue;
      try {
        records.push(JSON.parse(line.slice(5).trim()));
      } catch {
        /* skip malformed frame */
      }
    }
  }
  return records;
}

export async function fetchFullLog(fixtureId: string | number): Promise<LogResponse> {
  const res = await get(`/api/scores/updates/${fixtureId}`, "text/event-stream");
  if (!res.ok) throw new Error(`updates ${fixtureId} -> ${res.status}`);
  const records = parseSseLog(await res.text());
  // chronological: the feed is seq-ordered but be defensive
  records.sort((a, b) => (a.Seq ?? 0) - (b.Seq ?? 0));
  const actionCounts: Record<string, number> = {};
  for (const r of records) {
    const a = r.Action ?? "unknown";
    actionCounts[a] = (actionCounts[a] ?? 0) + 1;
  }
  return { fixtureId: Number(fixtureId), count: records.length, actionCounts, records };
}

/** Open the live raw stream upstream; caller pumps res.body. */
export async function openRawStream(fixtureId: string | number, signal?: AbortSignal): Promise<Response> {
  const url = `${txlineBase()}/api/scores/stream?fixtureId=${fixtureId}`;
  let res = await fetch(url, { headers: await txlineHeaders({ Accept: "text/event-stream" }), signal, cache: "no-store" });
  if (res.status === 401) {
    await refreshJwt();
    res = await fetch(url, { headers: await txlineHeaders({ Accept: "text/event-stream" }), signal, cache: "no-store" });
  }
  return res;
}
