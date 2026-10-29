/**
 * Uses a synthetic season shaped like the real one: matchday N is played on
 * the weekend of week N (Sat 12:30, Sat 15:00, Sun 14:00 UTC), and rescheduled
 * matches mirror the real cases found in the spike (docs/decisions/002).
 */
@IsTest
private class GameweekAssignerTest {
  private static final Datetime SEASON_START = Datetime.newInstanceGmt(
    2026,
    8,
    22,
    0,
    0,
    0
  ); // a Saturday
  private static Integer nextId = 1;

  /** A regular weekend: 3 matches for every matchday from 1 to count. */
  private static List<FootballDataClient.ApiMatch> regularSeason(
    Integer count
  ) {
    List<FootballDataClient.ApiMatch> matches = new List<FootballDataClient.ApiMatch>();
    for (Integer matchday = 1; matchday <= count; matchday++) {
      Datetime saturday = SEASON_START.addDays((matchday - 1) * 7);
      matches.add(match(matchday, saturday.addHours(12).addMinutes(30)));
      matches.add(match(matchday, saturday.addHours(15)));
      matches.add(match(matchday, saturday.addDays(1).addHours(14)));
    }
    return matches;
  }

  private static FootballDataClient.ApiMatch match(
    Integer matchday,
    Datetime kickoff
  ) {
    FootballDataClient.ApiMatch match = new FootballDataClient.ApiMatch();
    match.id = nextId++;
    match.matchday = matchday;
    match.utcDate = kickoff;
    return match;
  }

  private static Datetime weekend(Integer matchday) {
    return SEASON_START.addDays((matchday - 1) * 7);
  }

  @IsTest
  static void regularMatchesStayInTheirMatchday() {
    List<FootballDataClient.ApiMatch> matches = regularSeason(5);

    Map<Integer, Integer> gameweeks = GameweekAssigner.assign(matches);

    for (FootballDataClient.ApiMatch match : matches) {
      Assert.areEqual(match.matchday, gameweeks.get(match.id));
    }
  }

  @IsTest
  static void deadlineIsOneHourBeforeFirstRegularKickoff() {
    Map<Integer, Long> deadlines = GameweekAssigner.deadlines(regularSeason(2));

    Datetime firstKickoffGw2 = weekend(2).addHours(12).addMinutes(30);
    Assert.areEqual(firstKickoffGw2.addHours(-1).getTime(), deadlines.get(2));
  }

  @IsTest
  static void postponedMatchPlayedWeeksLaterMovesToThatGameweek() {
    // Like Everton v Liverpool 2024/25: matchday 15, played during matchday 25.
    List<FootballDataClient.ApiMatch> matches = regularSeason(30);
    FootballDataClient.ApiMatch moved = match(
      15,
      weekend(25).addDays(4).addHours(19).addMinutes(30)
    ); // Wednesday
    matches.add(moved);

    Assert.areEqual(25, GameweekAssigner.assign(matches).get(moved.id));
  }

  @IsTest
  static void matchBroughtForwardMovesToEarlierGameweek() {
    // Like Aston Villa v Liverpool 2024/25: matchday 29, brought forward into matchday 26.
    List<FootballDataClient.ApiMatch> matches = regularSeason(30);
    FootballDataClient.ApiMatch moved = match(
      29,
      weekend(26).addDays(4).addHours(19)
    ); // Wednesday
    matches.add(moved);

    Assert.areEqual(26, GameweekAssigner.assign(matches).get(moved.id));
  }

  @IsTest
  static void mondayNightMatchStaysInItsGameweek() {
    List<FootballDataClient.ApiMatch> matches = regularSeason(5);
    FootballDataClient.ApiMatch monday = match(
      3,
      weekend(3).addDays(2).addHours(20)
    );
    matches.add(monday);

    Assert.areEqual(3, GameweekAssigner.assign(matches).get(monday.id));
  }

  @IsTest
  static void rescheduledMatchDoesNotChangeItsOriginalMatchdayDeadline() {
    List<FootballDataClient.ApiMatch> matches = regularSeason(30);
    Long before = GameweekAssigner.deadlines(matches).get(15);

    matches.add(match(15, weekend(25).addDays(4).addHours(19)));

    Assert.areEqual(
      before,
      GameweekAssigner.deadlines(matches).get(15),
      'The outlier is not a regular match'
    );
  }

  @IsTest
  static void matchBeforeFirstDeadlineGoesToEarliestGameweek() {
    List<FootballDataClient.ApiMatch> matches = regularSeason(3);
    FootballDataClient.ApiMatch early = match(2, SEASON_START.addDays(-3));
    matches.add(early);

    Assert.areEqual(1, GameweekAssigner.assign(matches).get(early.id));
  }
}
