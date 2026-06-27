import { subscribe } from "@/lib/store/rooms";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

/** Server-Sent Events stream of room state — the live transport for the room. */
export async function GET(req: Request, ctx: { params: Promise<{ id: string }> }) {
  const { id } = await ctx.params;
  const encoder = new TextEncoder();

  const stream = new ReadableStream({
    start(controller) {
      let keepAlive: ReturnType<typeof setInterval> | null = null;
      let closed = false;

      const send = (payload: string) => {
        if (closed) return;
        try {
          controller.enqueue(encoder.encode(`data: ${payload}\n\n`));
        } catch {
          /* client gone */
        }
      };

      const unsub = subscribe(id, send);
      if (!unsub) {
        controller.enqueue(encoder.encode(`event: error\ndata: {"error":"Room not found"}\n\n`));
        controller.close();
        return;
      }

      keepAlive = setInterval(() => {
        if (closed) return;
        try {
          controller.enqueue(encoder.encode(`: keepalive\n\n`));
        } catch {
          /* ignore */
        }
      }, 15000);

      const close = () => {
        if (closed) return;
        closed = true;
        if (keepAlive) clearInterval(keepAlive);
        unsub();
        try {
          controller.close();
        } catch {
          /* ignore */
        }
      };

      req.signal.addEventListener("abort", close);
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
