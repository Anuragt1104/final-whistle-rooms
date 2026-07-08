import { openRawStream } from "@/lib/explorer/txodds";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

/**
 * SSE proxy for the live raw scores stream. The browser EventSource connects
 * here; we hold the credentials server-side, filter upstream heartbeats, and
 * re-emit well-formed `data:` frames plus our own keepalive comments.
 */
export async function GET(req: Request, ctx: { params: Promise<{ fixtureId: string }> }) {
  const { fixtureId } = await ctx.params;
  if (!/^\d+$/.test(fixtureId)) {
    return new Response("fixtureId must be numeric", { status: 400 });
  }

  const upstream = await openRawStream(fixtureId, req.signal);
  if (!upstream.ok || !upstream.body) {
    return new Response(`upstream ${upstream.status}`, { status: 502 });
  }

  const enc = new TextEncoder();
  const reader = upstream.body.getReader();

  const stream = new ReadableStream({
    async start(controller) {
      const keepAlive = setInterval(() => {
        try {
          controller.enqueue(enc.encode(`: keepalive\n\n`));
        } catch {
          clearInterval(keepAlive);
        }
      }, 15_000);
      const dec = new TextDecoder();
      let buf = "";
      try {
        for (;;) {
          const { value, done } = await reader.read();
          if (done) break;
          buf += dec.decode(value, { stream: true });
          const frames = buf.split("\n\n");
          buf = frames.pop() ?? "";
          for (const f of frames) {
            if (f.includes("event: heartbeat")) continue;
            const d = f.split("\n").find((l) => l.startsWith("data:"));
            if (d) controller.enqueue(enc.encode(`data: ${d.slice(5).trim()}\n\n`));
          }
        }
      } catch {
        /* client disconnected or upstream dropped */
      } finally {
        clearInterval(keepAlive);
        try {
          controller.close();
        } catch {
          /* already closed */
        }
      }
    },
    cancel() {
      reader.cancel().catch(() => {});
    },
  });

  return new Response(stream, {
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
      "X-Accel-Buffering": "no",
    },
  });
}
