# ChirpChirp — device smoke test

**One session, two phones, 30–45 minutes.** Clears every outstanding
DEVICE-UNVERIFIED item in one pass.

Written to be run, not read. No code knowledge needed. Write what actually
happened in the boxes as you go — "didn't try" and "not sure" are useful
answers; a blank is not.

This supersedes `REPRO-BACKGROUND-AUDIO.md`, which is now Part 3 below.

---

## Why this exists

Three separate fixes have landed in the audio and floor-control paths with no
phone anywhere near them:

| Commit | What changed | Risk if it's wrong |
|---|---|---|
| `0bb2b19` | The microphone capture path was rewritten to copy each chunk of audio instead of reusing the engine's buffer | **No audible sound at all**, or distorted sound |
| `7947e65` | Floor control (whose turn it is to talk) now resolves contention in every state | Wrong speaker name, or a stuck talk button |
| `e1f38a3` | A background service was deleted | Was suspected of killing audio after backgrounding — needs confirming |

Part 1 establishes that the app works at all. **If Part 1 fails, stop and tell
me.** Nothing after it will mean anything.

---

## Before you start

**Two iPhones.** Called **Phone A** and **Phone B** throughout — keep them
consistent, because which phone does what matters for interpreting results.

The Mac currently sees:

- **Jackson's Sacre Bleu** (iPhone 17 Pro Max) — connected
- **iPhone** (iPhone 16 Pro) — *unavailable*, so it needs plugging in and
  unlocking, and "Trust This Computer" if it asks

### Installing — read this, there's a snag

There is **no Development provisioning profile** for ChirpChirp on the Mac right
now, only App Store ones. `ios install` needs a Development profile, so it will
fail until one is made. Run these in order, on the **VPS**:

```
ios certs refresh chirp        # creates the Development profile — once, first
ios install chirp              # builds and installs on the connected iPhone
```

Then unplug Phone A, plug in Phone B, unlock it, and run `ios install chirp`
again.

If `certs refresh` complains that a device isn't registered, both phones need
adding to the Apple Developer account first (Devices → add by UDID). Tell me if
you hit that and I'll get you the UDIDs.

**Build being tested:** `7947e65`, or whatever `git -C /root/Chirp log -1
--oneline` shows when you install. Write it here so we know what these results
describe:

> **Build tested:** ________________________________

### Setup on both phones

- **Force-quit ChirpChirp** before starting (swipe up, swipe the card away).
  Every part below assumes a clean launch.
- Volume up, phones a few feet apart, not in airplane mode.
- Grant microphone permission when asked.

### Optional but very valuable

Plug Phone A into the Mac, open **Console** (Applications → Utilities →
Console), select Phone A in the sidebar, click **Start streaming**, and type
`com.chirpchirp.app` in the search box. Leave it running the whole session. It
turns "it didn't work" into a precise diagnosis. If you do this, say so and I'll
tell you which lines matter.

---

## Part 1 — Does it work at all?

**This is the gate. Everything else depends on it.**

### 1.1 Launch and connect

1. Launch ChirpChirp on **both** phones.
2. Wait up to 30 seconds.

**Expected:** each phone lists the other as a connected peer.

> **Did each phone see the other?**  YES / NO
> **How long did it take?** ______ seconds
> **Notes:**
>
> ______________________________________________

### 1.2 Talk and hear — A to B

1. On **Phone A**, press and hold the talk button.
2. Say "one two three four five" clearly.
3. Release.

**Expected:** Phone B plays the audio, audibly, roughly as you said it. Some
delay is fine. Radio-ish quality is fine and expected.

> **Did Phone B produce sound?**  YES / NO
> **Could you make out the words?**  CLEARLY / MUFFLED BUT AUDIBLE / GARBLED / SILENT
> **Notes (robotic? clipped? cut off at the start or end?):**
>
> ______________________________________________

### 1.3 Talk and hear — B to A

Same again, in the other direction.

> **Did Phone A produce sound?**  YES / NO
> **Could you make out the words?**  CLEARLY / MUFFLED BUT AUDIBLE / GARBLED / SILENT

### 1.4 The level meter

While holding the talk button on Phone A, watch the waveform / level indicator
on **Phone A's own screen**.

This is worth its own check because the level display was changed to be
calculated in a different place. It can be wrong while the audio itself is fine.

> **Does it move when you speak?**  YES / NO
> **Does it sit still, or stay pinned at maximum?** ______________________
> **Does it respond to loud vs quiet?**  YES / NO

---

### ⛔ STOP HERE IF PART 1 FAILED

If there was no sound in 1.2 or 1.3, **stop and tell me.** That means the
capture rewrite broke audio and everything below is noise. Note anything you saw
and send it over — this is exactly what the test is for, and finding it here is
the good outcome.

---

## Part 2 — Sustained transmission

The old code handed the audio engine a buffer it was about to overwrite. If any
of that survived, longer transmissions are where it shows.

1. On **Phone A**, hold the talk button and count slowly to twenty.
2. Listen on Phone B for the whole twenty seconds.

**Expected:** continuous, intelligible audio for the full twenty seconds. No
crash.

> **Did it stay intelligible the whole time?**  YES / NO
> **If it degraded, roughly when?** after ______ seconds
> **What did the degradation sound like?** (stutter / robotic / silence /
> repeating / static)
>
> ______________________________________________
>
> **Did either app crash?**  YES / NO

Now the same in the other direction, twenty seconds B → A.

> **Same result?**  YES / NO — if different, say how: ____________________

---

## Part 3 — Backgrounding (the big one)

**What we're finding out:** whether leaving the app and coming back permanently
kills audio until you force-quit.

**Why it matters:** a component whose job was to keep the mesh alive in the
background was deleted in `e1f38a3`. It was suspected of switching the phone's
audio system off on every return to the foreground, with nothing switching it
back on. If that was the cause, this is now fixed. If the symptom is still
there, my main hypothesis was wrong and I need to know before rewriting the
audio layer around it.

**The fingerprint to watch for:** *peers still connected, but no sound.* The
networking and the audio are separate systems, so "connected but silent" is the
specific combination that points at audio session ownership.

### 3.1 Home button

1. Both apps open and connected. Confirm A → B audio works right now.
2. On **Phone A only**: swipe up to the home screen. Wait 10 seconds.
3. Tap back into ChirpChirp on Phone A.
4. Wait 5 seconds.
5. **Phone A**: hold talk, say "after background".

> **Are the phones still showing each other as connected?**  YES / NO
> **Did Phone B hear it?**  YES / NO

6. Now the other direction: **Phone B**: hold talk, say "reply".

> **Did Phone A hear it?**  YES / NO

**Interpretation:** if A can't send but B can, the problem is A's *capture*. If A
can't hear either, it's A's whole audio session. Both are useful; they point
different directions.

### 3.2 Does it recover on its own?

If 3.1 broke audio, don't force-quit yet.

1. Wait 30 seconds without touching anything.
2. Try A → B again.

> **Did it come back by itself?**  YES / NO

### 3.3 Does force-quitting fix it?

1. Force-quit ChirpChirp on Phone A. Relaunch. Reconnect.
2. Try A → B.

> **Did audio work again after a fresh launch?**  YES / NO

**If yes:** that is the classic fingerprint of the audio session being switched
off and never switched back on — the defect is still live and I'll go straight at
it. **If audio never broke at all in Part 3:** deleting the background service
fixed it, and I can close defect #1.

### 3.4 Lock screen

Same as 3.1, but instead of the home screen, press the side button to lock Phone
A, wait 10 seconds, unlock, and try to talk.

> **Did audio survive a lock/unlock?**  YES / NO
> **Any difference from the home-screen test?** ____________________

### 3.5 Backgrounded mid-transmission

1. On Phone A, hold the talk button and start counting.
2. **While still holding**, swipe up to the home screen.
3. Come back into the app. Release the button.

This is deliberately awkward — I want to know what it does, not that it's
graceful.

> **Did either app crash?**  YES / NO
> **Did Phone A get stuck showing itself as transmitting?**  YES / NO
> **Did Phone B get stuck showing A as speaking?**  YES / NO
> **Could you talk normally afterwards?**  YES / NO

---

## Part 4 — Floor control (whose turn it is to talk)

Three separate stuck-microphone defects were fixed here. These are the checks
that they're actually fixed, and that the fix didn't break normal use.

### 4.1 Normal turn-taking

1. A talks for 3 seconds, releases.
2. B talks for 3 seconds, releases.
3. Repeat three times, promptly.

> **Did each phone correctly show the other's name while they were talking?**
> YES / NO
> **Did the name clear when they stopped?**  YES / NO
> **Did either phone ever get stuck showing someone as talking?**  YES / NO

### 4.2 Both at once (the collision fix)

Genuinely simultaneous — count down out loud and both press on zero. Try five
times.

**Expected:** exactly one phone transmits. The other shows the winner's name, or
briefly shows a "denied" indication. Both phones must agree on who won.

> **Did exactly one win each time?**  YES / NO — if not, how many times did both
> appear to transmit? ______
> **Did the two phones ever disagree about who was talking?**  YES / NO
> **Did the loser's microphone stop, or did it keep sending?** (does the loser
> still show itself as transmitting?) ____________________

### 4.3 Pressing while the other person is talking

1. **Phone B** holds talk and keeps talking for 10 seconds.
2. While B is talking, **tap** Phone A's talk button once. Let go.
3. Wait 2 seconds. **Tap it again.** Let go.
4. Keep B talking throughout.

**Expected:** both taps are refused. Phone A keeps showing B as the speaker
throughout, and A never transmits over B.

> **Was the first tap refused?**  YES / NO
> **Was the second tap refused?**  YES / NO
> **After the taps, did Phone A still show B as speaking?**  YES / NO
> **Did Phone A ever manage to talk over B?**  YES / NO

*(Before the fix, the second tap would have gone through and A would have
transmitted over B.)*

### 4.4 Double-press while talking — the stuck button

1. On **Phone A**, press and hold talk. Start counting.
2. **While still holding, tap the button again** with another finger.
3. Keep counting for 5 more seconds.
4. Release everything.
5. On **Phone B**: try to talk.

**Expected:** A's transmission is unaffected; when A lets go, B can immediately
talk.

> **Did A's audio keep going after the second press?**  YES / NO
> **When A released, did B show A as having stopped?**  YES / NO
> **Could B talk straight away?**  YES / NO
> **If B could not talk — how long until it could?** ______ seconds
> (If the answer is "about two minutes", that's the safety-net timer, and it
> means the fix didn't hold.)

### 4.5 Walk out of range mid-transmission

1. A holds talk and keeps talking.
2. Walk B into another room / far enough to drop the connection.
3. Keep A talking, then release.
4. Bring B back.

> **Did A get stuck transmitting?**  YES / NO
> **Did B get stuck showing A as speaking after losing the connection?** YES / NO
> **Did they reconnect on their own?**  YES / NO — after ______ seconds
> **Could they talk normally afterwards?**  YES / NO

---

## Part 5 — Leave it running

Put both phones down, apps open, for **10 minutes**. Don't touch them.

Then try A → B.

> **Still connected after 10 minutes?**  YES / NO
> **Did audio still work?**  YES / NO
> **Did either app crash or get killed?**  YES / NO

---

## What I could not give you a test for

**Anything needing three phones.** With two, these stay unverified and I'll
implement and cover them in the harness instead, per your instruction:

- A third device showing the wrong speaker after missing a release message.
- One peer disconnecting causing the *other* two to mark each other dead.

**The two floor-control holes I confirmed by test this morning** — a peer can
end your turn without closing your microphone. Reproducing those needs a
deliberately misbehaving peer, which is not something you can do by pressing
buttons. They're covered by the rebuild I'm proposing, not by this session.

---

## When you're done

Send me back:

1. This file with the boxes filled in.
2. Whether **Part 1 passed** — that's the headline.
3. Anything that surprised you, even if it's not on the list. Especially that.

If something crashes, note **what you were doing in the ten seconds before it**.
That's usually worth more than the crash log.
