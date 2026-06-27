"use client";

import { useEffect, useRef, useState } from "react";
import type { RoomView } from "@/lib/store/types";

/** Subscribe to a room's SSE stream and keep the latest RoomView in state. */
export function useRoomStream(roomId: string | null) {
  const [room, setRoom] = useState<RoomView | null>(null);
  const [connected, setConnected] = useState(false);
  const esRef = useRef<EventSource | null>(null);

  useEffect(() => {
    if (!roomId) return;
    let stopped = false;

    function open() {
      if (stopped) return;
      const es = new EventSource(`/api/rooms/${roomId}/stream`);
      esRef.current = es;
      es.onopen = () => setConnected(true);
      es.onmessage = (ev) => {
        try {
          const msg = JSON.parse(ev.data) as { type: string; room?: RoomView };
          if (msg.type === "state" && msg.room) setRoom(msg.room);
        } catch {
          /* ignore */
        }
      };
      es.onerror = () => {
        setConnected(false);
        es.close();
        // reconnect with a short backoff
        if (!stopped) setTimeout(open, 1500);
      };
    }
    open();

    return () => {
      stopped = true;
      esRef.current?.close();
    };
  }, [roomId]);

  return { room, connected };
}
