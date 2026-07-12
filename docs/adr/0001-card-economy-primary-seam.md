# Card Economy is the primary seam

Live match ticks, Party SSE, Duel HTTP, and clients must not own mint/craft/duel rules. A single Card Economy module exposes `mintFromEvent`, pack/craft, `resolveDuel`, and inventory reads. UI and Room/Party runtime stay thin callers. This keeps one testable boundary for the MVP game system and avoids Pulse or TxLINE adapters becoming god objects.

**Considered:** mint inside PulseInterpreter; separate Duel engine as co-equal seam. Rejected for MVP — one seam, extract Duel later only if rules bloat.
