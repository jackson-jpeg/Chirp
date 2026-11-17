# Can ChirpChirps keep receiving with the phone locked and no signal?

2026-11-17. Asked by the lead before scope item 7 (Lock Screen and Dynamic Island Live Activity
with a talk button). **Status: answered from Apple's documentation and its engineers' forum
replies; NOT yet proven on hardware.** The hardware test (section 4) needs two devices, and Chirp
has no simulator yet (Inbox item `chirp-2-0-jackson`). Until it runs, treat every "no" below as
"Apple says no", which is strong but not a measurement.

## Short answer

- **Live voice while locked, with no signal: no, not within the App Store rules.** Apple's
  push-to-talk framework, the one sanctioned way to receive and transmit PTT from the Lock Screen
  and Dynamic Island, wakes the app for incoming audio with an APNs push from a server (or Local
  Push Connectivity on a managed Wi-Fi network). With no signal there is no push, so nothing wakes
  the app. The only thing that would keep a locked phone listening on a phone-to-phone link is
  the `audio` background mode, and that is exactly what 1.0 was rejected for (2.5.4).
- **Texts and "someone is talking" alerts while locked: possibly, over Bluetooth LE**, with the
  `bluetooth-central` / `bluetooth-peripheral` background modes. This needs testing: two locked
  iPhones are reported to have trouble finding each other.
- **Item 7 as asked (a talk button on the Lock Screen that works with no signal): not possible as
  far as the documentation goes.** What is possible: a Live Activity that shows the channel and
  the last speaker while the app is open or recently used, with a button that opens the app
  (foreground) to talk. And the push-to-talk framework's own system UI *when there is signal*,
  which needs a relay server: a different product.
- **Separately, and urgent for 2.0's design:** MultipeerConnectivity, which 1.0's transport is
  built on, "has been officially deprecated in Xcode 27 beta" (Apple DTS, forum thread 836124).
  2.0's transport should be built on Network framework (Bonjour with peer-to-peer Wi-Fi), not on
  MultipeerConnectivity. The ChirpCore design does not change: the transport only moves bytes.

## 1. What Apple's documentation says

**Push to Talk framework** ("Creating a Push to Talk app", developer.apple.com):
- Needs the Push to Talk background mode, the Push to Talk capability and Push Notifications.
- Joining a channel: "A person can only join a channel when a PTT app is running in the
  foreground, with explicit user interaction."
- Receiving: "When an app's server has new audio for a person to receive, it sends a PTT
  notification using the device push token ... Set the APNs push type to `pushtotalk`." Then
  "the system starts the app in the background" and activates its audio session.
- No internet: "use the Local Push Connectivity API ... to receive incoming PTT messages without
  relying on APNs". This needs a server on a configured, matching Wi-Fi network and its own
  entitlement. It is meant for enterprise and restricted networks, not a festival or a ski slope.
- Transmitting: "Start PTT transmissions from the system UI or by calling
  `requestBeginTransmitting` ... when the app is running in the foreground or following a
  characteristic change from a CoreBluetooth device." The system UI (Lock Screen, Dynamic
  Island) is the framework's own. "The framework doesn't support custom sound effects", which
  matters for scope item 6 (each person's own start-talking chirp) on that path.

**Background execution** (Apple DTS, "iOS Background Execution Limits", forum thread 685525):
- iOS's "default behaviour is to suspend your app shortly after the user has moved it to the
  background; this suspension prevents the process from running any code."
- "There's no general-purpose mechanism for ... resuming in the background in response to a
  network or IPC request."
- Background modes "each fulfil a specific purpose. Do not attempt to use them for some other
  purpose. Before using a background API, read clause 2.5.4."

**MultipeerConnectivity in the background** (Apple DTS reply, forum thread 836124, on a
MultipeerConnectivity mesh like ours): "Multipeer Connectivity was never meant to be used in the
background", "Multipeer Connectivity has been officially deprecated in Xcode 27 beta", and other
networking APIs "don't work when the app is suspended in the background ... There aren't general
purpose ways to achieve either of those goals" (resuming on network activity, or running
indefinitely).

**Bluetooth LE in the background** (Apple's Core Bluetooth best practices, and forum threads):
- With the Bluetooth background modes iOS keeps scanning, advertising and connections going for
  a suspended app and wakes it for Bluetooth events. That is the mode's intended purpose, so it
  is not a 2.5.4 problem for a nearby-messaging app.
- Limits: in the background "the local name is not advertised and all service UUIDs are placed
  in the overflow area", discoverable "only by an iOS device explicitly scanning for them". One
  developer reports two locked iPhones never finding each other. Already-connected peers keep
  their connection, which is the more promising case.
- Bandwidth is enough for texts, acks, presence, roll call and a "who is talking" alert. It is
  doubtful for live Opus voice (24 kbps plus overhead) to several listeners at once. Nothing in
  this research measured it.

**Playing what arrives while locked.** Waking for a Bluetooth event gives the app a few seconds
to run code. Starting audible playback from the background is what the `audio` background mode
is for, and that mode is what 2.5.4 rejected in 1.0 (App Review read it as keeping the app alive,
not playing audio the user asked for). A local notification ("Sam is talking on Ski trip", or a
text) needs no background mode at all.

## 2. What this means for the scope

| Scope item | With no signal, phone locked | With no signal, app open |
|---|---|---|
| Hold to talk, whisper | No (needs the app in front) | Yes |
| Texts, roll call, meet-up spot, battery | Probably, over BLE: to be measured | Yes |
| Catch up (store and forward) | Yes in principle: friends' phones deliver when the app next opens, or over BLE if measured to work | Yes |
| Ping (make a friend's phone chirp) | A notification with a sound, if BLE wakes the app (the sound is the notification's; it does not override silent mode without the Critical Alerts entitlement) | Yes |
| Live captions | Only for audio that was received, so no while locked | Yes |
| 7) Lock Screen / Dynamic Island talk button | No as asked. A Live Activity can show status and open the app | n/a |
| Find (Nearby Interaction) | No as far as I know: phone-to-phone NI sessions pause in the background (from memory, not checked against Apple's docs this session) | Yes, on iPhones with the UWB chip |

## 3. Options for Jackson (a decision, not mine to make)

1. **Foreground voice, background texts over BLE.** The app talks only while open. Texts, roll
   call, pings and "Sam is talking" alerts arrive while locked through Bluetooth background modes
   (if section 4 shows they work). No `audio` mode, no server. This answers 2.5.4 and keeps
   working with no signal. The Live Activity becomes "status plus open to talk". (Recommended.)
2. **Add a relay server and Apple's Push to Talk framework for when there is signal.** True
   Lock Screen PTT, but only with internet, plus a server to run and pay for. Off-grid it falls
   back to option 1. It cannot play each person's own chirp sound.
3. **Ship the `audio` background mode again** and argue it in review. It was rejected once for
   exactly this; not recommended.

## 4. The hardware test that would prove it (not yet run)

Needs two devices on the same build, Wi-Fi and cellular off on both, Bluetooth on: the shared
iPhone plus Chirp's simulator for the parts a simulator can do, ideally a second iPhone for the
locked-to-locked cases (a simulator cannot be locked like a phone, and has no real Bluetooth).

- **B1** 1.0 as shipped (`audio` mode): lock A, B talks. Does A play it, after 1, 5 and 30 minutes?
  (Expected yes: that is what got rejected.)
- **B2** Branch `fix/2-5-4-foreground-only` (no background mode): same. Expected: A stops hearing
  within seconds of locking and the MultipeerConnectivity peer drops.
- **B3** A 2.0 BLE prototype with `bluetooth-central` and `bluetooth-peripheral`: connect A and B
  in the foreground, lock both, B sends a text and a ping. Does A post a notification, and how
  late? Repeat after 5 and 30 minutes, and with A locked before the two ever connected.
- **B4** Same with both phones locked from the start (the overflow-area discovery case).
- **B5** On B3's build, the device log for how long A runs after each wake.

Record each as passed, failed or not runnable, with the time and the device log lines.

## Sources

- Apple, Creating a Push to Talk app:
  https://developer.apple.com/documentation/pushtotalk/creating-a-push-to-talk-app
- Apple DTS, iOS Background Execution Limits: https://developer.apple.com/forums/thread/685525
- Apple DTS on MultipeerConnectivity in the background and its deprecation:
  https://developer.apple.com/forums/thread/836124
- Apple, Core Bluetooth best practices for a peripheral (background advertising):
  https://developer.apple.com/library/content/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/BestPracticesForSettingUpYourIOSDeviceAsAPeripheral/BestPracticesForSettingUpYourIOSDeviceAsAPeripheral.html
- Two locked iPhones not discovering each other (developer report):
  https://developer.apple.com/forums/thread/8702
- Apple, App Review Guidelines 2.5.4: https://developer.apple.com/app-store/review/guidelines/#software-requirements
