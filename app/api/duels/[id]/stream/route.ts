import { authenticatedFan } from "@/lib/auth/session";
import { DuelCommandService } from "@/lib/duel/service";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

export async function GET(
  request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  let fanId: string;
  try {
    fanId = authenticatedFan(request);
  } catch {
    return Response.json({ error: "authentication required" }, { status: 401 });
  }
  const { id } = await params;
  const service = new DuelCommandService();
  try {
    await service.get(id, fanId);
  } catch {
    return Response.json({ error: "duel not found" }, { status: 404 });
  }
  let cursor = Number(request.headers.get("last-event-id") ?? 0) || 0;
  const encoder = new TextEncoder();
  let timer: ReturnType<typeof setInterval> | undefined;
  let closed = false;
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      const send = async () => {
        if (closed) return;
        try {
          const events = await service.events(id, fanId, cursor);
          for (const item of events) {
            controller.enqueue(
              encoder.encode(
                `id: ${item.version}\nevent: duel\ndata: ${JSON.stringify(item.event.view)}\n\n`,
              ),
            );
            cursor = item.version;
          }
          if (!events.length) controller.enqueue(encoder.encode(`: keepalive ${Date.now()}\n\n`));
        } catch {
          closed = true;
          if (timer) clearInterval(timer);
          controller.close();
        }
      };
      void send();
      timer = setInterval(() => void send(), 1_000);
      request.signal.addEventListener("abort", () => {
        closed = true;
        if (timer) clearInterval(timer);
        try {
          controller.close();
        } catch {
          // Already closed by the runtime.
        }
      });
    },
    cancel() {
      closed = true;
      if (timer) clearInterval(timer);
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
