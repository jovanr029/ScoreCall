# 001: Licence for friends on the site

- **Status:** Accepted by the PO on 2026-11-01 (spike #2, decided together with #10)
- **Amended:** 2026-11-02 (#28): sign-up with an invite code instead of invite only
- **Date:** 2026-11-01

## Decision

Friends log in to the Experience Cloud site with the **Customer Community** licence (member-based). Friends **sign up themselves with an invite code** that the PO shares (amended 2026-11-02, see below). Originally it was invite only: the PO added each friend.

## Licences available

Both UAT and production have the same free Developer Edition allocation (queried from `UserLicense` on 2026-11-01). The relevant ones:

| Licence                        | Seats | Logins                          | Verdict                                                                     |
| ------------------------------ | ----- | ------------------------------- | --------------------------------------------------------------------------- |
| **Customer Community**         | 5     | Unlimited (member-based)        | ✅ Chosen                                                                   |
| Customer Community Plus        | 5     | Unlimited                       | Adds roles, sharing rules and reports, which the game doesn't need          |
| Customer Portal Manager Custom | 10    | Unlimited                       | Older portal licence, works on sites. Fallback if we need more than 5 seats |
| External Apps Login            | 40    | **2 daily unique logins** (org) | ❌ A third friend logging in on the same day would be blocked               |

The spike's original assumption (only External Apps Login and Customer Portal Manager Custom) was wrong: the orgs also have the Customer Community family.

## Why Customer Community

- **Enough seats:** the PO plays as an internal user; at least 4 friends fit into 5 seats. If the group grows past 5, the extra friends get Customer Community Plus (5 more) or Customer Portal Manager Custom (10 more). Each user can have a different licence; the site and permission set work for all of them.
- **No login limit:** member-based, so friends can log in as often as they like during a gameweek.
- **Our sharing model fits it:** predictions are Private and owned by the player; Season, Team and League are Read for external users, and Gameweek and Fixture follow their season. Customer Community users have no roles, so they can't be given extra access through sharing rules, and we don't need any. Friends' predictions after the deadline (#11) and leaderboards (#9) come from Apex, not from sharing.

## What it means for the build

- A custom profile **ScoreCall Friend** carries the licence. New orgs don't allow standard external profiles ("Customer Community User") for user creation, and a custom one is safer anyway. All access comes from the **ScoreCall_Player** permission set.
- ScoreCall_Player can't contain app or tab settings: the Customer Community licence doesn't allow assigned apps. Those moved to **ScoreCall_Player_App** for internal players.
- Every site user is a Contact on the **ScoreCall Players** account. That account's owner must have a role, so the PO has the **ScoreCall Admin** role.
- Tested by `ScoreCallSiteAccessTest`: two Customer Community users load the gameweek, save their own predictions, and can't see each other's.

How to add a friend: [onboarding.md](../onboarding.md).

## Amendment 2026-11-02: sign-up with an invite code (#28)

Onboarding the first test friend in UAT showed that "invite only" depends on email: the friend could only log in after clicking the "set your password" link, and that email never reached Gmail. The PO decided friends sign up themselves:

- The site's Register page asks for name, email, **their own password** and an **invite code**. No email is needed to get in.
- The code lives in the **ScoreCall Settings** custom setting, per org, never in git. Empty = sign-up closed. The PO can change it at any time.
- The seat limit still applies: sign-up is refused with a clear message when the 5 Customer Community seats are used.
- `add-friend.apex` stays as a fallback.

Details: [onboarding.md](../onboarding.md#how-a-friend-signs-up).
