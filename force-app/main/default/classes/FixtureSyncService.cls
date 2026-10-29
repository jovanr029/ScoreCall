/**
 * Syncs the current Premier League season from football-data.org into
 * Season, Team, Gameweek, Fixture and Season Team records.
 *
 * Order matters:
 *   1. Callouts first. Salesforce doesn't allow a callout after DML in the
 *      same transaction ("uncommitted work pending").
 *   2. Lock gameweeks whose deadline has passed, BEFORE applying fixture
 *      changes. A last-minute postponement in this run would otherwise move
 *      the deadline later before we look at it.
 *   3. Write the changes (only records that actually changed), then lock
 *      again for deadlines that passed meanwhile.
 * All DML is rolled back if anything fails, so a run is all or nothing.
 *
 * Runs as the admin (ScoreCall_Admin), see FixtureSyncJob.
 */
public with sharing class FixtureSyncService {
  /** Lets tests pin "now"; production always uses the real time. */
  @TestVisible
  private static Datetime nowOverride;

  private final FootballDataClient client;

  public FixtureSyncService() {
    this(new FootballDataClient());
  }

  @TestVisible
  private FixtureSyncService(FootballDataClient client) {
    this.client = client;
  }

  public class SyncResult {
    public Id seasonId;
    public Integer teamsChanged = 0;
    public Integer gameweeksCreated = 0;
    public Integer fixturesChanged = 0;
    public Integer seasonTeamsChanged = 0;
    public Integer gameweeksLocked = 0;

    public String summary() {
      return 'Fixtures changed: ' +
        fixturesChanged +
        ', teams changed: ' +
        teamsChanged +
        ', gameweeks created: ' +
        gameweeksCreated +
        ', gameweeks locked: ' +
        gameweeksLocked +
        ', table rows changed: ' +
        seasonTeamsChanged;
    }
  }

  /** Fetches the season from the API, then writes it. */
  public SyncResult run() {
    // 1. Callouts
    List<FootballDataClient.ApiMatch> matches = client.getMatches().matches;
    FootballDataClient.StandingsResponse standings = client.getStandings();
    return apply(matches, standings);
  }

  /**
   * Writes already-fetched API data. Separate from run() so tests can apply
   * several syncs in one test without callouts after DML.
   */
  @TestVisible
  private SyncResult apply(
    List<FootballDataClient.ApiMatch> matches,
    FootballDataClient.StandingsResponse standings
  ) {
    if (matches == null || matches.isEmpty()) {
      throw new FootballDataClient.FootballDataException(
        'football-data.org returned no matches'
      );
    }

    SyncResult result = new SyncResult();
    Savepoint savepoint = Database.setSavepoint();
    try {
      // 2. Lock before any change can move a deadline
      result.gameweeksLocked += lockPassedGameweeks();

      // 3. Write changes
      Season__c season = syncSeason(matches);
      result.seasonId = season.Id;
      Map<Integer, Team__c> teamsByApiId = syncTeams(matches, result);
      Map<Integer, Integer> gameweekByMatchId = GameweekAssigner.assign(
        matches
      );
      Map<Integer, Id> gameweekIdByNumber = syncGameweeks(
        season,
        new Set<Integer>(gameweekByMatchId.values()),
        result
      );
      syncFixtures(
        matches,
        teamsByApiId,
        gameweekByMatchId,
        gameweekIdByNumber,
        result
      );
      syncTable(season, standings.totalTable(), teamsByApiId, result);

      result.gameweeksLocked += lockPassedGameweeks();
    } catch (Exception e) {
      Database.rollback(savepoint);
      throw e;
    }
    return result;
  }

  // ---------- Season ----------

  private Season__c syncSeason(List<FootballDataClient.ApiMatch> matches) {
    FootballDataClient.ApiSeason apiSeason = matches[0].season;
    String externalId = String.valueOf(apiSeason.id);
    List<Season__c> existing = [
      SELECT Id, Status__c, Table_Prediction_Deadline__c
      FROM Season__c
      WHERE External_Id__c = :externalId
    ];

    Season__c season = new Season__c(
      External_Id__c = externalId,
      Start_Date__c = apiSeason.startDate,
      End_Date__c = apiSeason.endDate,
      Status__c = seasonStatus(apiSeason, matches)
    );
    if (existing.isEmpty()) {
      season.Name = seasonName(apiSeason);
    } else {
      season.Id = existing[0].Id;
    }

    // Only fill an empty deadline for a season that hasn't started: the PO
    // sets 2026/27's deadline (launch date) by hand and it must not be overwritten.
    Boolean hasDeadline =
      !existing.isEmpty() && existing[0].Table_Prediction_Deadline__c != null;
    if (!hasDeadline && season.Status__c == 'Upcoming') {
      season.Table_Prediction_Deadline__c = firstKickoff(matches).addHours(-1);
    }

    upsert season;
    return season;
  }

  private static String seasonName(FootballDataClient.ApiSeason apiSeason) {
    return apiSeason.startDate.year() +
      '/' +
      String.valueOf(apiSeason.endDate.year()).right(2);
  }

  private static String seasonStatus(
    FootballDataClient.ApiSeason apiSeason,
    List<FootballDataClient.ApiMatch> matches
  ) {
    if (now() < firstKickoff(matches)) {
      return 'Upcoming';
    }
    for (FootballDataClient.ApiMatch match : matches) {
      if (fixtureStatus(match.status) != 'Finished') {
        return 'Active';
      }
    }
    return 'Finished';
  }

  private static Datetime firstKickoff(
    List<FootballDataClient.ApiMatch> matches
  ) {
    Datetime first = null;
    for (FootballDataClient.ApiMatch match : matches) {
      if (first == null || match.utcDate < first) {
        first = match.utcDate;
      }
    }
    return first;
  }

  // ---------- Teams ----------

  private Map<Integer, Team__c> syncTeams(
    List<FootballDataClient.ApiMatch> matches,
    SyncResult result
  ) {
    Map<String, FootballDataClient.ApiTeam> apiTeams = new Map<String, FootballDataClient.ApiTeam>();
    for (FootballDataClient.ApiMatch match : matches) {
      apiTeams.put(String.valueOf(match.homeTeam.id), match.homeTeam);
      apiTeams.put(String.valueOf(match.awayTeam.id), match.awayTeam);
    }

    Map<String, Team__c> existing = new Map<String, Team__c>();
    for (Team__c team : [
      SELECT Id, External_Id__c, Name, Short_Name__c, Crest_URL__c
      FROM Team__c
      WHERE External_Id__c IN :apiTeams.keySet()
    ]) {
      existing.put(team.External_Id__c, team);
    }

    Map<Integer, Team__c> teamsByApiId = new Map<Integer, Team__c>();
    List<Team__c> changed = new List<Team__c>();
    for (String externalId : apiTeams.keySet()) {
      FootballDataClient.ApiTeam apiTeam = apiTeams.get(externalId);
      Team__c team = new Team__c(
        External_Id__c = externalId,
        Name = apiTeam.shortName,
        Short_Name__c = apiTeam.tla,
        Crest_URL__c = apiTeam.crest
      );
      Team__c current = existing.get(externalId);
      if (current != null) {
        team.Id = current.Id;
      }
      if (
        current == null ||
        current.Name != team.Name ||
        current.Short_Name__c != team.Short_Name__c ||
        current.Crest_URL__c != team.Crest_URL__c
      ) {
        changed.add(team);
      }
      teamsByApiId.put(apiTeam.id, team);
    }
    upsert changed;
    result.teamsChanged = changed.size();
    return teamsByApiId;
  }

  // ---------- Gameweeks ----------

  /** Creates missing gameweeks; existing ones never need changes (Number and Season are fixed). */
  private Map<Integer, Id> syncGameweeks(
    Season__c season,
    Set<Integer> numbers,
    SyncResult result
  ) {
    Map<Integer, Id> idByNumber = new Map<Integer, Id>();
    for (Gameweek__c gameweek : [
      SELECT Id, Number__c
      FROM Gameweek__c
      WHERE Season__c = :season.Id
    ]) {
      idByNumber.put(gameweek.Number__c.intValue(), gameweek.Id);
    }

    String seasonName = [SELECT Name FROM Season__c WHERE Id = :season.Id].Name;
    List<Gameweek__c> missing = new List<Gameweek__c>();
    for (Integer gameweekNumber : numbers) {
      if (!idByNumber.containsKey(gameweekNumber)) {
        missing.add(
          new Gameweek__c(
            Name = seasonName + ' GW ' + gameweekNumber,
            Season__c = season.Id,
            Number__c = gameweekNumber
          )
        );
      }
    }
    insert missing;
    for (Gameweek__c gameweek : missing) {
      idByNumber.put(gameweek.Number__c.intValue(), gameweek.Id);
    }
    result.gameweeksCreated = missing.size();
    return idByNumber;
  }

  // ---------- Fixtures ----------

  private void syncFixtures(
    List<FootballDataClient.ApiMatch> matches,
    Map<Integer, Team__c> teamsByApiId,
    Map<Integer, Integer> gameweekByMatchId,
    Map<Integer, Id> gameweekIdByNumber,
    SyncResult result
  ) {
    Set<String> externalIds = new Set<String>();
    for (FootballDataClient.ApiMatch match : matches) {
      externalIds.add(String.valueOf(match.id));
    }
    Map<String, Fixture__c> existing = new Map<String, Fixture__c>();
    for (Fixture__c fixture : [
      SELECT
        Id,
        External_Id__c,
        Name,
        Gameweek__c,
        Home_Team__c,
        Away_Team__c,
        Kickoff__c,
        Status__c,
        Home_Goals__c,
        Away_Goals__c
      FROM Fixture__c
      WHERE External_Id__c IN :externalIds
    ]) {
      existing.put(fixture.External_Id__c, fixture);
    }

    List<Fixture__c> changed = new List<Fixture__c>();
    for (FootballDataClient.ApiMatch match : matches) {
      Team__c home = teamsByApiId.get(match.homeTeam.id);
      Team__c away = teamsByApiId.get(match.awayTeam.id);
      Fixture__c fixture = new Fixture__c(
        External_Id__c = String.valueOf(match.id),
        Name = home.Short_Name__c + ' v ' + away.Short_Name__c,
        Gameweek__c = gameweekIdByNumber.get(gameweekByMatchId.get(match.id)),
        Home_Team__c = home.Id,
        Away_Team__c = away.Id,
        Kickoff__c = match.utcDate,
        Status__c = fixtureStatus(match.status),
        Home_Goals__c = match.score?.fullTime?.home,
        Away_Goals__c = match.score?.fullTime?.away
      );
      Fixture__c current = existing.get(fixture.External_Id__c);
      if (current != null) {
        fixture.Id = current.Id;
      }
      if (current == null || hasChanged(current, fixture)) {
        changed.add(fixture);
      }
    }
    upsert changed;
    result.fixturesChanged = changed.size();
  }

  private static Boolean hasChanged(Fixture__c current, Fixture__c latest) {
    for (
      SObjectField field : new List<SObjectField>{
        Fixture__c.Name,
        Fixture__c.Gameweek__c,
        Fixture__c.Home_Team__c,
        Fixture__c.Away_Team__c,
        Fixture__c.Kickoff__c,
        Fixture__c.Status__c,
        Fixture__c.Home_Goals__c,
        Fixture__c.Away_Goals__c
      }
    ) {
      if (current.get(field) != latest.get(field)) {
        return true;
      }
    }
    return false;
  }

  /** API status => Fixture__c.Status__c. See docs/decisions/002-fixture-source.md. */
  @TestVisible
  private static String fixtureStatus(String apiStatus) {
    switch on apiStatus {
      when 'IN_PLAY', 'PAUSED' {
        return 'Live';
      }
      when 'FINISHED', 'AWARDED' {
        return 'Finished';
      }
      when 'POSTPONED', 'SUSPENDED', 'CANCELLED' {
        return 'Postponed';
      }
      when else {
        return 'Scheduled'; // SCHEDULED, TIMED and anything new
      }
    }
  }

  // ---------- League table ----------

  private void syncTable(
    Season__c season,
    List<FootballDataClient.ApiTableRow> table,
    Map<Integer, Team__c> teamsByApiId,
    SyncResult result
  ) {
    Map<Id, Season_Team__c> existingByTeam = new Map<Id, Season_Team__c>();
    for (Season_Team__c row : [
      SELECT Id, Team__c, Position__c, Played__c, Points__c
      FROM Season_Team__c
      WHERE Season__c = :season.Id
    ]) {
      existingByTeam.put(row.Team__c, row);
    }

    List<Season_Team__c> toInsert = new List<Season_Team__c>();
    List<Season_Team__c> toUpdate = new List<Season_Team__c>();
    for (FootballDataClient.ApiTableRow apiRow : table) {
      Team__c team = teamsByApiId.get(apiRow.team.id);
      if (team == null) {
        continue; // a team without matches this season can't happen; be safe
      }
      Season_Team__c current = existingByTeam.get(team.Id);
      if (current == null) {
        toInsert.add(
          new Season_Team__c(
            Season__c = season.Id,
            Team__c = team.Id,
            Position__c = apiRow.position,
            Played__c = apiRow.playedGames,
            Points__c = apiRow.points
          )
        );
      } else if (
        current.Position__c != apiRow.position ||
        current.Played__c != apiRow.playedGames ||
        current.Points__c != apiRow.points
      ) {
        // Never send Season__c on update: it's a non-reparentable master-detail.
        toUpdate.add(
          new Season_Team__c(
            Id = current.Id,
            Position__c = apiRow.position,
            Played__c = apiRow.playedGames,
            Points__c = apiRow.points
          )
        );
      }
    }
    insert toInsert;
    update toUpdate;
    result.seasonTeamsChanged = toInsert.size() + toUpdate.size();
  }

  // ---------- Lock ----------

  /** Sets the sticky Locked__c on every gameweek whose deadline has passed. */
  private static Integer lockPassedGameweeks() {
    Datetime currentTime = now();
    List<Gameweek__c> toLock = new List<Gameweek__c>();
    for (Gameweek__c gameweek : [
      SELECT Id
      FROM Gameweek__c
      WHERE Locked__c = FALSE AND Deadline__c <= :currentTime
    ]) {
      toLock.add(new Gameweek__c(Id = gameweek.Id, Locked__c = true));
    }
    update toLock;
    return toLock.size();
  }

  private static Datetime now() {
    return nowOverride ?? System.now();
  }
}
