# How ChirpChirps 2.0 earns: proposal for Jackson (2026-11-18)

## The constraint that decides it

ChirpChirps only works when every friend has it. One person starts a flock and sends the
invite link; four or ten friends install it to join. Anything that charges the friends who
join breaks that loop. So whoever pays should be the person who starts the flock, the trip
organiser, who already cares the most.

## Options

**A. Free to join, one unlock for the flock starter (recommended).** One purchase, bought
once and restorable, the studio's usual shape (Crease Cracker's "The Whole City"). Working
name "Big Flock", suggested price $4.99.

- Free for everyone, always: joining any flock, talking, texts, captions (accessibility),
  Block, check-in (safety), Find, Demo Mode.
- The unlock, on the starter's phone only: flocks over 5 birds, more than one saved flock,
  and the extra bird colors and chirps.
- When a free flock passes 5 birds, the starter (only) sees a plain card: "Your flock has 6
  birds. Big Flock lets it grow, once, for $4.99." Nobody is cut off mid-trip: the flock
  keeps working and the card can be dismissed. Joiners never see a price.
- Honest limit: with no servers, the cap is counted on the starter's phone and is soft. That
  is fine for a $4.99 unlock; it is not a lock.
- Work: StoreKit 2 `Store` like Crease Cracker's, one product in App Store Connect, the card,
  a restore button, a StoreKit test config, and the purchase in the review notes (HARD RULE
  part 4: attach it to 2.0). About one session plus Jackson's App Store Connect product and
  price (a money action, his).

**B. Tip jar.** Free, with a "Buy the birds a coffee" set of consumables. No friction and
little money. Needs the same StoreKit work and review attachment.

**C. Paid up front ($1.99 or $2.99).** Every friend pays before they can join. Expect most
invites to die at the price. Not recommended.

**D. Free for 2.0, decide after launch.** Fastest to the store: no StoreKit, nothing to
attach, HARD RULE part 4 is met by having no purchases. Earns nothing until 2.1, but the
release list and first users come sooner.

## Recommendation

A, built after the two-device test and before 2.0 goes to review. If speed matters more
than revenue at launch, D, with A in 2.1.

## What I need

A pick (A, B, C or D), and if A or B: the name and price. Creating the product and its
price in App Store Connect is a money action, so that stays yours.

## Jackson's answer (Inbox, 2026-11-18; word for word)

> I like A. What about just charging for private relays? maybe another function or 2. that way, the public relays still get as many as possible, but it gives people a reason to buy

## What "private relays" can mean in 2.0 (follow-up, 2026-11-18)

2.0 has no separate relay to sell. Every phone with the app carries every packet it hears,
for anyone: open Nearby talk as it is, and private flocks sealed, so the phones in between
pass them along without being able to read them. That stays free for everyone whatever we
pick, which is the "public relays get as many as possible" half of his answer.

So what can be paid for is the **private flock** itself (locked with its own key, invite link
only). Reading his answer that way:

**A, as Jackson put it: Big Flock = start private flocks ($4.99, starter only).**
- Free, always: the app, talking and texting on the open Nearby line, captions, Block, roll
  call and "I need help" (they work on Nearby too), Demo Mode, **joining any private flock
  you are invited to**, and carrying everyone's messages.
- Big Flock: **start** a private flock and send its invite link. Joiners never pay. Plus the
  "function or 2": (1) the extra bird colors and chirps, (2) more than one saved flock.
- One catch to decide on: check-in, Find and Ping only work between people in the same private
  flock (that is what keeps location and pings away from strangers). A group where nobody has
  bought Big Flock has none of the three, and everything they say on Nearby can be heard by
  anyone in range. The App Store copy and review notes would have to say so plainly.

**Softer version, if that catch is too sharp:** private flocks are free up to 4 birds (a couple,
a small family); Big Flock lifts the cap, plus the same two extras. More people get the safety
features for free, fewer have a reason to buy.

Either way the build is the same StoreKit work (one product, restore, a StoreKit test file,
the purchase attached to 2.0), plus the gate on "Start a flock". Creating the product and its
price in App Store Connect stays his (a money action).
