# Game rules

ScoreCall is a Premier League prediction game for a group of friends. These rules are the product owner's decisions; the code follows them.

## Seasons and gameweeks

- The game runs per **Premier League season** (e.g. 2026/27). Leaderboards start from zero each season.
- A season has 38 **gameweeks**. Each gameweek contains the matches the Premier League schedules for it.

## Match predictions

- Each gameweek, every player predicts the score of **every match** in it.
- You predict **once**. The same prediction counts in every league you're in.
- Predictions can be created and edited until the **gameweek deadline**: **1 hour before the gameweek's first kickoff**. After the deadline, the whole gameweek is locked.
- Before the deadline you see only your own predictions. After it, you can see everyone's, with their points once matches are played (**All predictions** tab, #11). This is enforced on the server: asking for another player's predictions before the deadline is refused, whatever the browser sends.

### Points per match

| Prediction                                              | Points |
| ------------------------------------------------------- | ------ |
| Correct outcome (home win / draw / away win)            | 3      |
| Exact score (includes the correct outcome: 3 + 5 bonus) | 8      |
| Wrong outcome                                           | 0      |
| No prediction                                           | 0      |

A correctly predicted draw counts as a correct outcome, e.g. predicting 1–1 when the match ends 2–2 gives 3 points.

Points are given automatically as soon as the sync sees the match as finished (within 30 minutes of full time). If a result is later corrected, points are recalculated. In the rare case a result is annulled, the prediction goes back to open until the match is finished again.

### Changing the points

The 3 and 5 are configuration, not code: the custom metadata record **Scoring Rule → Default** (`force-app/main/default/customMetadata/Scoring_Rule.Default.md-meta.xml`).

1. Change the values in that file on a branch and open a PR. **Never edit them directly in Setup**: the next deploy would overwrite the change, and git would no longer show the real rules.
2. After the PR is merged and deployed, recalculate the season in each org, so the whole season uses one set of rules (PO decision):
   ```bash
   sf apex run --file scripts/apex/rescore-season.apex --target-org scorecall-prod
   ```

### Postponed matches

- If a match is postponed, all predictions made for it in its original gameweek are **voided**: 0 points for everyone.
- When the match is rescheduled, it becomes part of the gameweek in which it is **actually played**. Everyone predicts it again there, and those predictions score normally.
- A postponed match doesn't count towards its original gameweek's deadline, as long as the deadline hasn't passed yet.
- **Once locked, always locked.** When a gameweek's deadline has passed, it stays locked, even if a match is postponed afterwards (e.g. 10 minutes before kickoff because of the weather) and the "first kickoff" moves later. Predictions are never re-opened after the deadline.
- A match abandoned during play counts as postponed: its predictions are voided.

## Season table prediction

- Before the season, each player predicts the **final league position of all 20 teams** (each position used exactly once).
- **Deadline:** 1 hour before the season's first kickoff.
  - **Exception for 2026/27:** the season was already running when ScoreCall launched, so the deadline for this season is set at launch. It's less fair, but it's the same for everyone.
- Points are awarded once the final table is known.

### Points per team

| Distance from actual final position | Points |
| ----------------------------------- | ------ |
| Exact                               | 20     |
| 1 place off                         | 15     |
| 2 places off                        | 10     |
| 3 places off                        | 5      |
| 4 or more places off                | 0      |

Maximum: 20 teams × 20 = 400 points. A typical season of match predictions is worth roughly 1,200–1,300 points, so the table prediction is about 10–15% of the total.

## Leagues

- A **league** is a group of players with its own leaderboard. There can be several leagues, and a player can be in more than one.
- Leagues continue across seasons, with a separate leaderboard per season.
- League standings = match prediction points + table prediction points for that season.
- A player who joins late **starts at 0**. Gameweeks before they joined count as no prediction, and a missed table-prediction deadline gives 0.

## Leaderboard tie-breaker

Confirmed by the PO on 2026-11-11 (#9):

1. More **points** ranks higher.
2. Equal points: more **exact scores** ranks higher.
3. Still equal: **shared place**. Two players in 2nd place are both 2nd, and the next player is 4th (1, 2, 2, 4).

## Leaderboard (version 1)

- One table for **all players** of the active season, on the **Leaderboard** tab (ScoreCall app) and the Leaderboard tab of the friends' site Home page. Per-league tables come later, when there is more than one group of friends.
- **Whole season** = match points + table prediction points. A **gameweek** view (any gameweek whose deadline has passed) shows only that gameweek's match points.
- A player appears once they have made at least one prediction in the season.
- Columns: rank, player, points, exact scores. Your own row is highlighted. Only totals are shown, never someone else's predictions (that is #11).

## Not in version 1

Jokers / double points, weekly prizes, comments or chat, bonus picks (champion, top 4, relegation).
