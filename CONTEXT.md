# Final Whistle Rooms

A verified World Cup fan product: live match Moments become Merkle-backed collectibles; Player and Skill cards power between-match 1v1 games; optional Parties boost drops.

## Language

### People & presence

**Fan**:
A person using the product — watching matches, collecting Cards, and dueling.
_Avoid_: User, player (ambiguous with Player Card), customer

**Party**:
An optional multiplayer watch group for one Fixture that applies a drop multiplier and can host friend Duels.
_Avoid_: Room (legacy product term; keep in code/API only until renamed), lobby, watch party

### Match data

**Fixture**:
A scheduled World Cup match with home and away sides.
_Avoid_: Game, matchup

**Match Event**:
A discrete in-play occurrence from TxLINE-shaped data (goal, card, corner, phase change, material odds move).
_Avoid_: Stat update, pulse (Pulse is the plain-English feed, not the event itself)

**Pulse Card**:
An ephemeral, room-native plain-English feed item derived from Match Events. Not collectible.
_Avoid_: Moment, notification

**Odds Sandwich**:
Implied win probabilities (or related market read) immediately before and after a Match Event.
_Avoid_: Odds strip, market context

### Cards

**Moment**:
A durable, shareable collectible minted from a significant Match Event, carrying rarity, Odds Sandwich, and a Merkle proof.
_Avoid_: Pulse Card, souvenir, NFT (unless referring to optional chain anchor)

**Player Card**:
A playable fighter card depicting a real World Cup footballer (full likeness), with numeric axes used in Duels.
_Avoid_: Fighter (informal only), athlete card, roster card

**Skill Card**:
A one-shot modifier played alongside a Player Card in a Duel.
_Avoid_: Ability, power-up, spell

**Card**:
Any of Moment, Player Card, or Skill Card when speaking generally.
_Avoid_: Collectible (prefer the specific type)

**Lineage**:
The proof link from a Player Card or Skill Card back to the Moment (or mint event) that produced it.
_Avoid_: Provenance chain, parent proof

### Rarity & live incentives

**Market Rarity**:
Rarity stars on a Moment derived from how unlikely the event was in the market before it happened (TxLINE odds / swing size).
_Avoid_: Drop rarity (that is Pack-weighted), scarcity

**Micro-Play**:
A short, points-only prediction during a live Fixture (evolved from Next Swing) that can stamp a Moment and improve Pack odds.
_Avoid_: Bet, wager, stake (cash connotations), Next Swing (legacy name)

**Called It**:
A seal on a Moment earned when the Fan correctly resolved a related Micro-Play.
_Avoid_: Prediction badge, correct call

**Pack**:
A randomized grant of Player Cards and/or Skill Cards, weighted by Moment rarity, Micro-Play success, and Party multiplier.
_Avoid_: Loot box, booster (OK informally)

**Craft**:
Burning or spending Moments (by set/rarity rules) to mint or upgrade a Player Card or Skill Card.
_Avoid_: Exchange, smelt, fuse (OK as UI verbs later)

### Game

**Duel**:
A 1v1 contest between Fans using Player Cards and optional Skill Cards.
_Avoid_: Battle, match (ambiguous with Fixture), game

**Trump Duel**:
The default Duel mode: best of three Rounds. Each Fan brings a Hand of three Player Cards; the Attacker picks an Axis each Round; higher value wins the Round; optional one Skill Card per Round.
_Avoid_: Stat fight, Top Trumps (reference only)

**Hand**:
The three Player Cards a Fan selects to bring into a Trump Duel.
_Avoid_: Deck, lineup, squad, loadout (loadout OK informally for Arena)

**Round**:
One Axis comparison inside a Trump Duel (or one claim resolution step inside Moment Arena when scored round-wise).
_Avoid_: Turn, trick

**Attacker**:
The Fan who chooses the Axis for the current Round in a Trump Duel. Round winner becomes the next Attacker.
_Avoid_: Leader, picker

**Moment Arena**:
A featured Duel mode seeded by a recent Merkle-backed Moment; loadouts score by how well they claim that Moment.
_Avoid_: Ranked arena, claim mode

**Axis**:
One of five numeric stats on a Player Card compared in a Trump Duel: Finishing, Chaos, Clutch, Market Shock, Aura (each 0–99).
_Avoid_: Stat, attribute (OK informally)

**Base Stats**:
The authored 0–99 Axis values on a Player Card from the demo roster before any Lineage imprint.
_Avoid_: Default stats, card template

**Lineage Imprint**:
A lasting Axis boost applied when a Player Card is minted from Moment context (e.g. goal Moment → Finishing; market-swing Moment → Market Shock).
_Avoid_: Stat mutate, live update, XP

### Trust

**Merkle Leaf**:
One hashed entry in a Fixture- or inventory-scoped tree — typically a minted Moment or a Lineage mint event.
_Avoid_: Proof row, event hash

**Proof**:
A verifiable Merkle inclusion (and optional Solana anchor) a Fan can inspect for a Moment or Lineage.
_Avoid_: Validation receipt (TxLINE term for oracle proofs)

### Points

**Points**:
Skill-based, non-cash currency used for Micro-Plays, Duel stakes/rewards framing, and progression — never real-money gambling.
_Avoid_: Coins, chips, credits (unless a future named currency is introduced)
