;; slots.pact — six slot machines on public reel strips, one pot (Pact 5 / KDA-CE).
;;
;; ONE SIGNED TRANSACTION PER PLAYER. You place a board -- one machine, a stake per
;; spin and one to MAX-SPINS spins -- and that is all you sign. Every
;; spin of every board in a round is settled from ONE verified drand beacon; anyone
;; may settle a board, and whatever it won is always paid to the account that
;; placed it.
;;
;; WHERE THE REELS STOP. Each machine has one public strip of 64 stops for all three
;; reels. A spin's three stops are three 6-bit slices of the BLAKE2b hash of the
;; spin's key -- the hash of the round's seed and the account, then the spin's
;; index -- so every stop is uniform over
;; the 64 positions, exactly, with no modulo bias, and a front end can recompute
;; every reel from the beacon alone. The seed comes from a drand BN254 beacon
;; verified on chain by `n_48867b242317a0216a67f8c7ca26696b5878e0e3.drand`, never
;; from a Kadena block hash: the miner of a deciding block would see the outcome
;; before publishing and could discard the block, a free re-roll. The round's
;; beacon is pinned when the round opens: the last one drand publishes at or before
;; the close plus the wait, so with a beacon every 3 s it is published up to 3 s
;; before the wait is over, never earlier. Pact stamps a bet with the PARENT block's time, so a bet
;; can still be mined one block gap after the close; the wait is sized against the
;; gaps chain 2 has produced: replayed over 120,000 measured gaps with a round
;; closing every 30 s, no round would have been exposed at 120 s, although eight
;; of those gaps were longer than 120 s (the longest 136.2 s). It is a measured
;; rate, not an absolute, and it assumes blocks carry honest times: a gap longer
;; than the wait, or a clock held back for that long, would expose that one round,
;; up to its table limit. Afterwards
;; The seed is as honest as drand's signers: a threshold of them acting together
;; could know a beacon before it is published, at a cost to the pot of at most
;; one round's table limit. ANYONE
;; may submit the beacon; a forged one cannot verify, and drand values never
;; expire, so an open round's beacon can be submitted at any time; a round is
;; refunded only after ninety days with no beacon at or after its own seen, and a
;; refunded round takes no beacon afterwards.
;;
;; WHAT THE MACHINES PAY is fixed in MACHINES below: three line machines of equal
;; return and different volatility (classic 40x, easy 18x, big 250x), a wild
;; machine, a free-spins machine and a tumbling-reels machine. Each machine's exact
;; return is either computed BY THIS MODULE at load from its strip and paytable or
;; pinned as an exact fraction that the rules suite reproduces by enumerating every
;; stop combination. Every win returns more than the stake, so nothing that
;; returns less than a stake is ever called a win. Each strip shows its true
;; neighbours: a stop is one position, so a symbol appears just above or below the
;; line exactly as often as on it.
;;
;; NO HOUSE INPUT. No house secret, no per-round house transaction.
;;
;; SOLVENCY IS STRUCTURAL. Spins are independent, so a round's worst case is every
;; spin paying its machine's top prize: each board reserves its machine's maximum
;; times what was staked on it
;; the moment it is placed, and the pot's state refuses a well-formed board for one
;; reason only: it would take the round over its table limit. A settled board releases exactly what it reserved, win or lose, so the
;; pot's reserve returns to zero once a round is fully settled. A LOSER never
;; needs to sign anything; the house's helper settles every board.
;;
;; THE FEE NEVER TOUCHES THE PLAYER. It is paid out of the POT and decides only how
;; much of the house's own edge is forwarded to the SPT treasury: each machine's
;; house edge on what was staked on it, scaled by min(1, available / target-float), so the pot fills
;; to its target and then forwards the whole edge. A fee above the edge would give
;; the pot negative drift, which is why the edge is the ceiling.
;;
;; THE DIALS. The share of the spare pot one round may risk, the table minimum, the
;; betting window and the wait before the beacon are OPERATOR INPUTS for the life
;; of the module: `set-params` is gated on ADMIN, not GOVERNANCE, so they still
;; move after a freeze. A live round keeps the share, the minimum, its window and
;; its beacon; the fee's ramp reads the pot's health against the target NOW, by
;; design. Bounds the contract keeps: the share is arithmetic (0, 1]; the minimum
;; has a floor at the cost of paying one winner; the wait has a floor at its launch
;; value, because a wait shorter than a block gap lets anyone bet on a published
;; beacon. The machines, their strips and paytables and the spins a board may play are constants, not
;; dials; until the module is frozen the upgrade key can still replace them.
;;
;; A DRAND STALL REFUNDS; IT DOES NOT FORFEIT. After ninety days of total silence
;; a round may be voided and every stake claimed back, but only while the module
;; has verified no beacon at or after the round's own: `last-beacon` is the record,
;; and one `prove-liveness` call keeps every pending round un-voidable.
;;
;; FRESH DEPLOY ONLY. Adding a schema field does not fail at upgrade; it breaks at
;; the first read of the new field. Verify the target chain carries no rows.

(namespace "n_48867b242317a0216a67f8c7ca26696b5878e0e3")

; Load-time admin gate: deploying or upgrading this file requires the spt-gov
; keyset, which already exists on every mainnet chain. Rotating it rotates this
; module's admin with it.
(enforce-guard (keyset-ref-guard "n_48867b242317a0216a67f8c7ca26696b5878e0e3.spt-gov"))

(module slots GOVERNANCE

  @doc "Six slot machines sharing one pot: one signed transaction per player, \
  \every spin settled from a verified drand beacon, winners paid by anyone. The \
  \fee is the pot's and never touches a player's return."

  (use coin)
  ; Sealed, tableless, pure -- and PINNED BY CODE HASH. This module refuses to
  ; load against any other bytes under that name, so the beacon verifier cannot
  ; be swapped for one that hands out chosen reels.
  (use n_48867b242317a0216a67f8c7ca26696b5878e0e3.drand "Y07t-duJmkXkcGth0TfBRg3ThbNR-uh9PdNUd1MKHBQ"
    [ verified-seed round-at time-of-round ])

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; MACHINES ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ; Symbol codes. The three "high" symbols are bell, bar and seven. Code 5 is the
  ; machine's special symbol: the wild on `wild`, the scatter on `free-spins`; the
  ; other machines never carry it.
  (defconst BLANK:integer 0)
  (defconst CHERRY:integer 1)
  (defconst BELL:integer 2)
  (defconst BAR:integer 3)
  (defconst SEVEN:integer 4)
  (defconst SPECIAL:integer 5)
  (defconst SYMBOL-NAMES:[string] ["blank" "cherry" "bell" "bar" "seven" "special"])
  (defconst SYMBOL-CODES:[integer] [0 1 2 3 4 5])

  ; 64 is a power of two, so a uniform 256-bit hash sliced in 6-bit fields gives
  ; a uniform stop with no modulo bias: every return below is an exact fraction.
  (defconst REEL-SIZE:integer 64)
  (defconst REELS:integer 3)
  (defconst COMBINATIONS:integer (* REEL-SIZE (* REEL-SIZE REEL-SIZE)))

  ; THE MACHINES. A board names the machine it plays by its id; every payout term below is a
  ; constant, so nothing a player signed for can move short of an upgrade of this
  ; module, possible until it is frozen: a board is scored by the code live when
  ; it is settled. Each machine has ONE strip
  ; for all three reels (true neighbours: a symbol shows just above or below the
  ; line exactly as often as on it). `pays` by kind:
  ;   line   [three sevens, three bars, three bells, three cherries, any three
  ;          high, two cherries, one cherry, -] -- gross multiples of the stake
  ;   wild   the same seven, then three wilds; a wild stands for cherry, bell, bar
  ;          or seven in three-of-a-kind and any-three-high (not in the cherry
  ;          pays) and doubles the win it completes
  ;   free   a line machine whose scatters (code 5) count as blanks on the line; a
  ;          scatter in each reel's three-stop window awards FREE-SPINS free spins
  ;          at FREE-MULT, each able to retrigger, at most FREE-MAX free spins in one
  ;          bonus, the bonus capped at FREE-CAP
  ;   tumble [cherry, bell, bar, seven] line pays over a 3x3 window and five lines,
  ;          in line units at a fifth of the spin's stake (div 5); winning cells
  ;          vanish and the next strip positions fall in, cascade k paying x k, at
  ;          most TUMBLE-MAX cascades
  ; `max-units` / `div` is the most one spin can return, and every spin is capped
  ; there: the cap never binds (each is the enumerated maximum), and it makes
  ; "a board is never owed more than it reserved" a property of this code.
  ; `pinned-return` is the exact return [numerator denominator] of the machines
  ; whose return depends on the whole window (free, tumble): enumerated off chain
  ; over all 262,144 stop triples (free spins by an exact recursion on top) and
  ; pinned by the rules suite; the line and wild machines compute theirs below.
  (defconst MACHINES:[object]
    [
    { "id": 0, "name": "classic", "kind": "line"
    , "reel": [ 4 3 0 2 0 1 0 0   0 3 0 2 0 1 0 0   0 3 0 2 0 1 0 0   0 3 0 2 0 1 0 0
        4 3 0 2 0 1 0 0   0 3 0 2 0 1 0 0   0 3 0 2 0 1 0 0   0 3 0 2 0 1 0 0 ]
    , "pays": [40 20 10 15 5 5 2 0], "max-units": 40, "div": 1
    , "pinned-return": [] }
    { "id": 1, "name": "easy", "kind": "line"
    , "reel": [ 4 3 2 1 0 0 0 2   1 0 0 0 1 2 0 0   3 0 1 0 2 0 0 1   0 0 2 0 1 0 0 0
        4 3 2 1 0 0 0 2   1 0 0 0 1 2 0 0   3 0 1 0 2 0 0 1   0 0 2 0 1 0 0 0 ]
    , "pays": [18 6 2 2 2 2 2 0], "max-units": 18, "div": 1
    , "pinned-return": [] }
    { "id": 2, "name": "big", "kind": "line"
    , "reel": [ 4 3 1 2 0 0 0 0   0 2 0 0 0 0 0 0   4 3 1 2 0 0 0 0   0 2 0 0 0 0 0 0
        4 3 1 2 0 0 0 0   0 2 0 0 0 0 0 0   4 3 1 2 0 0 0 0   0 2 0 0 0 0 0 0 ]
    , "pays": [250 100 30 30 8 4 4 0], "max-units": 250, "div": 1
    , "pinned-return": [] }
    { "id": 3, "name": "wild", "kind": "wild"
    , "reel": [ 4 3 0 2 0 1 0 0   0 3 0 2 0 1 0 0   0 3 5 2 0 1 0 0   0 3 0 2 0 1 0 0
        4 3 0 2 0 1 0 0   0 3 0 2 0 1 0 0   0 3 5 2 0 1 0 0   0 3 0 2 0 1 0 0 ]
    , "pays": [20 8 6 15 5 2 2 40], "max-units": 40, "div": 1
    , "pinned-return": [] }
    { "id": 4, "name": "free-spins", "kind": "free"
    , "reel": [ 4 3 0 2 0 1 0 5   0 3 0 2 0 1 0 0   0 3 0 2 0 1 0 5   0 3 0 2 0 1 0 0
        4 3 0 2 0 1 0 5   0 3 0 2 0 1 0 0   0 3 0 2 0 1 0 5   0 3 0 2 0 1 0 0 ]
    , "pays": [40 20 10 10 5 3 2 0], "max-units": 100, "div": 1
    , "pinned-return": [9063389690458042355601938653540158107548580822591401155618918013981973816811062613547804594484841949198261321 9394170331095332911557922387157348109502730195633279482829163886128836100458433773854795993539074812127739904] }
    { "id": 5, "name": "tumble", "kind": "tumble"
    , "reel": [ 4 3 2 1 1 2 0 1   3 0 2 1 1 0 2 1   4 3 0 2 1 0 1 2   3 1 0 1 2 0 1 0
        4 3 2 1 1 2 0 1   3 0 2 1 1 0 2 1   4 3 0 2 1 0 1 2   3 1 0 1 2 0 1 0 ]
    , "pays": [7 18 35 80 0 0 0 0], "max-units": 600, "div": 5
    , "pinned-return": [19651 20480] }
    ])
  (defconst MACHINE-COUNT:integer 6)

  (defconst FREE-SPINS:integer 8)
  (defconst FREE-MULT:integer 2)
  (defconst FREE-MAX:integer 24)
  (defconst FREE-CAP:integer 100)
  (defconst TUMBLE-MAX:integer 5)
  ; rows per reel of the five tumble lines: three rows, then both diagonals
  (defconst TUMBLE-LINES:[[integer]] [[0 0 0] [1 1 1] [2 2 2] [0 1 2] [2 1 0]])

  (defun machine-at:object (id:integer) (at id MACHINES))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; PAYTABLES ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (defun is-high:bool (s:integer) (and (>= s BELL) (<= s SEVEN)))
  (defun count-sym:integer (x:integer syms:[integer]) (length (filter (= x) syms)))
  (defun imax:integer (a:integer b:integer) (if (> b a) b a))
  (defun base-pay:integer (p:[integer] s:integer)
    (cond ((= s SEVEN) (at 0 p)) ((= s BAR) (at 1 p)) ((= s BELL) (at 2 p))
          ((= s CHERRY) (at 3 p)) 0))

  (defun line-pay:integer (p:[integer] a:integer b:integer c:integer)
    @doc "What three symbols on the line pay on a line machine, in multiples of the stake."
    (if (and (= a b) (= b c))
        (base-pay p a)
        (if (and (is-high a) (and (is-high b) (is-high c)))
            (at 4 p)
            (let ((n (count-sym CHERRY [a b c])))
              (cond ((= n 2) (at 5 p)) ((= n 1) (at 6 p)) 0)))))

  (defun wild-pay:integer (p:[integer] a:integer b:integer c:integer)
    @doc "What three symbols on the line pay on the wild machine: the best of the substituted three-of-a-kind, any-three-high and the one- and two-cherry pays."
    (let* ((sy [a b c])
           (nw (count-sym SPECIAL sy))
           (rest (filter (!= SPECIAL) sy))
           (m (if (> nw 0) 2 1)))
      (if (= nw 3)
          (at 7 p)
          (let* ((r0 (at 0 rest))
                 (kind (if (and (!= r0 BLANK) (= (count-sym r0 rest) (length rest))) (* m (base-pay p r0)) 0))
                 (high (if (= (length (filter (is-high) rest)) (length rest)) (* m (at 4 p)) 0))
                 (n (count-sym CHERRY sy))
                 (cher (cond ((= n 2) (at 5 p)) ((= n 1) (at 6 p)) 0)))
            (imax kind (imax high cher))))))

  ; The machines' own arithmetic, at load, for the machines whose return depends
  ; only on the three symbols on the line: over every ordered triple of symbol
  ; codes, weighted by how many stops carry each, the units returned per
  ; COMBINATIONS units staked. The rules suite pins each against an enumeration of
  ; all 262,144 lines.
  (defun all-triples:[[integer]] ()
    (fold (+) []
      (map (lambda (a:integer)
             (fold (+) []
               (map (lambda (b:integer)
                      (map (lambda (c:integer) [a b c]) SYMBOL-CODES))
                    SYMBOL-CODES)))
           SYMBOL-CODES)))
  (defconst TRIPLES:[[integer]] (all-triples))
  (defun symbol-counts:[integer] (r:[integer]) (map (lambda (x:integer) (count-sym x r)) SYMBOL-CODES))
  (defun triple-units:integer (m:object t:[integer])
    (if (= "wild" (at 'kind m))
        (wild-pay (at 'pays m) (at 0 t) (at 1 t) (at 2 t))
        (line-pay (at 'pays m) (at 0 t) (at 1 t) (at 2 t))))
  (defun computed-return:integer (m:object)
    (let ((c (symbol-counts (at 'reel m))))
      (fold (+) 0
        (map (lambda (t:[integer])
               (* (* (at (at 0 t) c) (* (at (at 1 t) c) (at (at 2 t) c))) (triple-units m t)))
             TRIPLES))))
  (defun machine-return:[integer] (m:object)
    @doc "The machine's exact return per unit staked, as [numerator denominator]."
    (if (contains (at 'kind m) ["line" "wild"])
        [(computed-return m) COMBINATIONS]
        (at 'pinned-return m)))
  (defconst RETURNS:[[integer]] (map (machine-return) MACHINES))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; ECONOMICS ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ; Each machine's house edge, floored at 30 places: never above the exact edge,
  ; and exact for every machine whose denominator divides 10^30. It is the ceiling
  ; of that machine's fee.
  (defconst EDGE-PLACES:integer 30)
  (defun edge-of:decimal (r:[integer])
    (let ((num (at 0 r)) (den (at 1 r)) (sc (^ 10 EDGE-PLACES)))
      (/ (dec (/ (* (- den num) sc) den)) (dec sc))))
  (defconst EDGES:[decimal] (map (edge-of) RETURNS))
  (defconst MAX-MULTS:[decimal]
    (map (lambda (m:object) (/ (dec (at 'max-units m)) (dec (at 'div m)))) MACHINES))

  ; The spins one board may play. A board plays ONE machine and every spin is settled
  ; in the board's one claim, so this bounds the gas of a claim: the heaviest board,
  ; free-spins with every spin playing all FREE-MAX free spins, settles in about
  ; 108,700 gas at 77 spins against a 150,000 transaction limit, and an unsettleable
  ; board would lock its reserve forever. It is a constant, not a dial, because a
  ; payout's shape must never move.
  (defconst MAX-SPINS:integer 77)


  ; The share of the spare pot one round may put at risk. Bounded arithmetically
  ; only: a round cannot risk more than the pot has spare. With every spin
  ; reserved at MAX-MULT the share is also the round's whole stake capacity.
  (defconst LAUNCH-RESERVE-FRACTION:decimal 0.02)
  (defconst MAX-RESERVE-FRACTION:decimal 1.0)

  ; The table minimum PER SPIN and its floor. A free-spins board of 77 spins settles
  ; in about 7,200 gas, and at most about 108,700 when every spin plays all its free
  ; spins; at the floor such a board stakes 0.077, of which the pot keeps about
  ; 0.0027 on average: about two and a half times what that bound costs to settle at
  ; a gas price of 1e-8.
  (defconst LAUNCH-MIN-BET:decimal 0.01)
  (defconst MIN-BET-FLOOR:decimal 0.001)

  ; The betting window groups boards under one beacon: about one block, so a player
  ; may place a new board every ~30 s. It is not neutral for safety: every close is
  ; one more chance for a block gap longer than the wait below, so a shorter window
  ; needs a wait that no measured gap exceeds.
  (defconst LAUNCH-BET-WINDOW:decimal 30.0)
  (defconst MIN-BET-WINDOW:decimal 30.0)
  (defconst MAX-BET-WINDOW:decimal 3600.0)

  ; The wait between the close and the beacon. Pact's block-time is the PARENT
  ; block's, so a bet accepted at the close can still be mined a whole block gap
  ; later; a beacon published inside that gap could be bet on by anyone, and here a
  ; late bettor could also pick an account whose reels show three sevens. Replayed
  ; over 120,000 measured chain-2 gaps with a close every 30 s, exposed rounds per
  ; day are about 37 at 60 s, 1.4 at 90 s and 0 at 120 s, so the floor IS the launch
  ; value: the operator may lengthen the wait, never set it below 120 s. The beacon
  ; pinned is the last one at or before the close plus the wait, so it is published
  ; between 117 s and 120 s after the close at the floor; the replay above used
  ; that same rounding.
  (defconst LAUNCH-DRAND-MARGIN:decimal 120.0)
  (defconst MIN-DRAND-MARGIN:decimal 120.0)
  (defconst MAX-DRAND-MARGIN:decimal 3600.0)

  ; How long everyone must stay silent before a refund opens: ninety days.
  (defconst VOID-AFTER:decimal 7776000.0)

  (defconst PREC:integer 12)
  (defconst GAME-KEY:string "slots")

  ; The pot's guard is a MODULE guard: it passes only while this module is on the
  ; call stack and otherwise falls through to module admin, which is GOVERNANCE,
  ; which is `enforce false` once frozen. That holds on every engine version.
  ; Consequences: until the freeze module admin can spend the pot; the module can
  ; never be renamed; the account is fixed at first funding; and the engine marks
  ; `create-module-guard` deprecated (a load-time warning), kept here because it
  ; is the one permissionless custody that survives a freeze.
  (defun pot-guard:guard () (create-module-guard "slots-pot"))
  (defconst HOUSE_ACCOUNT:string (create-principal (pot-guard)))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; CAPABILITIES ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ; UPGRADE AUTHORITY ONLY. Freezing this module replaces this body with
  ; (enforce false) and changes nothing else, which is only true while no
  ; operational function depends on it: they all use ADMIN.
  (defcap GOVERNANCE ()
    (enforce-guard (keyset-ref-guard "n_48867b242317a0216a67f8c7ca26696b5878e0e3.spt-gov")))

  ; Operational authority: initialize, set-params, withdraw-house. The same keyset
  ; as GOVERNANCE, deliberately a different capability, so a freeze strands nothing.
  (defcap ADMIN ()
    (enforce-guard (keyset-ref-guard "n_48867b242317a0216a67f8c7ca26696b5878e0e3.spt-gov")))

  (defcap BET-PLACED:bool     (account:string seq:integer machines:[integer] total:decimal reserve:decimal) @event true)
  (defcap ROUND-OPENED:bool   (seq:integer close-time:time drand-round:integer) @event true)
  (defcap ROUND-RESULT:bool   (seq:integer drand-round:integer seed:integer) @event true)
  (defcap SPINS-SETTLED:bool  (account:string seq:integer machines:[integer] stops:[integer] payout:decimal) @event true)
  (defcap CLAIMED:bool        (account:string seq:integer amount:decimal) @event true)
  (defcap ROUND-VOID:bool     (seq:integer stake:decimal) @event true)
  (defcap LIVENESS-PROVEN:bool (drand-round:integer) @event true)
  (defcap FEE-PAID:bool       (seq:integer amount:decimal to:string) @event true)
  (defcap HOUSE-FUNDED:bool   (funder:string amount:decimal) @event true)
  (defcap HOUSE-WITHDRAWN:bool (to:string amount:decimal) @event true)
  (defcap PARAMS-SET:bool     (reserve-fraction:decimal min-bet:decimal target-float:decimal
                               bet-window:decimal drand-margin:decimal) @event true)
  (defcap INITIALIZED:bool    (revenue:string) @event true)

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; SCHEMAS ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (defschema entry
    @doc "What a board plays: which machine, the stake of each spin and how many spins, 1 to MAX-SPINS."
    machine:integer
    stake:decimal
    spins:integer)

  (defschema wager
    @doc "A board: exactly one entry, because a board plays one machine. Its total is that entry's stake times its spins."
    entries:[object{entry}])

  (defschema game
    last-beacon:integer      ; highest drand round this module has ever VERIFIED
    round-seq:integer        ; last round opened
    current:integer          ; the round currently taking bets, 0 = none
    reserved:decimal         ; total locked across every unsettled board and fee
    revenue:string           ; SPT treasury account, set once at initialize
    reserve-fraction:decimal
    target-float:decimal
    bet-window:decimal
    min-bet:decimal
    drand-margin:decimal)

  (defschema pull
    avail-at-open:decimal
    frac-at-open:decimal
    min-bet-at-open:decimal
    close-time:time
    drand-round:integer
    exposure:decimal         ; every board's reserve summed: each machine's maximum times its stake, the worst case
    stake:decimal            ; every stake in the round
    fee-owed:decimal
    reserve:decimal          ; max(exposure, stake) + fee-owed
    boards:integer           ; boards placed
    settled:integer          ; boards settled or refunded
    state:string             ; "open" | "resolved" | "void"
    seed:integer             ; 0 until resolved
    liability:decimal)       ; what unsettled boards still hold of the pot

  (defschema board
    seq:integer
    account:string
    entries:[object{entry}]  ; the machines played, in the order signed
    total:decimal            ; every entry's stake times spins, summed
    reserve:decimal          ; what this board booked against the pot: each entry's machine maximum times its total, summed
    claimed:bool
    stops:[integer]          ; the paid spins' reel stops, three per spin, entries in order, once settled
    payout:decimal)          ; what the board returned, once settled

  (deftable game-table:{game})
  (deftable rounds:{pull})
  (deftable boards:{board})

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; HELPERS ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (defun curr-time:time () (at 'block-time (chain-data)))
  (defun rkey:string (seq:integer) (int-to-str 10 seq))
  (defun bkey:string (seq:integer account:string) (format "{}|{}" [seq account]))

  (defun dmax:decimal (a:decimal b:decimal) (if (> b a) b a))

  ; The fee ramps with the pot's health and never exceeds the stake's own edge.
  (defun fee-scale:decimal (available:decimal target:decimal)
    (enforce (> target 0.0) "target float must be positive")
    (if (>= available target)
        1.0
        (floor (/ (if (> available 0.0) available 0.0) target) PREC)))

  (defun fee-for:decimal (m:integer total:decimal scale:decimal)
    (floor (* scale (* (at m EDGES) total)) PREC))

  ; What one machine's share of a board reserves: every spin paying that machine's maximum.
  (defun board-reserve:decimal (m:integer total:decimal) (* (at m MAX-MULTS) total))

  (defun entry-total:decimal (e:object{entry}) (* (at 'stake e) (dec (at 'spins e))))

  (defun validate-entry:decimal (e:object{entry} min-bet:decimal)
    @doc "Check one entry's machine, stake and spin count and return its total."
    (let ((m (at 'machine e)) (stake (at 'stake e)) (spins (at 'spins e)))
      (enforce (and (>= m 0) (< m MACHINE-COUNT))
        (format "unknown machine {}: machines are 0 to {}" [m (- MACHINE-COUNT 1)]))
      (enforce (>= stake min-bet) "stake per spin below the table minimum")
      (enforce-unit stake)
      (enforce (and (>= spins 1) (<= spins MAX-SPINS))
        (format "spins must be between 1 and {}" [MAX-SPINS]))
      (entry-total e)))

  (defun validate-wager:decimal (w:object{wager} min-bet:decimal)
    @doc "Check that the board holds exactly one entry, check that entry, and return the board's total."
    (let ((es (at 'entries w)))
      (enforce (= 1 (length es)) "a board plays one machine: it holds exactly one entry")
      (validate-entry (at 0 es) min-bet)))

  ; What a board books against the pot, and its fee: each entry at its own machine's
  ; maximum and edge, summed.
  (defun entries-reserve:decimal (es:[object{entry}])
    (fold (+) 0.0 (map (lambda (e:object{entry}) (board-reserve (at 'machine e) (entry-total e))) es)))
  (defun entries-fee:decimal (es:[object{entry}] scale:decimal)
    (fold (+) 0.0 (map (lambda (e:object{entry}) (fee-for (at 'machine e) (entry-total e) scale)) es)))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; THE SPIN ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ; A board's own seed: the round's seed and the account, hashed as a STRING so a
  ; browser can redo it. The seed has no "|", so the pre-image is unambiguous.
  (defun board-seed:string (seed:integer account:string)
    (hash (format "{}|{}" [seed account])))

  ; A spin is named by a string key: "<board seed>|<i>" for paid spin i, and
  ; "<board seed>|<i>|<j>" for free spin j of paid spin i. One hash of the key,
  ; sliced into three 6-bit stops: bits 0-5 reel one, 6-11 reel two, 12-17 reel three.
  (defun spin-key:string (bseed:string i:integer) (format "{}|{}" [bseed i]))
  (defun key-stops:[integer] (key:string)
    (let ((h (str-to-int 64 (hash key))))
      [ (mod h REEL-SIZE)
        (mod (/ h REEL-SIZE) REEL-SIZE)
        (mod (/ h (* REEL-SIZE REEL-SIZE)) REEL-SIZE) ]))
  (defun spin-stops:[integer] (bseed:string i:integer) (key-stops (spin-key bseed i)))

  ; The symbol at stop s of a strip, wrapping: stop -1 is stop 63.
  (defun sym:integer (reel:[integer] s:integer) (at (mod s REEL-SIZE) reel))
  (defun symbols-at:[integer] (reel:[integer] stops:[integer])
    (map (sym reel) stops))

  ; free-spins: a scatter counts as a blank on the line; a trigger is a scatter in
  ; every reel's three-stop window (the stop and its two neighbours).
  (defun unscatter:integer (x:integer) (if (= x SPECIAL) BLANK x))
  (defun window-has-scatter:bool (reel:[integer] s:integer)
    (contains SPECIAL [(sym reel (- s 1)) (sym reel s) (sym reel (+ s 1))]))
  (defun free-look:object (reel:[integer] p:[integer] stops:[integer])
    (let ((y (map (unscatter) (symbols-at reel stops))))
      { "win": (line-pay p (at 0 y) (at 1 y) (at 2 y))
      , "trigger": (= REELS (length (filter (window-has-scatter reel) stops))) }))
  ; The bonus: FREE-SPINS free spins, each paying FREE-MULT times its line, each
  ; trigger adding FREE-SPINS more up to FREE-MAX in all, and the bonus stopping
  ; once it reaches FREE-CAP. At most FREE-MAX free spins ever run.
  (defun free-bonus:integer (reel:[integer] p:[integer] key:string)
    (at 'acc
      (fold (lambda (st:object j:integer)
              (if (and (> (at 'left st) 0) (< (at 'acc st) FREE-CAP))
                  (let* ((look (free-look reel p (key-stops (format "{}|{}" [key j]))))
                         (acc (let ((a (+ (at 'acc st) (* FREE-MULT (at 'win look)))))
                                (if (> a FREE-CAP) FREE-CAP a)))
                         (g (at 'granted st))
                         (g2 (if (at 'trigger look)
                                 (let ((x (+ g FREE-SPINS))) (if (> x FREE-MAX) FREE-MAX x))
                                 g)))
                    { "left": (+ (- (at 'left st) 1) (- g2 g)), "granted": g2, "acc": acc })
                  st))
            { "left": FREE-SPINS, "granted": FREE-SPINS, "acc": 0 }
            (enumerate 1 FREE-MAX))))

  ; tumble: three columns of three read up the strip from each stop; a cascade
  ; pays every line showing three of a kind (not blank), removes those cells,
  ; drops the rest and fills from the next strip positions.
  (defun tumble-step:object (reel:[integer] p:[integer] st:object k:integer)
    (if (not (at 'live st))
        st
        (let* ((cols (at 'cols st))
               (wins (filter (lambda (l:[integer])
                               (let ((a (at (at 0 l) (at 0 cols)))
                                     (b (at (at 1 l) (at 1 cols)))
                                     (c (at (at 2 l) (at 2 cols))))
                                 (and (!= a BLANK) (and (= a b) (= b c)))))
                             TUMBLE-LINES)))
          (if (= 0 (length wins))
              { "live": false, "units": (at 'units st), "cols": cols, "ptr": (at 'ptr st) }
              (let* ((pay (fold (+) 0 (map (lambda (l:[integer]) (at (- (at (at 0 l) (at 0 cols)) 1) p)) wins)))
                     (hit (lambda (i:integer r:integer)
                            (< 0 (length (filter (lambda (l:[integer]) (= r (at i l))) wins)))))
                     (ptr (at 'ptr st))
                     (new (map (lambda (i:integer)
                                 (let* ((keep (map (lambda (r:integer) (at r (at i cols)))
                                                   (filter (lambda (r:integer) (not (hit i r))) [0 1 2])))
                                        (need (- 3 (length keep)))
                                        (fill (if (= need 0) []
                                                  (map (lambda (d:integer) (sym reel (+ (at i ptr) d)))
                                                       (enumerate 0 (- need 1))))))
                                   { "col": (+ keep fill), "ptr": (+ (at i ptr) need) }))
                               [0 1 2])))
                { "live": true
                , "units": (+ (at 'units st) (* k pay))
                , "cols": (map (lambda (x:object) (at 'col x)) new)
                , "ptr": (map (lambda (x:object) (at 'ptr x)) new) })))))
  (defun tumble-units:integer (reel:[integer] p:[integer] stops:[integer])
    (at 'units
      (fold (tumble-step reel p)
            { "live": true, "units": 0
            , "cols": (map (lambda (s:integer) [(sym reel s) (sym reel (+ s 1)) (sym reel (+ s 2))]) stops)
            , "ptr": (map (lambda (s:integer) (+ s 3)) stops) }
            (enumerate 1 TUMBLE-MAX))))

  (defun spin-units:integer (id:integer key:string)
    @doc "What one paid spin returns on machine `id`, in that machine's units (multiples of stake / div), capped at its maximum."
    (let* ((m (machine-at id))
           (reel (at 'reel m))
           (p (at 'pays m))
           (kind (at 'kind m))
           (stops (key-stops key))
           (y (symbols-at reel stops))
           (u (cond ((= kind "line") (line-pay p (at 0 y) (at 1 y) (at 2 y)))
                    ((= kind "wild") (wild-pay p (at 0 y) (at 1 y) (at 2 y)))
                    ((= kind "free")
                       (let ((look (free-look reel p stops)))
                         (+ (at 'win look) (if (at 'trigger look) (free-bonus reel p key) 0))))
                    ((= kind "tumble") (tumble-units reel p stops))
                    (enforce false "unknown machine kind")))
           (cap (at 'max-units m)))
      (if (> u cap) cap u)))

  (defun play-board:object (seed:integer account:string id:integer spins:integer stake:decimal)
    @doc "Every paid spin of a ONE-machine board from the round's seed (spins numbered from 1): the stops in spin order, the units won and the gross payout, floored to coin precision. `claim` settles boards with play-entries."
    (let* ((bs (board-seed seed account))
           (ks (map (spin-key bs) (enumerate 1 spins)))
           (units (fold (+) 0 (map (spin-units id) ks))))
      { "stops": (fold (+) [] (map (key-stops) ks))
      , "units": units
      , "payout": (floor (/ (* stake (dec units)) (dec (at 'div (machine-at id)))) PREC) }))

  ; A board's spins are numbered across its entries in the order signed: the first
  ; entry's spins are 1..n1, the next continue at n1 + 1. `bet` admits one entry, so
  ; every board plays exactly as `play-board` does.
  (defun play-entries:object (seed:integer account:string es:[object{entry}])
    @doc "Every paid spin of every entry of a board from the round's seed: the stops in spin order, the units won per entry and the gross payout, each entry floored to coin precision."
    (let ((bs (board-seed seed account)))
      (fold (lambda (acc:object e:object{entry})
              (let* ((id (at 'machine e))
                     (first (at 'next acc))
                     (ks (map (spin-key bs) (enumerate first (+ first (- (at 'spins e) 1)))))
                     (units (fold (+) 0 (map (spin-units id) ks))))
                { "next": (+ first (at 'spins e))
                , "stops": (+ (at 'stops acc) (fold (+) [] (map (key-stops) ks)))
                , "units": (+ (at 'units acc) [units])
                , "payout": (+ (at 'payout acc)
                               (floor (/ (* (at 'stake e) (dec units)) (dec (at 'div (machine-at id)))) PREC)) }))
            { "next": 1, "stops": [], "units": [], "payout": 0.0 }
            es)))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; ADMIN / SETUP ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (defun house-account:string () HOUSE_ACCOUNT)

  (defun initialize:string (revenue:string target-float:decimal)
    @doc "Admin, once: create the pot and record where revenue goes. `revenue` must be an existing k:, m:, r:, w: or u: principal; never c: or p:, which no outside signer can spend from."
    (with-capability (ADMIN)
      (validate-account revenue)
      ; A principal, so a stranger cannot pre-create a plain name and be paid every
      ; fee forever; never this module's own pot; and never a c: or p: principal,
      ; which no external signer can ever spend from and a frozen module cannot
      ; reach -- there is no setter and initialize runs once.
      (enforce (is-principal revenue)
        "revenue must be a principal account (k:, m:, r:, w: or u:), not a claimable name")
      (enforce (!= revenue HOUSE_ACCOUNT) "revenue must not be this module's own pot")
      (enforce (and (!= "c:" (take 2 revenue)) (!= "p:" (take 2 revenue)))
        "revenue must be an account something can spend from: not a c: or p: principal")
      ; `try`, because get-balance ABORTS on a missing account
      (let ((bal (try -1.0 (get-balance revenue))))
        (enforce (>= bal 0.0) "the revenue account must already exist"))
      (enforce (> target-float 0.0) "target float must be positive")
      (enforce-unit target-float)
      ; the game row goes in FIRST, so a second initialize fails on it plainly
      (insert game-table GAME-KEY
        { "last-beacon": 0, "round-seq": 0, "current": 0, "reserved": 0.0
        , "revenue": revenue
        , "reserve-fraction": LAUNCH-RESERVE-FRACTION
        , "target-float": target-float
        , "bet-window": LAUNCH-BET-WINDOW
        , "min-bet": LAUNCH-MIN-BET
        , "drand-margin": LAUNCH-DRAND-MARGIN })
      ; The pot's principal can be built from transaction data by anyone, so a
      ; stranger may create the coin row first. Tolerating that is safe: coin
      ; refuses the name to any other guard, so a squatted row IS our account.
      (if (< (try -1.0 (get-balance HOUSE_ACCOUNT)) 0.0)
          (create-account HOUSE_ACCOUNT (pot-guard))
          "the pot account already exists")
      (emit-event (INITIALIZED revenue)))
    "slots initialized")

  (defun fund-house:string (funder:string amount:decimal)
    @doc "Add capital to the pot. Permissionless, and it grants no claim on the pot."
    ; a module-specific message: coin's own "transfer amount must be positive"
    ; contains "amount must be positive", so a shared wording would let this check
    ; be deleted with every test still green
    (enforce (> amount 0.0) "fund amount must be positive")
    (transfer funder HOUSE_ACCOUNT amount)
    (emit-event (HOUSE-FUNDED funder amount))
    "house funded")

  (defun withdraw-house:string (amount:decimal)
    @doc "Admin: move UNRESERVED pot funds to the revenue account fixed at initialize. Until the freeze, the admin keyset is also module admin and can reach the pot by other means."
    (enforce (> amount 0.0) "withdrawal amount must be positive")
    (enforce-unit amount)
    (with-capability (ADMIN)
      (let* ((bal (get-balance HOUSE_ACCOUNT))
             (g (read game-table GAME-KEY))
             (reserved (at 'reserved g))
             (to (at 'revenue g))
             (available (- bal reserved)))
        (enforce (<= amount available)
          (format "withdrawal {} exceeds unreserved balance {}" [amount available]))
        (install-capability (coin.TRANSFER HOUSE_ACCOUNT to amount))
        (transfer HOUSE_ACCOUNT to amount)
        (emit-event (HOUSE-WITHDRAWN to amount))))
    "house withdrawal complete")

  (defun set-params:string (reserve-fraction:decimal min-bet:decimal target-float:decimal
                            bet-window:decimal drand-margin:decimal)
    @doc "Admin: the dials for FUTURE rounds. A live round keeps the share, the minimum, its window and its beacon; only the fee ramp reads the target now."
    (enforce (and (> reserve-fraction 0.0) (<= reserve-fraction MAX-RESERVE-FRACTION))
      (format "reserve-fraction must be in (0, {}]" [MAX-RESERVE-FRACTION]))
    (enforce (>= min-bet MIN-BET-FLOOR) (format "min-bet below the floor {}" [MIN-BET-FLOOR]))
    (enforce-unit min-bet)
    (enforce (> target-float 0.0) "target float must be positive")
    (enforce-unit target-float)
    (enforce (and (>= bet-window MIN-BET-WINDOW) (<= bet-window MAX-BET-WINDOW))
      (format "bet-window must be in [{}, {}]" [MIN-BET-WINDOW MAX-BET-WINDOW]))
    (enforce (and (>= drand-margin MIN-DRAND-MARGIN) (<= drand-margin MAX-DRAND-MARGIN))
      (format "drand-margin must be in [{}, {}]" [MIN-DRAND-MARGIN MAX-DRAND-MARGIN]))
    (with-capability (ADMIN)
      (update game-table GAME-KEY
        { "reserve-fraction": reserve-fraction, "min-bet": min-bet
        , "target-float": target-float, "bet-window": bet-window
        , "drand-margin": drand-margin })
      (emit-event (PARAMS-SET reserve-fraction min-bet target-float bet-window drand-margin)))
    "params set")

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; BET ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (defun bet:string (account:string w:object{wager})
    @doc "Place a board. THE ONLY TRANSACTION A PLAYER SIGNS: sign coin.TRANSFER of the board's total, every machine's stake times its spins. Anyone may settle it afterwards; what it wins is paid to `account`."
    (validate-account account)
    ; Coin can pay any existing account, so this is not about payment. What it
    ; refuses is exactly an `m:` principal -- this pot's own account is one -- so
    ; the pot can never be a player at its own machine; a module holding a plain
    ; named account is not caught, and widening this would be a new rule.
    (enforce (!= "m:" (take 2 account))
      "an m: principal cannot bet: the pot's own account is one")
    (with-read game-table GAME-KEY
      { "current" := cur, "reserved" := reserved
      , "target-float" := target, "min-bet" := min-bet }
      (let* ((t (curr-time))
             (es (at 'entries w))
             (bal (get-balance HOUSE_ACCOUNT))
             (available (- bal reserved))
             (scale (fee-scale available target)))
        ; keep the open round if it is still taking bets, else start one. The
        ; minimum is the ROUND's, so a change binds the next round only. Key "0"
        ; never exists, so before the first round the live value applies.
        (with-default-read rounds (rkey cur)
          { "state": "none", "close-time": t, "min-bet-at-open": min-bet }
          { "state" := cst, "close-time" := cclose, "min-bet-at-open" := cmb }
          (let* ((keep (and (= "open" cst) (<= t cclose)))
                 (mb (if keep cmb min-bet))
                 (total (validate-wager w mb))
                 (fee (entries-fee es scale))
                 (own (entries-reserve es)))
            ; The round is opened HERE, inline, with no separate export.
            ; Every term is read from the game row, never taken from the caller, and
            ; nothing outside `bet` can reach this write.
            (let ((seq (if keep cur
                         (with-read game-table GAME-KEY
                           { "reserved" := oreserved, "round-seq" := prev-seq, "drand-margin" := omargin
                           , "bet-window" := owindow, "reserve-fraction" := ofrac, "min-bet" := omin }
                           (let* ((nseq (+ 1 prev-seq))
                                  (oavail (- (get-balance HOUSE_ACCOUNT) oreserved))
                                  (nclose (add-time (curr-time) owindow))
                                  (ndr (round-at (add-time nclose omargin))))
                             (insert rounds (rkey nseq)
                               { "avail-at-open": oavail, "frac-at-open": ofrac, "min-bet-at-open": omin
                               , "close-time": nclose, "drand-round": ndr
                               , "exposure": 0.0, "stake": 0.0, "fee-owed": 0.0, "reserve": 0.0
                               , "boards": 0, "settled": 0
                               , "state": "open", "seed": 0, "liability": 0.0 })
                             (update game-table GAME-KEY { "round-seq": nseq, "current": nseq })
                             (emit-event (ROUND-OPENED nseq nclose ndr))
                             nseq)))))
              ; one board per account per round: a second write would clobber the
              ; first while the round's exposure still counted both
              (with-default-read boards (bkey seq account) { "total": -1.0 } { "total" := prior }
                (enforce (< prior 0.0)
                  "you already have a board in this round: place every spin in one transaction"))
              (with-read rounds (rkey seq)
                { "exposure" := ex, "stake" := rstake, "fee-owed" := rfee, "reserve" := rres
                , "boards" := nb, "avail-at-open" := a0, "frac-at-open" := f0 }
                (let* ((new-ex (+ ex own))
                       (new-stake (+ rstake total))
                       (new-fee (+ rfee fee))
                       ; the reserve must dominate BOTH outcomes: paying every
                       ; spin's top prize, and refunding every stake on a void.
                       ; MAX-MULT is above one, so the stake term cannot bind; it is
                       ; kept as the invariant's own statement, at the cost of one
                       ; comparison.
                       (new-res (+ (dmax new-ex new-stake) new-fee))
                       ; the table limit bounds the ROUND, against the smaller of the
                       ; pot at open and the pot now, at the share frozen at open
                       (cap (* f0 (if (< available a0) available a0))))
                  (enforce (<= (+ new-ex new-fee) cap)
                    (format "this round's exposure {} would exceed the table limit {}"
                            [(+ new-ex new-fee) cap]))
                  ; and what this board adds must be covered by the pot's OWN spare
                  ; capital, not by the stake arriving with it. Unreachable with this
                  ; table: the reserve is exposure + fee, the table limit already
                  ; bounds that by the cap, and the cap never exceeds `available`.
                  ; Kept for the same reason as the stake term above.
                  (enforce (<= (- new-res rres) available)
                    "the pot cannot cover this bet")
                  (update rounds (rkey seq)
                    { "exposure": new-ex, "stake": new-stake
                    , "fee-owed": new-fee, "reserve": new-res, "boards": (+ nb 1) })
                  (update game-table GAME-KEY
                    { "reserved": (+ reserved (- new-res rres)) })
                  (transfer account HOUSE_ACCOUNT total)
                  (insert boards (bkey seq account)
                    { "seq": seq, "account": account, "entries": es
                    , "reserve": own
                    , "total": total, "claimed": false, "stops": [], "payout": 0.0 })
                  (emit-event (BET-PLACED account seq (map (lambda (e:object{entry}) (at 'machine e)) es) total (- new-res rres)))
                  (format "bet placed in round {}" [seq])))))))))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; RESOLVE ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (defun resolve:integer (seq:integer sig-hex:string)
    @doc "Fix this round's seed from the drand beacon and pay the fee. PERMISSIONLESS: a forged beacon cannot verify. Returns the seed every board is settled from."
    (with-read rounds (rkey seq)
      { "state" := st, "drand-round" := dr, "exposure" := ex, "fee-owed" := fee, "reserve" := res }
      (enforce (= "open" st) "this round is already settled (resolved or void)")
      ; No time check is needed: a beacon that is not yet published does not
      ; exist, so verified-seed cannot succeed early.
      (let ((seed (verified-seed (format "slots|{}" [seq]) dr sig-hex)))
        ; the fee is PAID below, so the accrual is zeroed; what the boards may
        ; still take of the pot is the whole exposure until each one settles
        (update rounds (rkey seq)
          { "state": "resolved", "seed": seed, "liability": ex, "fee-owed": 0.0 })
        (with-read game-table GAME-KEY
          { "reserved" := reserved, "revenue" := rev, "last-beacon" := lb }
          ; a verified beacon is PROOF drand was alive at that round
          (update game-table GAME-KEY
            { "reserved": (- reserved (- res ex))
            , "last-beacon": (if (> dr lb) dr lb) })
          (if (> fee 0.0)
              (let ((dest rev))
                (install-capability (coin.TRANSFER HOUSE_ACCOUNT dest fee))
                (transfer HOUSE_ACCOUNT dest fee)
                (emit-event (FEE-PAID seq fee dest))
                "fee paid")
              "no fee"))
        (emit-event (ROUND-RESULT seq dr seed))
        seed)))

  (defun prove-liveness:integer (rnd:integer sig-hex:string)
    @doc "Permissionless: verify a drand beacon and record that drand was alive at that round. One call blocks a premature refund on every pending round at or below it."
    ; Without this, "drand went away" would be indistinguishable from "nobody
    ; settled this round", and the second is a losing player's own choice.
    (let ((seed (verified-seed "liveness" rnd sig-hex)))
      (enforce (!= seed 0) "beacon did not verify")
      (with-read game-table GAME-KEY { "last-beacon" := lb }
        (enforce (> rnd lb) "a later beacon is already on record")
        (update game-table GAME-KEY { "last-beacon": rnd })
        (emit-event (LIVENESS-PROVEN rnd))
        rnd)))

  (defun void-round:string (seq:integer)
    @doc "Refund a round whose beacon can never arrive. Permissionless; needs ninety days AND no beacon verified at or after the round's own."
    (with-read rounds (rkey seq)
      { "state" := st, "drand-round" := dr, "reserve" := res, "stake" := stk }
      (enforce (= "open" st) "this round is not open")
      (enforce (> (diff-time (curr-time) (time-of-round dr)) VOID-AFTER)
        "the beacon can still be submitted")
      ; if this module has verified a beacon at or after this round's, drand was
      ; alive by then and the round must be resolved, not refunded
      (with-read game-table GAME-KEY { "last-beacon" := lb }
        (enforce (< lb dr)
          "drand has been seen since this round: resolve it, do not refund it"))
      ; no fee is taken on a void, so the accrual is dropped, not paid
      (update rounds (rkey seq) { "state": "void", "liability": stk, "fee-owed": 0.0 })
      (with-read game-table GAME-KEY { "reserved" := reserved }
        (update game-table GAME-KEY { "reserved": (- reserved (- res stk)) }))
      (emit-event (ROUND-VOID seq stk)))
    "round void: every stake is refundable")

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; CLAIM ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (defun claim:string (seq:integer account:string)
    @doc "Settle a board: spin its reels from the round's seed, release what it reserved and pay what it won, or refund it from a void round. PERMISSIONLESS: it always pays the account that placed the board, and a board that won nothing settles too."
    (with-read boards (bkey seq account)
      { "entries" := es, "total" := total, "reserve" := booked, "claimed" := done }
      (enforce (not done) "this board has already been claimed")
      (with-read rounds (rkey seq)
        { "state" := st, "seed" := seed, "liability" := liab, "settled" := ns }
        (let* ((played (cond ((= st "resolved") (play-entries seed account es))
                             ((= st "void") { "stops": [], "units": [], "payout": total })
                             (enforce false "this round has not been settled yet")))
               (amount (at 'payout played))
               ; what this board holds of the pot: the reserve it booked when it was
               ; placed, read from its own row so no later upgrade of a machine's
               ; maximum can change it (what it PAYS is scored by the code live
               ; now); its stake once the round is void
               (held (if (= st "void") total booked)))
          (update boards (bkey seq account)
            { "claimed": true, "stops": (at 'stops played), "payout": amount })
          (update rounds (rkey seq) { "liability": (- liab held), "settled": (+ ns 1) })
          (with-read game-table GAME-KEY { "reserved" := reserved }
            (update game-table GAME-KEY { "reserved": (- reserved held) }))
          (emit-event (SPINS-SETTLED account seq (map (lambda (e:object{entry}) (at 'machine e)) es) (at 'stops played) amount))
          (if (> amount 0.0)
              (let ((dest account))
                (install-capability (coin.TRANSFER HOUSE_ACCOUNT dest amount))
                (transfer HOUSE_ACCOUNT dest amount)
                (emit-event (CLAIMED account seq amount))
                (format "paid {}" [amount]))
              "settled: nothing to claim, this board did not win")))))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; VIEWS ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (defun get-round:object (seq:integer) (read rounds (rkey seq)))
  (defun get-board:object (seq:integer account:string) (read boards (bkey seq account)))
  (defun get-params:object () (read game-table GAME-KEY))

  (defun machines:[object] ()
    @doc "Every machine as it is played: its id, name, kind, strip, paytable, exact return [numerator denominator], house edge, maximum per unit staked, and the spins one board may play."
    (map (lambda (id:integer)
           (let ((m (machine-at id)))
             { "id": id, "name": (at 'name m), "kind": (at 'kind m)
             , "reel": (at 'reel m), "pays": (at 'pays m), "div": (at 'div m)
             , "return": (at id RETURNS), "house-edge": (at id EDGES)
             , "max-mult": (at id MAX-MULTS), "max-spins": MAX-SPINS }))
         (enumerate 0 (- MACHINE-COUNT 1))))

  ; The boards of one round, for whoever settles them. A full scan: for /local
  ; use, never inside a transaction.
  (defun round-boards:[object{board}] (seq:integer)
    (select boards (where 'seq (= seq))))

  ; Whether a board of total `s` fits in `room` at fee scale `scale`: the same
  ; inequality `bet` enforces, with the board's fee floored the same way.
  (defun board-fits:bool (m:integer s:decimal room:decimal scale:decimal)
    (<= (+ (board-reserve m s) (fee-for m s scale)) room))

  ; The largest board total on machine m that fits in `room`: the quotient floored
  ; to coin precision is never above the true maximum, and because `bet` floors
  ; the fee it can sit one unit under it, so the next unit is tried against the
  ; exact inequality.
  (defun max-board:decimal (room:decimal scale:decimal mb:decimal m:integer)
    (let* ((per-unit (+ (at m MAX-MULTS) (* scale (at m EDGES))))
           (under (floor (/ (if (> room 0.0) room 0.0) per-unit) PREC))
           (next (+ under 0.000000000001))
           (best (if (board-fits m next room scale) next under)))
      (if (>= best mb) best 0.0)))

  (defun pot-status:object ()
    @doc "Solvency at a glance, and for each machine EXACTLY the largest ONE-machine board total `bet` would ACCEPT right now (max-stakes, by machine id: the open round's headroom, or the share of the spare pot a fresh round may risk). A board plays one machine, so each figure stands alone. Under the minimum, 0.0."
    (let* ((bal (get-balance HOUSE_ACCOUNT))
           (g (read game-table GAME-KEY))
           (reserved (at 'reserved g))
           (available (- bal reserved))
           (scale (fee-scale available (at 'target-float g)))
           (cur (at 'current g))
           (open (if (= cur 0) false
                     (let ((r (read rounds (rkey cur))))
                       (and (= "open" (at 'state r)) (<= (curr-time) (at 'close-time r))))))
           ; the cap binds on the OPEN round, against the smaller of the pot at open
           ; and the pot now -- the same expression `bet` measures against; with no
           ; round open, a fresh round's cap, with nothing yet reserved
           (cap (if open
                    (let* ((r (read rounds (rkey cur))) (a0 (at 'avail-at-open r)))
                      (* (at 'frac-at-open r) (if (< available a0) available a0)))
                    (* (at 'reserve-fraction g) available)))
           (used (if open
                     (let ((r (read rounds (rkey cur)))) (+ (at 'exposure r) (at 'fee-owed r)))
                     0.0))
           (mb (if open (at 'min-bet-at-open (read rounds (rkey cur))) (at 'min-bet g)))
           (room (- cap used)))
      { "balance": bal, "reserved": reserved, "available": available
      , "fee-scale-now": scale, "min-bet": mb, "max-spins": MAX-SPINS
      ; "up to X today", per machine id: exactly the largest board total `bet` accepts now
      , "max-stakes": (map (max-board room scale mb) (enumerate 0 (- MACHINE-COUNT 1))) }))
)

