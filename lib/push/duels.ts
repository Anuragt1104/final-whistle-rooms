import { fcmConfigured, sendFcm } from "./goals";
import type { DuelRepository } from "@/lib/duel/repository";

export async function notifyDuelTurn(
  repository: DuelRepository,
  duelId: string,
  fanId: string,
): Promise<void> {
  if (!fcmConfigured()) return;
  const tokens = await repository.devicesForFan(fanId);
  await Promise.allSettled(
    tokens.slice(0, 20).map((token) =>
      sendFcm({
        token,
        // Metadata only: no card, axis, score, or hidden state.
        data: {
          type: "duel_turn",
          duelId,
          deepLink: `finalwhistle://duels/${duelId}`,
        },
        android: { priority: "HIGH" },
      }),
    ),
  );
}
