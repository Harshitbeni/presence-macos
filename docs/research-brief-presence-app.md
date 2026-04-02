# Research Brief: Mac Menu Bar Presence + Music App
**Prepared for:** Coding Agent  
**Prepared by:** Harshit Beniwal  
**Date:** April 2026  
**Purpose:** Pre-build research to validate technical feasibility and inform architecture decisions before a PRD is written.

---

## What We're Building

A Mac-only menu bar app that creates a shared ambient presence layer for small, trusted friend groups. Think of it as a lightweight "who's online and what are they listening to" layer that lives quietly in your menu bar — not a chat app, not a social network.

Users add friends, organize them into named groups (e.g. college friends, work partner, Twitter mutuals), and see at a glance who's online and what music they're playing. The defining interaction is "tuning in" — syncing your own music player to follow whatever a friend is currently listening to in real time.

---

## V Zero Scope (Research Focus)

This is the MVP. All research should prioritize what's needed to ship this.

**Core features:**
- Menu bar app (Mac only)
- Add friends, organize into named groups
- Online / offline status per friend
  - Offline state: grayscale avatar
  - Online state: colored avatar, music visible
  - User can set themselves offline via a dropdown: "Go offline for 15 min / 1 hour / until I turn back on"
- Music display: currently playing track (title, artist, album art)
- "Tune in" to a friend's music: your player starts playing whatever they're playing and follows their track changes in near real time (a few seconds of lag is acceptable)

**Out of scope for V Zero:**
- Nudging / calling
- Activity / active app display
- Location and timezone

---

## V One Scope (Context Only — Not a Blocker)

Include this so architecture decisions can scale into it without a full rewrite.

- **Nudge:** Tap a friend's card to send a nudge. If accepted, opens a choice: iMessage, FaceTime Audio, or FaceTime Video.
- **Activity:** Shows what app the friend is actively using (e.g. "In Figma", "In VS Code"). Pulled from the active foreground app on their Mac.
- **Location & Timezone:** Passive display of where a friend is and what local time it is for them.

---

## Research Areas

### 1. Music Platform Integration

**Goal:** Determine which music platform(s) can support both reading a user's currently playing track and triggering playback of a specific track on another user's device.

This is the core technical risk of the app. We need answers to:

#### Spotify
- Can we read the currently playing track (title, artist, album art) via the Web API? What's the polling strategy — is there a webhook or push mechanism, or must we poll? What are the rate limits?
- Can we trigger playback of a specific track on a user's active device via the API? Does this require Spotify Premium? (Note: based on initial research, `PUT /me/player/play` exists but requires Premium.)
- What changed in the February 2026 Web API update? Does it affect playback endpoints or Dev Mode apps?
- What's the auth flow for a Mac app — OAuth via browser redirect, or is there a native SDK?
- Any ToS restrictions around syncing playback state between users?

#### Apple Music
- Can we read the currently playing track on macOS? MusicKit's `MPMusicPlayerController` and `nowPlayingItem` appear viable — confirm this works reliably on macOS (not just iOS).
- Can AppleScript or the Music app's scripting dictionary be used as a simpler fallback to read now-playing state?
- Can we trigger playback of a specific track on a user's device using MusicKit or MediaPlayer? Does this require an Apple Music subscription?
- What's the auth flow for a Mac app using MusicKit?
- Any restrictions on using MusicKit to build a social/sync experience?

#### Reference apps (validation)
- How do established Mac music accessories (e.g. **Sleeve** by Replay Software) read now-playing metadata, control playback, and satisfy macOS permissions? Use their public docs to sanity-check our approach (AppleScript vs system Now Playing, streaming edge cases, optional Web API usage).

#### Cross-Platform Question
If we support both Spotify and Apple Music, the "tune in" feature gets complicated when two users are on different platforms. Research whether:
- We can look up a track by title + artist on the target user's platform and play the equivalent (fuzzy match via catalog lookup)
- Or whether tune-in should be platform-locked (you can only tune in if you're on the same platform as the friend)

**Recommendation expected:** Which platform(s) to support at launch, and why. If only one, which one gives the cleaner developer path on macOS.

---

### 2. Mac App Language & Framework

**Goal:** Confirm the best language and UI framework for a Mac-only menu bar app that prioritizes: native feel, snappy performance, lightweight memory footprint, and rich custom animations.

Research and compare:

#### Swift + SwiftUI
- Best fit for menu bar apps on macOS today?
- Animation capabilities — can we do custom, fluid, physics-based animations comparable to what you'd see in apps like Linear or Craft?
- Any limitations with menu bar / `NSStatusItem` integration in SwiftUI?

#### Swift + AppKit
- More control than SwiftUI, but more verbose. Is it still the right call for a heavily custom-animated UI?
- Can AppKit and SwiftUI be mixed (e.g. AppKit for menu bar plumbing, SwiftUI for the popover UI)?

#### Swift + AppKit/SwiftUI Hybrid
- Many production Mac apps use this pattern. Is it the recommended approach for a menu bar app with custom UI?

#### Non-Native (Electron, Tauri, Flutter)
- Evaluate briefly. Given the requirement for lightweight and snappy, are any of these viable, or should they be ruled out?

**Recommendation expected:** Which framework combination to use, and why. Given the constraints (Mac-only, lightweight, custom animations), native Swift is the likely winner — but confirm and justify.

---

### 3. Backend Architecture

**Goal:** Choose a backend stack that handles real-time presence and music state sync with minimal operational overhead and low cost. The founder is a designer — there should be no manual server management.

#### What the backend needs to do
- Store user accounts and friend relationships
- Broadcast presence state (online/offline) to friends in near real time
- Broadcast now-playing music state (track, artist, art URL) to friends following that user
- Handle "tune in" relay: when User A tunes in to User B, the backend must push track changes from B to A as they happen
- Auth (sign in with Apple or email)

#### What it does NOT need to do
- Long-term storage of music history
- Store message content
- Heavy compute

#### Platforms to evaluate

**Supabase**
- Real-time subscriptions via Postgres — fit for presence and music state?
- Free tier limits and cost at small scale (sub-100 users)
- Swift / macOS SDK availability
- How to model presence (ephemeral vs. persisted rows)

**Firebase (Firestore + Realtime Database)**
- Realtime Database may be better than Firestore for high-frequency state updates like music sync
- Free tier (Spark plan) — how far does it go?
- Swift SDK maturity on macOS
- Cost at small scale

**PocketBase**
- Lightweight, single binary, open source
- Real-time subscriptions support?
- Can it be hosted on a managed platform (Fly.io, Railway) with zero DevOps?
- Cost at small scale

**Convex**
- Newer, reactive, designed for real-time apps
- Swift / native client support?
- Free tier and pricing

#### Questions for the agent to answer
- For a presence + music sync use case with sub-100 users, which backend has the lowest cost and operational overhead?
- Is WebSockets or Server-Sent Events the right transport for real-time music state updates, and does the recommended backend handle this natively?
- How should "tune in" be modeled — does User A subscribe to User B's presence channel, or does the backend push diffs?
- How do we handle the case where User B goes offline mid-session while User A is tuned in?
- Should music state be persisted to a database row (overwritten on each track change) or kept in-memory / ephemeral?

**Recommendation expected:** Which backend to use, what the data model looks like at a high level, and estimated monthly cost at launch scale.

---

## Constraints & Priorities Summary

| Priority | Constraint |
|---|---|
| Must | Mac only — no cross-platform requirement |
| Must | No server management for the founder |
| Must | Low cost at launch (sub-100 users) |
| Must | Real-time feel — presence and music updates in seconds |
| Should | Support both Spotify and Apple Music if technically feasible |
| Should | Architecture should not need a full rewrite to support V One features |
| Nice to have | Free tier covers early usage entirely |

---

## Expected Output from Agent

A structured research doc that includes:

1. **Music platform verdict** — which platform(s) to support, what's possible, what's not, and any ToS / API gotchas
2. **Framework verdict** — language and UI framework recommendation with justification
3. **Backend verdict** — recommended stack, rough data model, estimated cost
4. **Open questions / risks** — anything that needs a prototype or further validation before building starts
5. **Suggested next step** — what to build or validate first

Do not write any code. This is a research and recommendation document only.
