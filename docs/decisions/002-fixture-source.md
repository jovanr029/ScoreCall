# 002: Fixture and result data source

- **Status:** Proposed (spike #5), waiting for PO approval
- **Date:** 2026-10-11

## Decision

Use the **football-data.org API v4, free plan**, as the source for teams, fixtures, results and the league table. Salesforce calls it through a **Named Credential** (`FootballData`); the API key is entered per org in Setup and never stored in git.

Fallback (not needed for now): the admin enters fixtures and results by hand.

## What was tested

Real calls with a free API key on 2026-10-11, from the terminal (key loaded from a gitignored `.env`):

| Call                                                     | Result                                                                             |
| -------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| `GET /v4/competitions/PL/matches`                        | 200 · 380 matches for 2026/27 (58 finished, 1 in play, 321 timed), 10 per matchday |
| `GET /v4/competitions/PL/standings`                      | 200 · one `TOTAL` table with 20 rows                                               |
| `GET /v4/competitions/PL/teams`                          | 200 · 20 teams                                                                     |
| `GET /v4/competitions/PL/matches?season=2025` and `2024` | 200 · used to find rescheduled matches (see below)                                 |

- **Free plan:** the Premier League is one of 12 free competitions ("free. Forever.").
- **Rate limit:** 10 requests per minute. The response header `x-requests-available-minute` shows what is left.
- **Live status works:** a match was `IN_PLAY` during the test. Third-party write-ups say free-plan scores can be delayed; that's fine, because we only score `FINISHED` matches.

## Key finding: rescheduled matches keep their original matchday

The API's `matchday` is the **original** Premier League matchday, even when the match is played weeks earlier or later. From past seasons:

| Season  | Match                      | API matchday | Actually played                                                |
| ------- | -------------------------- | ------------ | -------------------------------------------------------------- |
| 2024/25 | Everton v Liverpool        | 15           | 12 Feb 2025, during matchday 25 (+66 days, storm postponement) |
| 2024/25 | Aston Villa v Liverpool    | 29           | During matchday 26 (−24 days, brought forward)                 |
| 2024/25 | Newcastle v Crystal Palace | 29           | During matchday 32 (+32 days)                                  |
| 2025/26 | Wolves v Arsenal           | 31           | During matchday 27 (−31 days)                                  |
| 2025/26 | Man City v Crystal Palace  | 31           | During matchday 36 (+53 days)                                  |

So 2–3 matches per season move, **in both directions**. Once played, they show as `FINISHED` like any other match; the `POSTPONED` status is only visible while no new date is set.

**Consequence for the sync (#6):** assign each fixture to a gameweek **by its kickoff date**, never by the API matchday. Proposed rule (the same one Fantasy Premier League uses):

1. Build each gameweek's deadline from its "regular" fixtures: the matches played within a few days of the rest of their API matchday.
2. Every fixture belongs to the **latest gameweek whose deadline is before its kickoff**.
3. When a fixture's gameweek changes (postponed, or moved forward or back), predictions made for it in the old gameweek are **Voided** (0 points); players predict it again in the new gameweek. This is the PO rule from `docs/game-rules.md`, applied to both directions.

## Mapping to our data model

| API                                                        | Salesforce                                                                   |
| ---------------------------------------------------------- | ---------------------------------------------------------------------------- |
| `season.id` (e.g. 2502)                                    | `Season__c.External_Id__c`                                                   |
| `season.startDate` / `endDate`                             | `Season__c.Start_Date__c` / `End_Date__c`; name built as `2026/27`           |
| `team.id` / `shortName` / `tla` / `crest`                  | `Team__c.External_Id__c` / `Name` / `Short_Name__c` / `Crest_URL__c`         |
| `match.id`                                                 | `Fixture__c.External_Id__c`                                                  |
| `match.utcDate`                                            | `Fixture__c.Kickoff__c` (UTC)                                                |
| `match.score.fullTime.home` / `.away`                      | `Fixture__c.Home_Goals__c` / `Away_Goals__c`                                 |
| `match.matchday`                                           | Not stored as the gameweek (see above); only used to find "regular" fixtures |
| standings `TOTAL` row: `position`, `playedGames`, `points` | `Season_Team__c.Position__c`, `Played__c`, `Points__c`                       |

### Status mapping

| API status                            | `Fixture__c.Status__c` |
| ------------------------------------- | ---------------------- |
| `SCHEDULED`, `TIMED`                  | Scheduled              |
| `IN_PLAY`, `PAUSED`                   | Live                   |
| `FINISHED`, `AWARDED`                 | Finished               |
| `POSTPONED`, `SUSPENDED`, `CANCELLED` | Postponed              |

## Call budget

A full sync is 2 calls (matches + standings); teams only change once a season. Running hourly on match days is far below 10 calls per minute.

## Sample (trimmed) responses

Match:

```json
{
  "id": 560542,
  "utcDate": "2026-08-21T19:00:00Z",
  "status": "FINISHED",
  "matchday": 1,
  "lastUpdated": "2026-10-11T00:20:32Z",
  "homeTeam": { "id": 57, "shortName": "Arsenal", "tla": "ARS" },
  "awayTeam": { "tla": "COV" },
  "score": {
    "winner": "HOME_TEAM",
    "duration": "REGULAR",
    "fullTime": { "home": 3, "away": 0 },
    "halfTime": { "home": 2, "away": 0 }
  }
}
```

Team:

```json
{
  "id": 57,
  "name": "Arsenal FC",
  "shortName": "Arsenal",
  "tla": "ARS",
  "crest": "https://crests.football-data.org/57.png"
}
```

Standings row: `{ "position": 1, "team": { "tla": "MCI" }, "playedGames": 6, "points": 18 }`

## Open points

- **Terms of use:** the official terms page couldn't be found during the spike. Before go-live, the PO should confirm on football-data.org that a private, non-commercial app for friends is fine, and whether attribution is expected (if so, add "Data: football-data.org" to the site footer).
- **Named Credential:** to be proven from Salesforce in this spike (next step).
