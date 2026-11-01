# Prediction screen

Where players enter their score predictions. It is the **Predict** tab, the first tab in the ScoreCall app, and the same component will be placed on the Experience Cloud site for friends (#10). Rules: [game-rules.md](game-rules.md).

## What the player sees

- The **next open gameweek** by default: the earliest gameweek whose deadline hasn't passed. If every gameweek is past (end of the season), the last one.
- ◀ ▶ arrows to move to the previous and next gameweek.
- The **deadline** in the player's own time zone, and a live countdown.
- One row per match: kickoff, home team, two score fields, away team. Fields are pre-filled with the player's saved prediction.
- **Save predictions** sends only the rows changed since the last save. Both fields empty means "no prediction" and is skipped.
- After the deadline the gameweek is **read-only** (a lock message replaces the countdown). Once a match is played, the result and the points are shown: `+8` for an exact score, `+3` for the right outcome, `+0`, or `Void` for a postponed match.
- A **postponed** match can't be predicted (it will come back in a later gameweek).

## How it's built

```
Predict tab (ScoreCall_Predict)
  └─ Lightning App Page ScoreCall_Predict
       └─ LWC predictionEntry
            ├─ @wire getGameweek(gameweekId)          cacheable read; null = next open gameweek
            └─ saveGameweekPredictions(...)           imperative, on Save; then refreshApex
                 └─ PredictionController (with sharing, USER_MODE)
```

- **The deadline is enforced in Apex.** The component only disables the fields; `saveGameweekPredictions` rejects any save at or after the deadline, or once the gameweek is locked, whatever the browser sends.
- **Own predictions only:** the controller reads and writes the running user's predictions, with the user's sharing and field permissions (`WITH USER_MODE`).
- **Goals:** 0 to 20, checked in the browser and again in Apex.

## Access

| Needed                                                       | Where                                                |
| ------------------------------------------------------------ | ---------------------------------------------------- |
| Apex class `PredictionController`                            | `ScoreCall_Player`, `ScoreCall_Admin` (class access) |
| Predict tab                                                  | `ScoreCall_Player`, `ScoreCall_Admin` (tab settings) |
| Read fixtures, gameweeks, teams; create/edit own predictions | `ScoreCall_Player` (object and field permissions)    |

## Team crests

Crests are images from `https://crests.football-data.org` (`Team__c.Crest_URL__c`). Salesforce blocks images from other domains unless they are allowed by Content Security Policy, so the CSP Trusted Site **Football_Data_Crests** allows `img-src` for that domain (context: All). The Experience Cloud site has its own CSP settings; allowing the domain there is part of #10.

If a crest is missing, the row still shows the team name.
