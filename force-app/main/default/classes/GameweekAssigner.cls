/**
 * Decides which gameweek each match belongs to. See
 * docs/decisions/002-fixture-source.md.
 *
 * The API's matchday is the ORIGINAL Premier League matchday: a rescheduled
 * match keeps it, even when it's played weeks earlier or later. So:
 *
 *   1. For each matchday, its "regular" matches are those within a few days of
 *      the matchday's median kickoff (rescheduled ones are far away).
 *   2. A matchday's deadline = its earliest regular kickoff - 1 hour.
 *   3. Every match belongs to the latest gameweek whose deadline is before
 *      its kickoff (the Fantasy Premier League rule).
 *
 * Pure logic: no SOQL, no DML, no callouts.
 */
public with sharing class GameweekAssigner {
  @TestVisible
  private static final Long REGULAR_WINDOW_MS = 4L * 24 * 60 * 60 * 1000; // 4 days
  private static final Long ONE_HOUR_MS = 60L * 60 * 1000;

  /** Returns API match id => gameweek number. */
  public static Map<Integer, Integer> assign(
    List<FootballDataClient.ApiMatch> matches
  ) {
    Map<Integer, Long> deadlineByMatchday = deadlines(matches);

    Map<Integer, Integer> gameweekByMatchId = new Map<Integer, Integer>();
    for (FootballDataClient.ApiMatch match : matches) {
      gameweekByMatchId.put(
        match.id,
        gameweekFor(match.utcDate.getTime(), deadlineByMatchday)
      );
    }
    return gameweekByMatchId;
  }

  /** Matchday => deadline (epoch ms), built from each matchday's regular matches. */
  @TestVisible
  private static Map<Integer, Long> deadlines(
    List<FootballDataClient.ApiMatch> matches
  ) {
    Map<Integer, List<Long>> kickoffsByMatchday = new Map<Integer, List<Long>>();
    for (FootballDataClient.ApiMatch match : matches) {
      if (!kickoffsByMatchday.containsKey(match.matchday)) {
        kickoffsByMatchday.put(match.matchday, new List<Long>());
      }
      kickoffsByMatchday.get(match.matchday).add(match.utcDate.getTime());
    }

    Map<Integer, Long> deadlineByMatchday = new Map<Integer, Long>();
    for (Integer matchday : kickoffsByMatchday.keySet()) {
      List<Long> kickoffs = kickoffsByMatchday.get(matchday);
      kickoffs.sort();
      Long median = kickoffs[kickoffs.size() / 2];

      Long firstRegular = null;
      for (Long kickoff : kickoffs) {
        if (Math.abs(kickoff - median) <= REGULAR_WINDOW_MS) {
          firstRegular = kickoff;
          break; // sorted, so the first regular one is the earliest
        }
      }
      deadlineByMatchday.put(matchday, firstRegular - ONE_HOUR_MS);
    }
    return deadlineByMatchday;
  }

  /** The matchday with the latest deadline before the kickoff; the earliest matchday if none. */
  private static Integer gameweekFor(
    Long kickoff,
    Map<Integer, Long> deadlineByMatchday
  ) {
    Integer best = null;
    Integer earliest = null;
    for (Integer matchday : deadlineByMatchday.keySet()) {
      Long deadline = deadlineByMatchday.get(matchday);
      if (earliest == null || deadline < deadlineByMatchday.get(earliest)) {
        earliest = matchday;
      }
      if (
        deadline <= kickoff &&
        (best == null ||
        deadline > deadlineByMatchday.get(best))
      ) {
        best = matchday;
      }
    }
    return best != null ? best : earliest;
  }
}
