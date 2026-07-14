"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { TopBar } from "@/components/TopBar";
import { FixtureRow } from "@/components/FixtureRow";
import { api } from "@/lib/client/api";
import type { Fixture } from "@/lib/txline/types";
import type { RoomSummary } from "@/lib/store/rooms";

export function HomeClient() {
  const router = useRouter();
  const [fixtures, setFixtures] = useState<Fixture[]>([]);
  const [rooms, setRooms] = useState<RoomSummary[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    api.fixtures().then((r) => setFixtures(r.fixtures)).finally(() => setLoading(false));
    const load = () => api.listRooms().then((r) => setRooms(r.rooms)).catch(() => {});
    load();
    const t = setInterval(load, 5000);
    return () => clearInterval(t);
  }, []);

  async function watchFeatured(fixtureId: string) {
    try {
      const { roomId } = await api.watch(fixtureId, { name: "Fan" });
      router.push(`/room/${roomId}`);
    } catch {
      /* not watchable yet */
    }
  }

  const live = fixtures.filter((f) => f.status === "live");
  const upcoming = fixtures.filter((f) => f.status === "scheduled").slice(0, 8);
  const featured = (live[0] ?? upcoming[0] ?? fixtures[0])?.id;

  return (
    <div className="pb-16">
      <TopBar />

      <main className="px-4">
        {/* Hero */}
        <section className="card mt-4 overflow-hidden p-5">
          <div className="mb-2 flex flex-wrap items-center gap-2">
            <span className="chip text-[var(--color-lime)]">World Cup 2026</span>
            <span className="chip">Verified by TxLINE on Solana</span>
          </div>
          <h1 className="text-2xl font-extrabold leading-tight">
            Watch the World Cup <span className="text-[var(--color-lime)]">together.</span>
          </h1>
          <p className="mt-2 text-sm text-[var(--color-mut)]">
            One global live room per match — the whole crowd together. Real-time match pulse, a room
            prediction game, and an AI recap — all reacting to verified TxLINE data as it happens.
          </p>
          <div className="mt-4 flex gap-2">
            <button
              className="btn btn-primary flex-1"
              disabled={!featured}
              onClick={() => featured && watchFeatured(featured)}
            >
              ▶ Watch the featured match
            </button>
          </div>
          <Link href="/explorer" className="mt-2 block text-center text-xs text-[var(--color-mut)] hover:text-[var(--color-lime)]">
            Feed Explorer — see every field the oracle publishes →
          </Link>
        </section>

        {/* Active rooms */}
        {rooms.length > 0 && (
          <section className="mt-6">
            <h2 className="mb-2 text-sm font-bold uppercase tracking-wider text-[var(--color-mut)]">
              Active rooms
            </h2>
            <div className="space-y-2">
              {rooms.map((r) => (
                <Link
                  key={r.id}
                  href={`/room/${r.id}`}
                  className="card flex items-center justify-between p-3 transition hover:border-[var(--color-lime)]/50"
                >
                  <div className="min-w-0">
                    <div className="truncate text-sm font-semibold">{r.name}</div>
                    <div className="text-[11px] text-[var(--color-mut)]">
                      {r.fixture.home.flag} {r.fixture.home.code} vs {r.fixture.away.code} {r.fixture.away.flag} ·{" "}
                      {r.memberCount} in room
                    </div>
                  </div>
                  <span className={`chip ${r.status === "live" ? "text-[var(--color-lime)]" : ""}`}>
                    {r.status === "live" ? "LIVE" : r.status === "finished" ? "FT" : "Lobby"}
                  </span>
                </Link>
              ))}
            </div>
          </section>
        )}

        {/* Fixtures */}
        <section className="mt-6">
          <h2 className="mb-2 text-sm font-bold uppercase tracking-wider text-[var(--color-mut)]">
            {live.length ? "Live & upcoming" : "Upcoming matches"}
          </h2>
          {loading ? (
            <div className="space-y-2">
              {[0, 1, 2].map((i) => (
                <div key={i} className="card h-16 shimmer" />
              ))}
            </div>
          ) : (
            <div className="space-y-2">
              {[...live, ...upcoming].map((f) => (
                <FixtureRow key={f.id} fixture={f} />
              ))}
            </div>
          )}
        </section>

        <p className="mt-8 text-center text-[11px] leading-relaxed text-[var(--color-mut)]">
          Powered by <span className="text-white">TxLINE</span> live football data · sign-in with Solana
          <br />
          Skill-based predictions — points & streaks only, no cash staking.
        </p>
      </main>
    </div>
  );
}
