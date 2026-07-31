# Reproduction steps — Defect #1: audio dies after backgrounding

**Written for running on devices, not for reading code.** No technical
background needed. Roughly 20 minutes including setup.

**What we are trying to find out:** whether returning to ChirpChirp from the
home screen (or from a locked screen) permanently kills the app's audio until
you force-quit and relaunch it.

**Why it matters:** if this reproduces, it is the highest-value confirmed defect
in the project and it explains a large share of "the app just stops working"
reports. If it does *not* reproduce, my top hypothesis is wrong and I need to
know that before I start rewriting the audio layer around it.

---

## What I believe is happening, in plain terms

The app has a component whose job is to keep the mesh network alive while the
app is in the background. Every time you bring the app back to the foreground,
that component **switches the phone's audio system off** for this app — and
nothing ever switches it back on. The only thing that switches it on is app
launch.

So the prediction is: **audio works until the first time you background the app,
and is dead from then on, for the rest of that launch.**

The mesh/networking side is a separate system, so I expect **peers to stay
connected** even while audio is dead. That combination — connected but silent —
is the specific fingerprint I'm looking for.

---

## Before you start

- **Two iPhones**, both with the current build installed.
- Call them **Phone A** and **Phone B**. Keep them consistent throughout —
  which phone does what matters for interpreting the results.
- Both phones: **force-quit ChirpChirp** (swipe up from the bottom, swipe the
  ChirpChirp card away). Every test below assumes a clean launch.
- Have them a few feet apart, both off Wi-Fi hotspot / airplane mode.
- Turn the volume up on both.
- **Optional but very valuable:** plug Phone A into the Mac, open the
  **Console** app (Applications → Utilities → Console), select Phone A in the
  left sidebar, click **Start streaming**, and type `com.chirpchirp.app` in the
  search box. Leave it running for the whole session. If you can do this, tell
  me and I'll tell you exactly which lines to look for. It turns "it didn't
  work" into a precise diagnosis.

---

## Test 1 — Control: does it work at all before backgrounding?

This test exists to prove the setup is good. If this fails, stop — nothing below
will mean anything.

1. Launch ChirpChirp on **both** phones.
2. Grant microphone permission if asked.
3. Wait until each phone shows the other as a connected peer.
4. On **Phone A**: press and hold the talk button. Say "test one".
5. Release.

**Expected:** Phone B plays "test one".

| Result | What it means |
|---|---|
| ✅ Phone B hears it | Setup is good. Continue to Test 2. |
| ❌ Nothing heard | **Stop and tell me.** Audio is broken before backgrounding is even involved, which is a different and worse problem than the one I'm testing for. |
| ❌ Peers never connected | **Stop and tell me.** That's a separate defect (peer discovery), also worth knowing about. |

---

## Test 2 — The main event: background and return

Do not force-quit between Test 1 and Test 2. This must be the same launch.

1. On **Phone A**, swipe up to go to the home screen. (Do **not** swipe the app
   away — just go home. The app should still be in the app switcher.)
2. Wait **10 seconds**. Count them.
3. Tap the ChirpChirp icon to bring Phone A back.
4. Wait for the screen to settle — 2 or 3 seconds.
5. **Check first, before talking:** does Phone A still show Phone B as a
   connected peer?
6. On **Phone A**: press and hold the talk button. Say "test two".
7. Release.
8. Now the reverse direction. On **Phone B** (which was never backgrounded):
   press and hold, say "test two reply", release.

**Record all three observations:**

| # | Question | Answer |
|---|---|---|
| 2a | After returning, was Phone B still listed as connected on Phone A? | yes / no |
| 2b | Did Phone B hear "test two" from Phone A? | yes / no |
| 2c | Did Phone A hear "test two reply" from Phone B? | yes / no |

**How to read it:**

| Pattern | What it means |
|---|---|
| 2a **yes**, 2b **no**, 2c **no** | **This is my prediction, confirmed.** Still connected, audio dead in both directions on the phone that was backgrounded. Highest-confidence outcome. |
| 2a yes, 2b no, 2c **yes** | Partial — only the microphone died, not the speaker. Still a confirmation, but narrows it to the capture side. Note it precisely. |
| 2a **no** | The mesh dropped too. That points at the process being suspended or killed rather than the audio system being switched off — a *different* diagnosis. Important either way. |
| 2a yes, 2b **yes**, 2c yes | **My hypothesis is wrong** as stated, or the trigger needs longer in the background. Continue to Test 3 before concluding. |

---

## Test 3 — Is it permanent, or does it recover?

Only if Test 2 showed dead audio. Stay in the same launch.

1. Wait 30 seconds with the app open in the foreground. Don't touch it.
2. Try talking from **Phone A** again.
3. If still dead: background Phone A and return again. Try talking.
4. If still dead: on Phone A, leave and re-enter the channel (or toggle the
   talk mode) if the UI allows it, then try again.

| Result | What it means |
|---|---|
| Never recovers within the launch | Confirms "permanent until relaunch". This is what I expect. |
| Recovers after some action | **Tell me exactly which action.** That's a big clue — it tells me what path in the app happens to switch audio back on, which is a candidate for the real fix. |

---

## Test 4 — Confirm relaunch clears it

1. Force-quit ChirpChirp on **Phone A** (swipe the card away).
2. Relaunch it. Wait for the peer to reconnect.
3. Talk from Phone A **without** backgrounding it first.

**Expected:** works again.

| Result | What it means |
|---|---|
| ✅ Works | Confirms the whole picture: healthy at launch, dead after backgrounding, healthy again after relaunch. This is a complete, tight reproduction and it's all I need. |
| ❌ Still dead | Something more persistent is wrong. Tell me — my diagnosis would be incomplete. |

---

## Test 5 — Does locking the screen do it too?

Worth knowing because it's the most common way users background an app without
meaning to.

1. Force-quit and relaunch Phone A. Confirm talking works.
2. Press the **side button** to lock Phone A's screen. Wait 10 seconds.
3. Unlock. Try talking.

| Result | What it means |
|---|---|
| Audio dead | The defect fires on screen lock too, so users hit it constantly without ever leaving the app. Raises the severity considerably. |
| Audio fine | The trigger is specifically leaving the app, not locking. Narrower than I thought — useful. |

---

## Test 6 — Does time in the background change anything?

Only worth doing if Tests 2–5 were inconclusive.

Repeat Test 2, but wait **2 minutes** in the background instead of 10 seconds.

| Result | What it means |
|---|---|
| 10 seconds fine, 2 minutes dead | The trigger is time-based, which points at iOS suspending the app rather than the app switching its own audio off. **Different diagnosis** — I'd need to rethink. |
| Dead either way | Time isn't a factor. Consistent with my hypothesis. |

---

## What to send me

Just the table answers plus anything surprising. Specifically:

1. Test 1: pass or fail.
2. Test 2: the three yes/no answers (2a, 2b, 2c).
3. Test 3: did it ever recover, and if so after what.
4. Test 4: did relaunch fix it.
5. Test 5: does screen lock trigger it.
6. Test 6: only if you ran it.
7. Anything you noticed that isn't covered above — a frozen UI, the app
   relaunching itself, the talk button not responding, battery heat, a peer
   count that flickers. Especially: **did the app ever appear to restart on its
   own?** That would mean it was being killed, which is a different problem again.

---

## Honest caveats

- **I have not run any of this.** These steps are derived from reading the code,
  not from observing a device. That is exactly why I want you to run them: the
  reasoning is only as good as the evidence, and there is currently no crash log
  or device recording anywhere in this project to check it against.
- **Two devices is enough for this particular test.** Some other defects in the
  audit need three phones; this one doesn't.
- **A negative result is a genuinely useful result.** If Test 2 comes back all
  "yes", I need to know before I rebuild the audio-session layer around a wrong
  theory. Don't try to make it fail — just report what happens.
- **Do not force-quit between Tests 1 and 2.** That is the single most common way
  to accidentally get a false negative here, because relaunching is exactly what
  I predict repairs it.
