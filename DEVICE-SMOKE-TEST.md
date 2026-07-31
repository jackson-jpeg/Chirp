# ChirpChirp — device smoke test

Two phones. **Two independently runnable halves**, because they are ready at
different times and must be attributed to different commits.

| | Covers | Run against | Ready | Time |
|---|---|---|---|---|
| **Part A** | Launch, connect, talk, hear, sustained audio, backgrounding | `620e42b` or later, **as long as `FloorController.swift` is untouched** | **now** | 25–30 min |
| **Part B** | Floor control: collisions, double-press, yielding, stale holder | the FloorController rebuild — hash filled in when it lands | after the rebuild | 15–20 min |

**Record the commit you actually installed.** At install time run
`git -C /root/Chirp log -1 --oneline` and write it in the box in whichever part
you're running. Results attributed to the wrong build are worse than no results.

Written to be run, not read. No code knowledge needed. Write what actually
happened in the boxes — "didn't try" and "not sure" are useful answers; a blank
is not.

Supersedes `REPRO-BACKGROUND-AUDIO.md`, folded in as A3.

---

## Installing — read this, there's a snag

There is **no Development provisioning profile** for ChirpChirp on the Mac, only
App Store ones, and `ios install` needs a Development one. On the **VPS**:

```
ios certs refresh chirp        # creates the Development profile — once, first
ios install chirp              # builds and installs on the connected iPhone
```

Then unplug Phone A, plug in Phone B, unlock it, run `ios install chirp` again.

If `certs refresh` says a device isn't registered, both phones need adding to
the Apple Developer account (Devices → add by UDID). Tell me and I'll get you
the UDIDs.

**TestFlight is not an option** — all five builds there expired, the newest is
from 23 April, and it is 23 commits behind. Cable install is the only route.

The Mac currently sees:

- **Jackson's Sacre Bleu** (iPhone 17 Pro Max) — connected
- **iPhone** (iPhone 16 Pro) — *unavailable*; needs plugging in, unlocking, and
  "Trust This Computer" if it asks

### Setup, both phones, before either part

- **Force-quit ChirpChirp** (swipe up, swipe the card away). Every test assumes
  a clean launch.
- Volume up, phones a few feet apart, not in airplane mode.
- Grant microphone permission when asked.
- Call them **Phone A** and **Phone B** and keep them consistent — which phone
  does what matters for interpreting results.

### Optional but very valuable

Plug Phone A into the Mac, open **Console** (Applications → Utilities →
Console), select Phone A in the sidebar, **Start streaming**, and search
`com.chirpchirp.app`. Leave it running. It turns "it didn't work" into a precise
diagnosis. Say if you do this and I'll tell you which lines matter.

---
---

# PART A — audio and lifecycle

**Run against `620e42b` or later, provided `Chirp/Sources/Services/PTT/FloorController.swift`
has not changed.** If it has, you are running Part B's build and should do Part
B too.

> **Commit installed:** ________________________________
> **Date/time run:** ________________________________

## Why Part A exists

Three fixes landed in the audio and lifecycle paths with no phone anywhere near
them:

| Commit | What changed | Risk if wrong |
|---|---|---|
| `0bb2b19` | Microphone capture rewritten to copy each chunk instead of reusing the engine's buffer | **No audible sound at all**, or distorted sound |
| `e1f38a3` | A background service was deleted | Was suspected of killing audio after backgrounding — needs confirming |
| `155e17a` | Voice-message parsing hardened | A malformed message used to crash the app |

**A1 is a hard gate. If it fails, stop and tell me** — it means capture is broken
and everything after it is noise. Finding that here is the good outcome.

---

## A1 — Does it work at all?

### A1.1 Launch and connect

1. Launch ChirpChirp on **both** phones.
2. Wait up to 30 seconds.

**Expected:** each phone lists the other as a connected peer.

> **Did each phone see the other?**  YES / NO
> **How long?** ______ seconds
> **Notes:** ______________________________________________

### A1.2 Talk and hear — A to B

1. **Phone A**: press and hold talk. Say "one two three four five" clearly.
2. Release.

**Expected:** Phone B plays it, audibly. Some delay is fine. Radio-ish quality is
fine and expected.

> **Did Phone B produce sound?**  YES / NO
> **Words intelligible?**  CLEARLY / MUFFLED BUT AUDIBLE / GARBLED / SILENT
> **Notes (robotic? clipped? cut off at start or end?):**
> ______________________________________________

### A1.3 Talk and hear — B to A

Same, other direction.

> **Did Phone A produce sound?**  YES / NO
> **Words intelligible?**  CLEARLY / MUFFLED BUT AUDIBLE / GARBLED / SILENT

### A1.4 The level meter

While holding talk on Phone A, watch the waveform on **Phone A's own screen**.
Worth its own check: the level calculation moved to a different place, and it can
be wrong while the audio itself is fine.

> **Does it move when you speak?**  YES / NO
> **Sits still, or pinned at maximum?** ______________________
> **Responds to loud vs quiet?**  YES / NO

---

### ⛔ STOP IF A1 FAILED

No sound in A1.2 or A1.3 → stop, note what you saw, tell me.

---

## A2 — Sustained transmission

The old code handed the audio engine a buffer it was about to overwrite. If any
of that survived, long transmissions are where it shows.

1. **Phone A**: hold talk, count slowly to twenty. Listen on B throughout.

> **Intelligible the whole time?**  YES / NO
> **If it degraded, when?** after ______ seconds
> **What did it sound like?** (stutter / robotic / silence / repeating / static)
> ______________________________________________
> **Did either app crash?**  YES / NO

Repeat B → A.

> **Same result?**  YES / NO — if different: ____________________

---

## A3 — Backgrounding (the big one)

**What we're finding out:** whether leaving the app and coming back permanently
kills audio until you force-quit.

**Why it matters:** a component that kept the mesh alive in the background was
deleted in `e1f38a3`. It was suspected of switching this app's audio system off
on every return to the foreground, with nothing switching it back on. If that was
the cause, this is now fixed. If the symptom survives, my main hypothesis was
wrong and I need to know before rewriting the audio layer around it.

**Fingerprint to watch for:** *peers still connected, but no sound.* Networking
and audio are separate systems, so "connected but silent" points specifically at
audio session ownership.

### A3.1 Home button

1. Both apps open and connected. Confirm A → B works right now.
2. **Phone A only**: swipe up to the home screen. Wait 10 seconds.
3. Tap back into ChirpChirp. Wait 5 seconds.
4. **Phone A**: hold talk, say "after background".

> **Still showing each other as connected?**  YES / NO
> **Did Phone B hear it?**  YES / NO

5. **Phone B**: hold talk, say "reply".

> **Did Phone A hear it?**  YES / NO

**Interpretation:** A can't send but B can → A's *capture* is dead. A can't hear
either → A's whole audio session is dead. Different directions, both useful.

### A3.2 Does it recover on its own?

If A3.1 broke audio, **don't force-quit yet.** Wait 30 seconds untouched, try
A → B again.

> **Came back by itself?**  YES / NO

### A3.3 Does force-quitting fix it?

Force-quit on Phone A, relaunch, reconnect, try A → B.

> **Audio worked again after fresh launch?**  YES / NO

**If yes:** classic fingerprint of the audio session being switched off and never
switched back on — defect #1 is still live and I go straight at it. **If audio
never broke at all in A3:** deleting the background service fixed it and I can
close defect #1.

### A3.4 Lock screen

As A3.1, but lock Phone A with the side button instead, wait 10 seconds, unlock,
talk.

> **Audio survived lock/unlock?**  YES / NO
> **Any difference from the home-screen test?** ____________________

### A3.5 Backgrounded mid-transmission

1. Phone A: hold talk, start counting.
2. **While still holding**, swipe up to the home screen.
3. Come back into the app. Release.

Deliberately awkward — I want to know what it does, not that it's graceful.

> **Did either app crash?**  YES / NO
> **Did Phone A get stuck showing itself as transmitting?**  YES / NO
> **Did Phone B get stuck showing A as speaking?**  YES / NO
> **Could you talk normally afterwards?**  YES / NO

*(If A gets stuck, note it and move on — that is floor-control behaviour and
Part B covers it properly.)*

---

## A4 — Leave it running

Both phones down, apps open, **10 minutes**, untouched. Then A → B.

> **Still connected?**  YES / NO
> **Audio still worked?**  YES / NO
> **Did either app crash or get killed?**  YES / NO

---

## Part A — send me back

1. This file with A1–A4 filled in.
2. **Whether A1 passed.** That's the headline.
3. Anything that surprised you, even if it's not on the list. Especially that.

If something crashes, note **what you were doing in the ten seconds before it**.
Usually worth more than the crash log.

---
---

# PART B — floor control

**Do not run yet.** FloorController is being rebuilt as an explicit state
machine. Running this against the current build tests code that is about to be
replaced, and two known stuck-microphone paths are open in it.

> **Run against commit:** ______________________ *(I will fill this in when
> the rebuild lands, and tell you.)*
>
> **Commit installed:** ________________________________
> **Date/time run:** ________________________________

## Why Part B is separate

Five stuck-microphone defects have been found in this component. Three are fixed;
two are open and are the reason for the rebuild. Testing it now would measure
code that will not exist next week.

## B1 — Normal turn-taking

1. A talks 3 seconds, releases. B talks 3 seconds, releases. Repeat three times,
   promptly.

> **Did each phone correctly show the other's name while they talked?** YES / NO
> **Did the name clear when they stopped?**  YES / NO
> **Did either phone ever get stuck showing someone as talking?**  YES / NO

## B2 — Both at once (collisions)

Genuinely simultaneous — count down out loud, both press on zero. Five times.

**Expected:** exactly one phone transmits. The other shows the winner's name or
briefly shows a "denied" indication. Both phones agree on who won.

> **Exactly one winner each time?**  YES / NO — if not, how many times did both
> appear to transmit? ______
> **Did the phones ever disagree about who was talking?**  YES / NO
> **Did the loser's microphone stop?** (does the loser still show itself as
> transmitting?) ____________________

## B3 — Pressing while the other is talking

1. **Phone B** holds talk, keeps talking 10 seconds.
2. While B talks, **tap** Phone A's talk button once. Let go.
3. Wait 2 seconds. **Tap again.** Let go. Keep B talking throughout.

**Expected:** both taps refused. Phone A keeps showing B as speaker throughout
and never transmits over B.

> **First tap refused?**  YES / NO
> **Second tap refused?**  YES / NO
> **Did Phone A still show B as speaking afterwards?**  YES / NO
> **Did Phone A ever talk over B?**  YES / NO

## B4 — Double-press while talking (the stuck button)

1. **Phone A**: press and hold talk, start counting.
2. **While still holding, tap the button again** with another finger.
3. Keep counting 5 more seconds. Release everything.
4. **Phone B**: try to talk.

> **Did A's audio keep going after the second press?**  YES / NO
> **When A released, did B show A as stopped?**  YES / NO
> **Could B talk straight away?**  YES / NO
> **If not — how long until it could?** ______ seconds
> *(If the answer is "about two minutes", that's the safety-net timer, and the
> fix did not hold.)*

## B5 — Walk out of range mid-transmission

1. A holds talk, keeps talking. Walk B out of range.
2. Keep A talking, then release. Bring B back.

> **Did A get stuck transmitting?**  YES / NO
> **Did B get stuck showing A as speaking after the drop?**  YES / NO
> **Did they reconnect on their own?**  YES / NO — after ______ seconds
> **Could they talk normally afterwards?**  YES / NO

## B6 — Three devices (only if a third phone appears)

The stale-holder case needs three. If you can borrow one:

1. All three connected. **A** talks; confirm **B** and **C** both show A.
2. A releases. Immediately **B** presses and talks.

> **Did C switch to showing B, or stay stuck on A?**  SWITCHED / STUCK ON A
> **Did C ever show nobody talking while B was talking?**  YES / NO

---

## What no button-pressing session can cover

**The two open stuck-microphone paths.** A peer can end your turn without
closing your microphone by sending a message naming your device. Reproducing that
needs a deliberately misbehaving peer, not a button press. It is covered by the
rebuild and its tests, not by this session.

## Part B — send me back

This file with B1–B6 filled in, plus the commit you installed.
