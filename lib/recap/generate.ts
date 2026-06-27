/**
 * AI room recap — a short narrative of what happened in the ROOM, not just the
 * match ("Ana leads on 420 after calling the red-card swing"). Storytelling is
 * what makes the product feel like a finished experience rather than a feed.
 *
 * Default: a high-quality deterministic local generator (fully offline, demo-
 * safe). If ANTHROPIC_API_KEY is set, Claude writes the recap with the same
 * facts. Either way it returns plain text.
 */
import type { MatchEvent } from "@/lib/txline/types";

export interface RecapContext {
  scope: "half-time" | "full-time";
  homeName: string;
  homeCode: string;
  awayName: string;
  awayCode: string;
  homeGoals: number;
  awayGoals: number;
  leader?: { name: string; points: number; streak: number; bestStreak: number };
  runnerUp?: { name: string; points: number };
  keyEvents: MatchEvent[];
  momentum: number;
}

export async function generateRecap(ctx: RecapContext): Promise<string> {
  if (process.env.ANTHROPIC_API_KEY) {
    try {
      return await claudeRecap(ctx);
    } catch {
      // fall through to local generator
    }
  }
  return localRecap(ctx);
}

function localRecap(ctx: RecapContext): string {
  const { homeCode, awayCode, homeGoals, awayGoals, scope } = ctx;
  const lead =
    homeGoals === awayGoals
      ? `level at ${homeGoals}–${awayGoals}`
      : homeGoals > awayGoals
        ? `${ctx.homeName} ahead ${homeGoals}–${awayGoals}`
        : `${ctx.awayName} in front ${awayGoals}–${homeGoals}`;

  const goals = ctx.keyEvents.filter((e) => e.kind === "goal");
  const reds = ctx.keyEvents.filter((e) => e.kind === "red");
  const when = scope === "half-time" ? "First half" : "Full-time";

  const beats: string[] = [];
  beats.push(`${when}: ${homeCode} ${homeGoals}–${awayGoals} ${awayCode}, ${lead}.`);

  if (goals.length === 0) {
    beats.push("Tight and cagey — no goals to separate them yet.");
  } else if (goals.length >= 3) {
    beats.push(`A wild ${goals.length}-goal ride that kept the room on its feet.`);
  } else {
    const last = goals[goals.length - 1];
    beats.push(`${last.label} at ${last.minute}' was the moment that shifted the room.`);
  }

  if (reds.length > 0) {
    beats.push(`A red card swung the momentum and reshuffled the leaderboard.`);
  }

  if (ctx.leader) {
    const streakBit =
      ctx.leader.bestStreak >= 3 ? ` riding a ${ctx.leader.bestStreak}-call streak` : "";
    beats.push(`${ctx.leader.name} tops the room on ${ctx.leader.points}${streakBit}.`);
    if (ctx.runnerUp && ctx.runnerUp.points > 0) {
      const gap = ctx.leader.points - ctx.runnerUp.points;
      beats.push(
        gap <= 50
          ? `${ctx.runnerUp.name} is right on their heels — ${gap} points back.`
          : `${ctx.runnerUp.name} leads the chase from ${gap} back.`,
      );
    }
  } else {
    beats.push("The leaderboard is wide open — your next call could top it.");
  }

  return beats.join(" ");
}

async function claudeRecap(ctx: RecapContext): Promise<string> {
  const model = process.env.ANTHROPIC_RECAP_MODEL ?? "claude-haiku-4-5-20251001";
  const facts = {
    moment: ctx.scope,
    score: `${ctx.homeCode} ${ctx.homeGoals}-${ctx.awayGoals} ${ctx.awayCode}`,
    keyEvents: ctx.keyEvents.map((e) => `${e.minute}' ${e.label}`),
    leader: ctx.leader,
    runnerUp: ctx.runnerUp,
  };
  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": process.env.ANTHROPIC_API_KEY as string,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model,
      max_tokens: 160,
      messages: [
        {
          role: "user",
          content:
            "You are the in-room pundit for a private World Cup watch party. In 2-3 punchy sentences, recap the match AND the room's prediction game. Mention the leader by name and their points. Energetic, friendly, no betting/odds-as-money language. Facts:\n" +
            JSON.stringify(facts),
        },
      ],
    }),
  });
  if (!res.ok) throw new Error(`Claude recap failed: ${res.status}`);
  const data = (await res.json()) as { content: Array<{ type: string; text?: string }> };
  const text = data.content?.find((c) => c.type === "text")?.text;
  if (!text) throw new Error("Claude recap empty");
  return text.trim();
}
