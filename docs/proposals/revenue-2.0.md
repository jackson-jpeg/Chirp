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
