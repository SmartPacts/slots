# Slots — how it works, and everything that can go wrong

Every number in this document that states a rule of the contract is checked against it by
`.github/scripts/check-player-terms.sh`; if the contract changes and this page does not, the gate
fails. Each machine's return, edge, hit rate and top prize is recomputed by that check from the
machine's strip and paytable as the contract holds them. The block-gap figure is a measurement,
said so where it appears. The behaviours described here are pinned by named tests on the
contract's own page, which marks the few not yet pinned.

---

## The game

**Six slot machines run on one contract and one pot.** Every machine has three reels and one
public strip of **64 stops**, the same strip on all three reels. You pick a machine, a stake per
spin and how many spins you want, from **1 to 77**, and you sign it once. We call that a board.
**A board plays one machine.** A board that names a second machine is refused ("a board plays one
machine"), and nothing moves. Every spin of every board in a round is decided by one random
number from drand, a group of independent organisations **outside Kadena entirely**, and the
contract checks that number's proof itself.

**Where the reels stop.** A spin's three stops come from one hash of the round's drand number,
your account and the spin's number. Each stop is one of the 64 positions with exactly equal
chance, so each machine's return below is exact, not an estimate. Everyone in a round spins
from the same drand number, but your reels are your own: another account's reels stop
somewhere else. Anyone can recompute every reel of every board once the number is public.

**What you see is what the odds are.** Each strip is shown as it is: a symbol appears one
stop above or below the line exactly as often as it appears on it. Nothing is placed near the
line to look like a near miss.

**Every win pays more than the spin's stake.** No combination on any machine returns less than
you staked on that spin and calls it a win. A board of several spins can still return less
than the whole board cost, even when some of its spins won. That is a loss, and we call it one.

## A round

1. **You place a board**: one machine, a stake per spin
   (**0.01 KDA** minimum per spin today) and 1 to 77 spins. This is the only thing you sign. One
   board per account per round: a second board from the same account in the same round is
   refused, even on another machine, so you play one machine per round from one account.
   If the board breaks a rule, it is refused and nothing moves. The
   minimum, the closing time, the drand number and the share of the pot the round may risk
   are fixed when the round opens, and nothing changes them while it is open. The table limit
   is measured against the smaller of the pot at open and the pot now, so it can shrink while
   the pot stands below where it was at the open, and it never grows past the limit the round
   opened with. A board that arrives when no round is taking boards opens the next round and is its first
   board; a round only ever opens because someone placed a board.
2. **Betting closes 30 seconds** after the round opens. The window is a dial: never under 30
   seconds, never over an hour, and a change binds the next round.
3. **The reels come from drand**, which publishes a new random number every 3 seconds. The
   round is locked to the last drand number published at or before **120 seconds after betting
   closes**, so it is published 117 to 120 seconds after the close, never while the round is
   taking boards (limit 3 says what that rests on). The wait is a setting the operator controls, and the
   contract holds it to a range: never below **120 seconds**, never above an hour.
4. **Anyone submits it.** The contract checks the cryptographic proof itself, so a fake number
   is rejected. drand numbers never expire, so a round settles correctly whether that happens in
   a minute or a month.
5. **Your board is settled.** Settling plays every spin of your board, records
   the stops and pays what they won together to the account that placed it. A losing board is settled too, and you sign
   nothing for either. From the first bet of a round to its results takes about three minutes.

**Why not a Kadena block?** Because whoever produces that block would see the reels first and
could throw the block away if they did not like them. drand is produced off Kadena, so no miner
touches it.

## The machines

Every machine below is fixed in the contract: its strip, its paytable and its top prize are
constants no setting can move. Pays are gross: what a spin returns, stake included, in times the
spin's stake. "Any three high" means any mix of bell, bar and seven. Each machine's return is an
average over every possible spin: a single board can return anything from nothing to its top prize.

### Machine 0 — classic

- **classic strip**: 38 blanks, 8 cherries, 8 bells, 8 bars, 2 sevens.
- **classic pays**: three sevens 40 · three bars 20 · three bells 10 · three cherries 15 · any three high 5 · two cherries 5 · one cherry 2.
- **classic return: 983/1024 = 95.9961%** of everything staked; **house edge 4.0039%**.
- **classic wins on 35.23% of spins** (92,360 of the 262,144 possible lines).
- **classic top prize: 40 times the spin's stake.** Its smallest win pays **2 times** the spin's stake.

### Machine 1 — easy

Wins often and small.

- **easy strip**: 36 blanks, 12 cherries, 10 bells, 4 bars, 2 sevens.
- **easy pays**: three sevens 18 · three bars 6 · three bells 2 · three cherries 2 · any three high 2 · two cherries 2 · one cherry 2.
- **easy return: 983/1024 = 95.9961%** of everything staked; **house edge 4.0039%**.
- **easy wins on 47.92% of spins** (125,632 of the 262,144 possible lines).
- **easy top prize: 18 times the spin's stake.** Its smallest win pays **2 times** the spin's stake.

### Machine 2 — big

Wins rarely and large. Its table is the smallest of the six: see *Table limits*.

- **big strip**: 44 blanks, 4 cherries, 8 bells, 4 bars, 4 sevens.
- **big pays**: three sevens 250 · three bars 100 · three bells 30 · three cherries 30 · any three high 8 · two cherries 4 · one cherry 4.
- **big return: 983/1024 = 95.9961%** of everything staked; **house edge 4.0039%**.
- **big wins on 19.17% of spins** (50,240 of the 262,144 possible lines).
- **big top prize: 250 times the spin's stake.** Its smallest win pays **4 times** the spin's stake.

### Machine 3 — wild

The classic strip with two blanks replaced by a wild. A wild stands for a cherry, bell, bar or
seven in three of a kind and in any three high, and a win it completes pays **double**. A wild
never counts as a cherry in the one- and two-cherry pays. Three wilds have their own prize.

- **wild strip**: 36 blanks, 8 cherries, 8 bells, 8 bars, 2 sevens, 2 wilds.
- **wild pays**: three sevens 20 · three bars 8 · three bells 6 · three cherries 15 · any three high 5 · two cherries 2 · one cherry 2 · three wilds 40.
- **wild return: 7865/8192 = 96.0083%** of everything staked; **house edge 3.9917%**.
- **wild wins on 36.06% of spins** (94,528 of the 262,144 possible lines).
- **wild top prize: 40 times the spin's stake.** Its smallest win pays **2 times** the spin's stake.

### Machine 4 — free-spins

The classic strip with four blanks replaced by a scatter. A scatter on the line counts as a
blank. A scatter anywhere in **each** reel's three-stop window (the stop on the line and the
ones just above and below) awards **8 free spins** that pay **2 times** their line. A free
spin that shows the same can retrigger **8 more**, up to **24 free spins** per trigger, and
the bonus stops once it reaches **100 times** the spin's stake. Free spins are part of the spin
that triggered them: they are decided by the same drand number and settled with your board.

- **free-spins strip**: 34 blanks, 8 cherries, 8 bells, 8 bars, 2 sevens, 4 scatters.
- **free-spins pays**: three sevens 40 · three bars 20 · three bells 10 · three cherries 10 · any three high 5 · two cherries 3 · one cherry 2.
- **free-spins return: 96.4789%** of everything staked, an exact fraction of two 109-digit numbers; **house edge 3.5211%**.
- **free-spins wins on its line on 35.23% of spins**, and **triggers the bonus on 0.66% of spins** (27 in 4,096). A spin that triggers the bonus shows no line win.
- **free-spins top prize: 100 times the spin's stake.** Its smallest win pays **2 times** the spin's stake.

### Machine 5 — tumble

Each spin shows a window of three stops per reel, read up the strip. Three of a kind (not
blanks) on any of **5 lines** (the three rows and both diagonals) wins. Lines pay at a line bet
of **one fifth** of the spin's stake. The winning cells vanish, the rest drop, the next stops
of the strip fall in from above, and the k-th cascade pays k times its lines, at most **5
cascades** per spin.

- **tumble strip**: 16 blanks, 22 cherries, 14 bells, 8 bars, 4 sevens.
- **tumble pays**, per winning line: three cherries 1.4 · three bells 3.6 · three bars 7 · three sevens 16, times the cascade's number.
- **tumble return: 19651/20480 = 95.9521%** of everything staked; **house edge 4.0479%**.
- **tumble wins on 24.62% of spins** (64,544 of the 262,144 possible windows).
- **tumble top prize: 112.6 times the spin's stake.** Its smallest win pays **1.4 times** the spin's stake.

Every spin is capped at its machine's top prize inside the contract. The cap never binds, because
each top prize above is the true maximum of that machine, found by trying every stop.

## Table limits

The portion of the pot one round may risk is a setting the operator controls, and today it is
**2%** of the house's spare capital. The operator can raise or lower that portion at any time,
can raise or lower the table minimum at any time, can lengthen or shorten the betting window
and the wait before the drand number is locked in within their ranges, and can move the pot's
target, the level below which the fee ramps down, **including after the contract is frozen**,
because all of these are day-to-day settings and not part of what freezing locks. Every such
change is a public transaction on the chain, and none of them can change what a round already
taking bets froze: its portion of the pot, its minimum, its window and its drand number. The one
figure read live is the pot's target: a change to it moves the fee accrued by later boards in
that round, and with it the room the round has left under its limit.

The contract's own bound on the portion is arithmetic and nothing else: it refuses any portion
above **100%** of the pot's spare capital, because a round cannot risk more than the pot has
spare. There is no upper bound on the minimum bet, and the minimum per spin can never be set
below **0.001 KDA**.

**How big a board can be.** Before accepting a board, the pot reserves the worst case: every
spin of the board paying its machine's top prize. So the largest board the round accepts on a
machine is the round's remaining room divided by that machine's top prize plus its fee. The pot
publishes that figure for each machine, exactly: a board of that total is accepted, and one unit
of the last decimal more is refused. **The round limit counts every board in the round together.**
Each figure is the room left for one more board: two boards each at their full published figure
do not both fit in one round. At today's table share, a board in a fresh round is never more than **one
2,000th** of the pot's spare capital on classic and wild, **one 900th** on easy, **one 12,500th**
on big, **one 5,000th** on free-spins and **one 5,630th** on tumble. **The big machine's table is
small**: from a pot of 15,000 KDA with nothing reserved, a round takes about 1.2 KDA on big in
total.

**What the pot is sized to keep.** Beside each machine's "up to" figure, the play page shows a
second one: **1%** of the pot's spare capital divided by that machine's top prize, rounded down
to 12 decimal places. A board of that size is one the pot is sized to keep taking after a year
of busy play. From a pot of 15,000 KDA with nothing reserved, that is **3.75 KDA** on classic and
wild, **8.333333333333 KDA** on easy, **0.6 KDA** on big, **1.5 KDA** on free-spins and
**1.33214920071 KDA** on tumble. This figure is a simulation result, not a contract rule: the
contract never measures a board against it, and the only limit it enforces is the "up to"
figure. The simulation played a year at one round every 12 minutes and at one round every 30
seconds, from a pot of 15,000 KDA and of 30,000 KDA, on every machine, 1,000 years in each
setting. In none of those years did the pot fall below half of where it started, and in none did
it fall so low that a board of that size would no longer fit.

The limit applies to the **whole round**, not per player, and it uses whichever is smaller: the
pot when the round opened, or the pot now. **A round can fill up.** If other players have
already taken the round's room, your board is refused and you wait for the next round, about
30 seconds later. One player can take a whole round's room.

**The pot can never fail to pay a board it took**, for as long as the contract's code stands
(limit 1: it is not frozen today). Before accepting any board the contract reserves that
board's worst case, and each settled board releases exactly what it
reserved. It can refuse a
board; it cannot run short on one it took. What a board wins comes out of the pot, never out of
another player's stake.

## What you should know before you play

**Who may play.** You must be at least 18 years old, or older where the law where you are sets a
higher age for games of chance, and playing a game of chance for KDA must be lawful where you are.
The play page asks you to confirm this by ticking a box, and it asks your wallet to sign nothing
until that box is ticked: the tick is checked when you press the button, again the moment before
your wallet is asked, and again the moment the board leaves, and a board whose tick was removed in
between is discarded unsent. That tick is the only check there is. The contract cannot know your
age or where you are: it accepts a board from any wallet account (the one exception is a
contract's `m:` account, which no wallet can hold), and anyone can call it directly without the
page. Whether you may play is yours to know, not something we can verify for you, and we keep no
list of countries. **If you are under age, or play is unlawful where you are, do not play.** Play
for entertainment, with money you can afford to lose; if play stops being fun, stop.

**You do not need any KDA to be paid.** The house runs a helper that settles every board,
winners and losers, and every refund, usually within minutes of the result. You sign nothing
and you need hold nothing: a settlement always pays the account that placed the board, never
whoever sent the transaction. Anyone can also settle any board by calling the contract
directly, you included; the play page has no button for it. If the helper were ever down, a
settlement is delayed, not lost, with one exception: a round that nobody at all settles for
90 days (limit 2).

**Unclaimed winnings never expire.** They stay owed to you indefinitely. Nothing sweeps them to
the house.

**The fee never comes out of your stake.** It is paid by the pot, out of the house's own edge,
to the SPT treasury: at most the machine's house edge on what you staked, reached
when the pot is at its target, and less while the pot is still filling. Your return is the figure above whatever the fee does.

**Nothing is ever signed for you.** Each board is one signature you make yourself, for one
round, on one machine. The play page sends each board the moment you sign it; it holds nothing
to send later. One board can commit up to 77 spins (limit 6).

---

## 🔴 The honest limits

These are real. They are listed because they are true, not because they are comfortable.

**1. Until the contract is frozen, the operator's key controls the pot, and the rules.** The
same key that can upgrade the contract can move the pot's entire balance anywhere, and can
replace the contract's code: the machines, their strips and paytables, and how a round still
waiting for its drand number is decided. Nothing can reach money you have already been paid,
but while the contract is upgradeable **the bankroll is custody, not escrow, and every rule on
this page holds only as long as the key leaves the code alone.** Freezing the contract ends
this, and nothing else about the game changes when it does. **The contract is not frozen
today, and no date is set for freezing it.**

**2. If drand is ever retired, rounds refund after 90 days.** Nobody can prove on-chain that a
number is gone for good rather than simply not yet sent in, so the contract waits. One cheap,
public call from anyone shows the contract a newer drand number, and a round locked at or below
the newest number seen can then never be refunded: the refund exists only while the contract
has seen no drand number at or after the round's own. **Two consequences:** if truly nobody
acts for 90 days, a player who lost can take their stake back; and because a refund applies to
a whole round, it would also return a **winner** their stake instead of their winnings. **If you
win, make sure your board is settled.** The helper does it; anyone can also do it by calling
the contract directly, at any time.

**3. The reels are secret only while Kadena's clock behaves.** The wait between the close and
the drand number (120 seconds, and never less) is what keeps that number unpublished while
betting is open. The number itself is published 117 to 120 seconds after the close, because
drand publishes every 3 seconds. The wait is sized against measured Kadena blocks: replayed over 120,000 measured
block gaps on chain 2 with a round closing every 30 seconds, no round would have been exposed
(0 in 41.7 days), although eight of those gaps were longer than 120 seconds (the longest 136.2).
That is a measurement of the past, not something the contract can prove, and it assumes that
blocks carry honest times: a miner sets the time on the blocks they mine, so the wait is as
strong as the other miners' blocks arriving inside it. **If a block gap were ever longer than the
wait, or the clock were held back that long**, one round would be exposed: someone could bet after
seeing the number, on an account whose reels they had already checked, up to that round's own
limit. It comes out of the pot, never out of another player's stake.

**4. A round can, in principle, stick.** If a drand number becomes permanently unavailable
*after* the contract has already seen a later one, that round can be neither settled nor
refunded, and everything reserved for it stays locked: the players' stakes and the pot's
reserve. Other rounds are not affected. This has never happened in drand's history, but it is
possible.

**5. One board per account per round, playing one machine, signed once.** Once it is signed you
cannot change its machine, its stake or its number of spins. To play another machine, or more
spins, wait for the next round.

**6. Your whole board is decided at once.** Up to 77 spins, all on one machine, are committed in
the one signature, and all of them are decided the moment the drand number is known. The play page reveals your spins one by one, but they were
settled together: nothing you do while watching changes any of them, and there is no way to stop
a board part way.

**7. The table can be full.** A round's limit is shared by everyone in it, and one board can
take all of it. Your board is then refused until the next round. A board counts against the
limit as a whole: if it does not fit, it is not placed.

**8. The big machine's table is small.** Its top prize is 250 times the spin's stake, and the pot
reserves that for every spin, so a round takes far less on big than on any other machine.

**9. The operator's dials.** The portion of the pot a round may risk (above zero, at most 100%),
the minimum per spin (never below 0.001 KDA, no ceiling), the pot's target, the betting window
(30 seconds to an hour) and the wait before the drand number (120 seconds to an hour) stay the
operator's after the contract is frozen. A change reaches only rounds that have not opened yet,
except the pot's target, which moves the fee at once. The floors are the contract's: the
operator cannot go below them.

**10. Two settlements paying the same account cannot go in one transaction.** A Kadena
limitation. Each goes through on its own.

---

## What we do not do

We do not hold your funds between rounds. Under the contract's rules there is no way to reverse
a bet, cancel a round you are winning, or change the reels after you have played: no correction,
no override and no undo. **A wrong bet stays wrong, and so does a winning one.** (Honest limit 1
is the exception, until the contract is frozen.)

**What the operator can still do, said plainly.** There is no pause button and we are not
building one. A round that has opened runs to its end on the terms it opened with: nothing we
hold can change those terms or its outcome; until the freeze, honest limit 1 above says what the
key could still replace. What we can do is stop **future** rounds, and the rest of an open
round's betting (boards already placed are untouched): by withdrawing the bankroll, or by
raising the minimum bet or lowering the table limit for the rounds that follow. All the dials
stay ours after the contract is frozen. That is deliberate, and it is the cost of keeping them
tunable rather than fixing them in code forever. Any such change is a public transaction on the
chain.
