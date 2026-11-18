#!/usr/bin/env python3
"""Writes chirpchirps.com's use-case pages: site/<slug>/index.html.

    python3 site-deploy/usecases.py        # rewrite the four pages

Edit the words here, run it, commit the pages with it. Every claim must be
something the 2.0 build does (deploy.sh checks the site against the same list
of missing features as scripts/check_store_copy.py). No em dashes.
"""
from html import escape
from pathlib import Path

SITE = Path(__file__).resolve().parent.parent / "site"
ANALYTICS = '<script defer src="/a/sgj.js" data-website-id="cfeb9746-8873-4c4f-807a-ad9fe8c8880e" data-host-url="/a"></script>'

# Screens from the app itself, as on the home page (img/<name>-light|dark.webp).
SHOT_ALT = {
    "talk": "The Talk screen: friends on a wire, one of them talking, her words as a caption, and a big button to hold.",
    "nearby": "The Nearby screen: who can hear you right now and how far away each friend is.",
    "find": "The Find screen: how far away a friend is, with an arrow on iPhones that can point one.",
    "rollcall": "The Roll call screen: everyone asked if they are OK, with who has answered.",
}

PAGES = [
    {
        "slug": "ski-trips",
        "title": "ChirpChirps for ski trips | Talk to your group on the mountain",
        "desc": "Hold to talk to your ski group on the lift, in the trees and at the lodge, with no signal. Texts with ticks, roll call and Find. Coming to iPhone.",
        "eyebrow": "Ski trips",
        "h1": "Talk to your group from the chairlift.",
        "lede": "Signal on a mountain comes and goes. ChirpChirps goes phone to phone, so your group can talk on the slopes without bars.",
        "moments": [
            ("Lift 4 is closed", "Hold the button and tell the whole group at once. Let go and they hear it. Gloves on? It is one big button."),
            ("Who made it down?", "Roll call asks everyone if they are OK with one tap. Anyone can answer \"I need help\"."),
            ("Lost in the trees", "Find shows how far away a friend is, and which way to walk on iPhones that support it. Ping makes their phone chirp."),
            ("Too windy to hear", "Turn on captions and read what your friends say. Or send a text: ticks show who has it."),
        ],
        "shots": ["talk", "rollcall"],
        "tips": [
            "Everyone needs ChirpChirps on their own iPhone. Start a birdhouse and send the invite link before you head up, while you still have signal.",
            "Range depends on the mountain: open slopes carry further than trees and ridges. Nearby shows who can hear you right now.",
            "Cold drains batteries. Keep your phone in an inside pocket between runs.",
        ],
    },
    {
        "slug": "festivals",
        "title": "ChirpChirps for festivals | Find your friends when the network is down",
        "desc": "Eighty thousand people and no bars. Hold to talk to your friends, text with ticks, find each other in the crowd. No account, no signal. Coming to iPhone.",
        "eyebrow": "Festivals",
        "h1": "Find your friends in the crowd, with no bars.",
        "lede": "When the whole field is on one cell tower, messages stop. ChirpChirps goes phone to phone, so your group can still talk and find each other.",
        "moments": [
            ("Meet at the main stage", "Hold to talk and the whole group hears you. Or type it: ticks show who has it."),
            ("Too loud to listen", "Captions show what your friends say as text, made on your phone. Captions only mode keeps it silent."),
            ("Where are you?", "Find shows how far away a friend is, and which way to walk on iPhones that support it. Ping makes their phone chirp."),
            ("Check in for a bit", "Share where you are with everyone in your birdhouse for 15 minutes. It is off until you ask, and it asks every time."),
        ],
        "shots": ["find", "nearby"],
        "tips": [
            "Start a birdhouse and send the invite link before the gates, while there is still signal.",
            "A crowd absorbs radio. You will reach friends further away in an open field than in the middle of the pit.",
            "Your birdhouse is locked with its own key. Only people with the invite link can hear it, and you can block anyone nearby.",
        ],
    },
    {
        "slug": "cruises",
        "title": "ChirpChirps for cruises | Talk on board with no roaming and no ship Wi-Fi",
        "desc": "Talk to your family on deck and across the ship with no roaming plan and no ship Wi-Fi. Hold to talk, texts with ticks, roll call. Coming to iPhone.",
        "eyebrow": "Cruises",
        "h1": "Talk on board, without paying for ship Wi-Fi.",
        "lede": "At sea there is no signal and the ship's Wi-Fi costs extra. ChirpChirps goes phone to phone, so your group can talk on board for free.",
        "moments": [
            ("Dinner in ten", "Hold to talk and everyone in your birdhouse who is close by hears you. Or send a text, with ticks when it arrives."),
            ("Kids on the pool deck", "Roll call asks everyone if they are OK with one tap, and anyone can answer \"I need help\"."),
            ("Phone in the cabin", "With your phone locked, texts, roll calls and pings still come in over Bluetooth and show as notifications."),
            ("Which deck?", "Find shows how far away someone is, and which way to walk on iPhones that support it."),
        ],
        "shots": ["talk", "find"],
        "tips": [
            "Set your phone to airplane mode to avoid roaming, then turn Wi-Fi and Bluetooth back on in Control Center. ChirpChirps never uses cellular.",
            "Steel decks and walls block radio. Expect it to reach along a deck more easily than between decks.",
            "Start a birdhouse and send the invite link before you board.",
        ],
    },
    {
        "slug": "camping",
        "title": "ChirpChirps for camping | Talk at the campsite with no tower",
        "desc": "From the trailhead to the tent, hold to talk to your group with no cell tower. Texts with ticks, roll call, ping and Find. Coming to iPhone.",
        "eyebrow": "Camping",
        "h1": "From the trailhead to the tent, no tower needed.",
        "lede": "Campsites are where the signal gives up. ChirpChirps goes phone to phone, so your group can talk around camp and on the trail.",
        "moments": [
            ("Back at camp by dark?", "Roll call asks everyone if they are OK with one tap. \"I need help\" is one tap too."),
            ("Grabbing firewood", "Hold to talk and the group hears you. Let go to listen. One person talks at a time, so nobody talks over anyone."),
            ("Where is the tent?", "Ping a friend and their phone chirps, so you can walk to the sound. Find shows how far away they are."),
            ("Phone in your pocket", "With your phone locked, texts and pings still come in over Bluetooth and show as notifications."),
        ],
        "shots": ["rollcall", "nearby"],
        "tips": [
            "Everyone needs ChirpChirps on their own iPhone. Start a birdhouse and send the invite link at home.",
            "Trees, hills and rock shorten the range. Nearby shows who can hear you right now.",
            "ChirpChirps is not a replacement for emergency services. Tell someone at home where you are going.",
        ],
    },
]

NAV = """<nav class="nav">
    <div class="nav-in">
        <a href="/" class="nav-brand"><span class="pip" aria-hidden="true"></span>ChirpChirps</a>
        <div class="nav-links">
            <a href="/#how">How it works</a>
            <a href="/support">Support</a>
            <a href="/privacy">Privacy</a>
        </div>
    </div>
</nav>"""

FOOT = """<footer class="foot">
    <div class="foot-in">
        <div class="foot-links">
{links}
            <a href="/privacy">Privacy</a>
            <a href="/support">Support</a>
            <a href="/terms">Terms</a>
            <a href="/credits">Credits</a>
        </div>
        <small>&copy; 2026 ChirpChirps</small>
    </div>
</footer>"""

SIGNUP = """    <div class="notify" id="notify">
        <p class="soon">Coming to iPhone</p>
        <form class="signup" method="post" action="/api/signup">
            <label class="sr" for="email">Your email address</label>
            <input id="email" name="email" type="email" required autocomplete="email" inputmode="email" maxlength="254" placeholder="you@example.com">
            <div class="trap" aria-hidden="true"><label for="company">Company</label><input id="company" name="company" type="text" tabindex="-1" autocomplete="off"></div>
            <button class="btn btn-primary" type="submit">Tell me when it is out</button>
        </form>
        <p class="signup-note" role="status">One email on release day. Then we delete the list, your address with it.</p>
    </div>"""


def foot_links() -> str:
    return "\n".join(f'            <a href="/{p["slug"]}/">{escape(p["eyebrow"])}</a>' for p in PAGES)


def shot(name: str) -> str:
    return f"""            <figure class="shot">
                <picture>
                    <source srcset="/img/{name}-dark.webp" media="(prefers-color-scheme: dark)">
                    <img src="/img/{name}-light.webp" width="600" height="1304" loading="lazy" decoding="async"
                         alt="{escape(SHOT_ALT[name])}">
                </picture>
            </figure>"""


def page(p: dict) -> str:
    url = f"https://chirpchirps.com/{p['slug']}/"
    moments = "\n".join(
        f'            <div class="cap"><h3>{escape(h)}</h3><p>{escape(t)}</p></div>' for h, t in p["moments"])
    tips = "\n".join(f"            <li>{escape(t)}</li>" for t in p["tips"])
    others = " ".join(f'<a href="/{o["slug"]}/">{escape(o["eyebrow"])}</a>' for o in PAGES if o is not p)
    return f"""<!DOCTYPE html>
<!-- Written by site-deploy/usecases.py: edit the words there, not here. -->
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{escape(p['title'])}</title>
    <meta name="description" content="{escape(p['desc'])}">
    <link rel="canonical" href="{url}">
    <meta property="og:type" content="website">
    <meta property="og:site_name" content="ChirpChirps">
    <meta property="og:url" content="{url}">
    <meta property="og:title" content="{escape(p['title'])}">
    <meta property="og:description" content="{escape(p['desc'])}">
    <meta property="og:image" content="https://chirpchirps.com/img/og.png">
    <meta name="twitter:card" content="summary_large_image">
    <meta name="theme-color" content="#EAF6FC" media="(prefers-color-scheme: light)">
    <meta name="theme-color" content="#0D182B" media="(prefers-color-scheme: dark)">
    <link rel="stylesheet" href="/fonts/fonts.css?v=6">
    <link rel="stylesheet" href="/brand.css?v=7">
    <link rel="icon" href="/favicon.ico" sizes="any">
    <link rel="icon" type="image/png" sizes="32x32" href="/favicon-32x32.png">
    <link rel="icon" type="image/png" sizes="16x16" href="/favicon-16x16.png">
    <link rel="apple-touch-icon" href="/apple-touch-icon.png">
    {ANALYTICS}
</head>
<body>

{NAV}

<main>
<section class="intro">
    <p class="eyebrow">{escape(p['eyebrow'])}</p>
    <h1>{escape(p['h1'])}</h1>
    <p class="lede">{escape(p['lede'])}</p>
    <p class="small-print">No account. No phone number.</p>
{SIGNUP}
</section>

<section class="section">
    <div class="wrap">
        <div class="section-head">
            <p class="eyebrow">How it helps</p>
            <h2>The moments it is for.</h2>
        </div>
        <div class="caps">
{moments}
        </div>
    </div>
</section>

<section class="section">
    <div class="wrap">
        <div class="section-head">
            <p class="eyebrow">A look inside</p>
            <h2>Screens from the app itself.</h2>
        </div>
        <div class="shots">
{chr(10).join(shot(s) for s in p['shots'])}
        </div>
    </div>
</section>

<section class="section">
    <div class="wrap">
        <div class="section-head">
            <p class="eyebrow">Good to know</p>
            <h2>Before you go.</h2>
        </div>
        <ul class="tips">
{tips}
        </ul>
        <p class="disclaimer">ChirpChirps is not a substitute for emergency services and should not be relied on for life-safety communication. How far it reaches depends on the place, where the phones are, and how many are nearby.</p>
        <p class="more">Also for: {others}</p>
    </div>
</section>

<section class="close">
    <div class="wrap">
        <h2>Bring your birdhouse.</h2>
        <p class="lede">No account, no servers, nothing collected. Your voice goes from phone to phone.</p>
        <a class="btn btn-sun" href="#notify">Tell me when it is out</a>
    </div>
</section>
</main>

{FOOT.format(links=foot_links())}

</body>
</html>
"""


def main() -> None:
    for p in PAGES:
        out = SITE / p["slug"] / "index.html"
        out.parent.mkdir(exist_ok=True)
        text = page(p)
        assert "—" not in text, f"em dash in {p['slug']}"
        out.write_text(text, encoding="utf-8")
        print(f"wrote {out.relative_to(SITE.parent)}")


if __name__ == "__main__":
    main()
