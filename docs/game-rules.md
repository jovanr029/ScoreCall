# Game rules

ScoreCall is a Premier League prediction game for a group of friends. These rules are the product owner's decisions; the code follows them.

## Seasons and gameweeks

- The game runs per **Premier League season** (e.g. 2026/27). Leaderboards start from zero each season.
- A season has 38 **gameweeks**. Each gameweek contains the matches the Premier League schedules for it.

## Match predictions

- Each gameweek, every player predicts the score of **every match** in it.
- You predict **once**. The same prediction counts in every league you're in.
- Predictions can be created and edited until the **gameweek deadline**: **1 hour before the gameweek's first kickoff**. After the deadline, the whole gameweek is locked.
- Before the deadline you see only your own predictions. After it, you can see everyone's.

### Points per match

| Prediction                                              | Points |
| ------------------------------------------------------- | ------ |
| Correct outcome (home win / draw / away win)            | 3      |
| Exact score (includes the correct outcome: 3 + 5 bonus) | 8      |
| Wrong outcome                                           | 0      |
| No prediction                                           | 0      |

A correctly predicted draw counts as a correct outcome, e.g. predicting 1–1 when the match ends 2–2 gives 3 points.

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

_To be confirmed by PO._ Proposal: more exact scores first, then alphabetical.

## Not in version 1

Jokers / double points, weekly prizes, comments or chat, bonus picks (champion, top 4, relegation).
