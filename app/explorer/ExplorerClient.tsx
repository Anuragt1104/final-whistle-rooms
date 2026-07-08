"use client";
import type { FixtureLite, LogResponse, RawRecord } from "@/lib/explorer/types";
import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import ActionDetail, { StructureDetail } from "./components/ActionDetail";
import CatalogSidebar from "./components/CatalogSidebar";
import LiveDashboard from "./components/LiveDashboard";
import MatchInspector from "./components/MatchInspector";
import RecordDetail from "./components/RecordDetail";

type CenterView = { kind: "timeline" } | { kind: "action"; action: string } | { kind: "structure"; id: string };

export default function ExplorerClient() {
  const [fixtures, setFixtures] = useState<FixtureLite[]>([]);
  const [fixture, setFixture] = useState<FixtureLite | null>(null);
  const [records, setRecords] = useState<RawRecord[]>([]);
  const [source, setSource] = useState<"none" | "snapshot" | "log">("none");
  const [loading, setLoading] = useState("");
  const [live, setLive] = useState(false);
  const [selected, setSelected] = useState<RawRecord | null>(null);
  const [center, setCenter] = useState<CenterView>({ kind: "timeline" });
  const [scrollToSeq, setScrollToSeq] = useState<number | null>(null);
  const [cursor, setCursor] = useState<number | null>(null); // replay position (record count), null = end
  const esRef = useRef<EventSource | null>(null);

  // fixtures on mount
  useEffect(() => {
    fetch("/api/explorer/fixtures")
      .then((r) => r.json())
      .then((d) => {
        const fx: FixtureLite[] = d.fixtures ?? [];
        setFixtures(fx);
        // default: the live match if any, else the freshest finished one
        const preferred = fx.find((f) => f.state === "live") ?? [...fx].reverse().find((f) => f.state === "finished") ?? fx[0] ?? null;
        if (preferred) selectFixture(preferred);
      })
      .catch(() => setLoading("Couldn't reach the feed — is TXLINE_API_TOKEN configured?"));
    return () => esRef.current?.close();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const stopLive = useCallback(() => {
    esRef.current?.close();
    esRef.current = null;
    setLive(false);
  }, []);

  const selectFixture = useCallback(
    async (f: FixtureLite) => {
      stopLive();
      setFixture(f);
      setRecords([]);
      setSelected(null);
      setCursor(null);
      setCenter({ kind: "timeline" });
      // instant view: the snapshot (latest record per action type)
      setLoading("Loading snapshot…");
      try {
        const snap = await fetch(`/api/explorer/snapshot/${f.fixtureId}`).then((r) => r.json());
        setRecords((snap.records ?? []).sort((a: RawRecord, b: RawRecord) => (a.Seq ?? 0) - (b.Seq ?? 0)));
        setSource("snapshot");
        setLoading("");
      } catch {
        setLoading("No records for this fixture yet (kickoff ahead).");
        setSource("none");
      }
    },
    [stopLive],
  );

  const loadFullLog = useCallback(async () => {
    if (!fixture) return;
    setLoading(`Loading full match log (~1MB)…`);
    try {
      const log: LogResponse = await fetch(`/api/explorer/log/${fixture.fixtureId}`).then((r) => r.json());
      setRecords(log.records ?? []);
      setSource("log");
      setLoading("");
    } catch {
      setLoading("Full log unavailable for this fixture (feed keeps logs ~2 weeks). Snapshot still shows every field.");
    }
  }, [fixture]);

  const goLive = useCallback(() => {
    if (!fixture || esRef.current) return;
    const es = new EventSource(`/api/explorer/live/${fixture.fixtureId}`);
    es.onmessage = (ev) => {
      try {
        const rec: RawRecord = JSON.parse(ev.data);
        setRecords((rs) => (rs.some((r) => r.Seq === rec.Seq && r.Id === rec.Id) ? rs : [...rs, rec]));
      } catch {
        /* skip malformed frame */
      }
    };
    es.onerror = () => {
      /* EventSource auto-reconnects; keep the badge */
    };
    esRef.current = es;
    setLive(true);
  }, [fixture]);

  // visible slice (replay cursor folds the world to "as of" that record)
  const visible = useMemo(() => (cursor == null ? records : records.slice(0, cursor)), [records, cursor]);
  const counts = useMemo(() => {
    const c: Record<string, number> = {};
    for (const r of visible) c[r.Action ?? "?"] = (c[r.Action ?? "?"] ?? 0) + 1;
    return c;
  }, [visible]);

  const jumpTo = useCallback((seq: number) => {
    setCenter({ kind: "timeline" });
    setScrollToSeq(seq);
    setTimeout(() => setScrollToSeq(null), 400);
  }, []);

  const canReplay = source === "log" && records.length > 10;

  return (
    <div className="explorer-root h-dvh flex flex-col bg-[#070b14] text-[#eaf1fb]">
      {/* top bar */}
      <header className="border-b border-[#243650] px-4 py-2.5 flex items-center gap-3 flex-wrap">
        <Link href="/" className="font-bold text-[15px]" style={{ color: "var(--color-lime)" }}>
          FINAL WHISTLE
        </Link>
        <span className="text-[13px] text-[#8aa0bd]">/ TxODDS Feed Explorer</span>
        <select
          value={fixture?.fixtureId ?? ""}
          onChange={(e) => {
            const f = fixtures.find((x) => x.fixtureId === Number(e.target.value));
            if (f) selectFixture(f);
          }}
          className="rounded-lg bg-[#141f33] border border-[#243650] px-2.5 py-1.5 text-[13px] outline-none min-w-[280px]"
        >
          {(["live", "finished", "upcoming"] as const).map((state) => {
            const group = fixtures.filter((f) => f.state === state);
            if (group.length === 0) return null;
            return (
              <optgroup key={state} label={state.toUpperCase()}>
                {group.map((f) => (
                  <option key={f.fixtureId} value={f.fixtureId}>
                    {f.home} v {f.away}
                    {f.score ? ` (${f.score.home}-${f.score.away})` : ""} · {new Date(f.startTime).toLocaleString([], { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" })} · #{f.fixtureId}
                  </option>
                ))}
              </optgroup>
            );
          })}
        </select>
        {fixture && (
          <span
            className="text-[10.5px] font-bold tracking-wider rounded-full px-2 py-0.5"
            style={{
              color: fixture.state === "live" ? "#070b14" : "#c8d5e8",
              background: fixture.state === "live" ? "#c7f24d" : "#141f33",
              border: "1px solid #243650",
            }}
          >
            {fixture.state.toUpperCase()}
          </span>
        )}
        <button
          onClick={loadFullLog}
          disabled={!fixture || source === "log"}
          className="text-[12.5px] rounded-lg border border-[#243650] px-3 py-1.5 hover:border-[#c7f24d] disabled:opacity-40"
        >
          {source === "log" ? `Full log · ${records.length} records` : "Load full match log"}
        </button>
        {fixture?.state === "live" &&
          (live ? (
            <button onClick={stopLive} className="text-[12.5px] rounded-lg border border-[#c7f24d] text-[#c7f24d] px-3 py-1.5">
              ■ Stop stream
            </button>
          ) : (
            <button onClick={goLive} className="text-[12.5px] rounded-lg bg-[#c7f24d] text-[#070b14] font-semibold px-3 py-1.5">
              ▶ Go live
            </button>
          ))}
        {source === "snapshot" && (
          <span className="text-[11.5px] text-[#8aa0bd]">snapshot = latest record per action type ({records.length})</span>
        )}
        {loading && <span className="text-[11.5px] text-[#ffd24a]">{loading}</span>}
      </header>

      <LiveDashboard fixture={fixture} records={visible} live={live} />

      {/* replay scrubber */}
      {canReplay && (
        <div className="border-b border-[#243650] px-4 py-1.5 flex items-center gap-3 bg-[#0b1220]">
          <span className="text-[10.5px] tracking-widest font-bold text-[#8aa0bd]">REPLAY</span>
          <input
            type="range"
            min={1}
            max={records.length}
            value={cursor ?? records.length}
            onChange={(e) => setCursor(Number(e.target.value) >= records.length ? null : Number(e.target.value))}
            className="flex-1 accent-[#c7f24d]"
          />
          <span className="text-[11.5px] text-[#8aa0bd] tabular-nums w-40 text-right">
            {cursor == null ? "full match" : `record ${cursor}/${records.length}`}
          </span>
          {cursor != null && (
            <button onClick={() => setCursor(null)} className="text-[11.5px] text-[#c7f24d] underline">
              jump to end
            </button>
          )}
        </div>
      )}

      {/* 3-column body */}
      <div className="flex-1 flex min-h-0">
        <CatalogSidebar
          counts={counts}
          selectedAction={center.kind === "action" ? center.action : null}
          selectedStructure={center.kind === "structure" ? center.id : null}
          onSelectAction={(a) => setCenter({ kind: "action", action: a })}
          onSelectStructure={(id) => setCenter({ kind: "structure", id })}
        />
        <main className="flex-1 min-w-0 border-r border-[#243650] flex flex-col min-h-0">
          {center.kind !== "timeline" && (
            <button onClick={() => setCenter({ kind: "timeline" })} className="text-left px-4 py-2 text-[12px] text-[#4aa3ff] border-b border-[#243650] hover:bg-[#0b1220]">
              ← back to the match timeline
            </button>
          )}
          {center.kind === "action" ? (
            <ActionDetail
              action={center.action}
              count={counts[center.action] ?? 0}
              instances={visible.filter((r) => r.Action === center.action)}
              onJumpTo={jumpTo}
            />
          ) : center.kind === "structure" ? (
            <StructureDetail id={center.id} />
          ) : (
            <MatchInspector records={visible} selectedSeq={selected?.Seq ?? null} onSelect={setSelected} scrollToSeq={scrollToSeq} />
          )}
        </main>
        <aside className="w-[400px] shrink-0 min-h-0 overflow-hidden">
          <RecordDetail record={selected} onViewSpec={(a) => setCenter({ kind: "action", action: a })} />
        </aside>
      </div>
    </div>
  );
}
