/**
 * The season table prediction screen (#18).
 *
 *   getTablePrediction()         the player's own table (or a starting order:
 *                                the current league table) and, once the
 *                                deadline has passed, everyone's tables
 *   saveTablePrediction(...)     the 20 teams in the player's order; refused
 *                                at or after Season__c.Table_Prediction_Deadline__c
 *
 * Points shown before the season is Finished are "if the season ended today"
 * (current Season_Team__c positions); they are not stored and not in the
 * leaderboard. TableScoringService stores the real points at the end.
 *
 * with sharing and USER_MODE for the player's own records. Other players'
 * tables (only after the deadline) and deleting the player's own old rows
 * (players may not delete) go through the inner AcrossPlayers class.
 */
public with sharing class TablePredictionController {
  public class TableView {
    @AuraEnabled
    public Id seasonId;
    @AuraEnabled
    public String seasonName;
    @AuraEnabled
    public Datetime deadline;
    /** The player can still save (deadline set and not passed). */
    @AuraEnabled
    public Boolean isOpen = false;
    /** The season is Finished: points are final. */
    @AuraEnabled
    public Boolean isFinished = false;
    /** The player has saved a table for this season. */
    @AuraEnabled
    public Boolean hasSaved = false;
    @AuraEnabled
    public List<TableRow> myTable = new List<TableRow>();
    /** Everyone's tables; only filled once the deadline has passed. */
    @AuraEnabled
    public List<PlayerTable> players = new List<PlayerTable>();
  }

  public class TableRow {
    @AuraEnabled
    public Id teamId;
    @AuraEnabled
    public String teamName;
    @AuraEnabled
    public String shortName;
    @AuraEnabled
    public String crest;
    @AuraEnabled
    public Integer predictedPosition;
    @AuraEnabled
    public Integer currentPosition;
    /** Final points (season Finished) or "if it ended today". */
    @AuraEnabled
    public Integer points;
  }

  public class PlayerTable {
    @AuraEnabled
    public Id userId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Integer points = 0;
    @AuraEnabled
    public Boolean isCurrentUser = false;
    @AuraEnabled
    public List<TableRow> rows = new List<TableRow>();
  }

  @AuraEnabled(cacheable=true)
  public static TableView getTablePrediction() {
    TableView view = new TableView();
    Season__c season = currentSeason();
    if (season == null) {
      return view;
    }
    view.seasonId = season.Id;
    view.seasonName = season.Name;
    view.deadline = season.Table_Prediction_Deadline__c;
    view.isFinished = season.Status__c == 'Finished';
    view.isOpen = isOpen(season);

    Map<Id, Season_Team__c> seasonTeams = seasonTeams(season.Id);
    List<Table_Prediction__c> mine = [
      SELECT Team__c, Predicted_Position__c, Points__c
      FROM Table_Prediction__c
      WHERE Season__c = :season.Id AND OwnerId = :UserInfo.getUserId()
      WITH USER_MODE
      ORDER BY Predicted_Position__c
    ];
    view.hasSaved = !mine.isEmpty();
    view.myTable = mine.isEmpty()
      ? startingOrder(seasonTeams)
      : rows(mine, seasonTeams, view.isFinished);

    if (isPastDeadline(season)) {
      view.players = everyonesTables(season.Id, seasonTeams, view.isFinished);
    }
    return view;
  }

  @AuraEnabled
  public static TableView saveTablePrediction(Id seasonId, List<Id> teamIds) {
    Season__c season = currentSeason();
    if (season == null || season.Id != seasonId) {
      throw error('This season isn\'t open for table predictions.');
    }
    if (!isOpen(season)) {
      throw error(
        season.Table_Prediction_Deadline__c == null
          ? 'Table predictions aren\'t open yet.'
          : 'The table prediction deadline has passed.'
      );
    }

    Set<Id> seasonTeamIds = seasonTeams(season.Id).keySet();
    Set<Id> ordered = new Set<Id>(teamIds == null ? new List<Id>() : teamIds);
    if (
      teamIds == null ||
      teamIds.size() != seasonTeamIds.size() ||
      !ordered.equals(seasonTeamIds)
    ) {
      throw error(
        'Put all ' + seasonTeamIds.size() + ' teams in order, each once.'
      );
    }

    // Reordering swaps positions, and Position_Key__c (owner + season +
    // position) is unique, so updating rows in place would collide halfway.
    // Replace the player's 20 rows instead. Players can't delete records, so
    // the delete runs in system mode, limited to the player's own rows.
    new AcrossPlayers().deleteOwnTable(season.Id);
    List<Table_Prediction__c> table = new List<Table_Prediction__c>();
    for (Integer i = 0; i < teamIds.size(); i++) {
      table.add(
        new Table_Prediction__c(
          Season__c = season.Id,
          Team__c = teamIds[i],
          Predicted_Position__c = i + 1
        )
      );
    }
    Database.insert(table, AccessLevel.USER_MODE);
    return getTablePrediction();
  }

  /** The newest season that is running or about to start. */
  private static Season__c currentSeason() {
    List<Season__c> seasons = [
      SELECT Id, Name, Status__c, Table_Prediction_Deadline__c
      FROM Season__c
      WHERE Status__c IN ('Upcoming', 'Active')
      WITH USER_MODE
      ORDER BY Start_Date__c DESC NULLS LAST
      LIMIT 1
    ];
    return seasons.isEmpty() ? null : seasons[0];
  }

  private static Boolean isOpen(Season__c season) {
    return season.Status__c != 'Finished' &&
      season.Table_Prediction_Deadline__c != null &&
      System.now() < season.Table_Prediction_Deadline__c;
  }

  private static Boolean isPastDeadline(Season__c season) {
    return season.Table_Prediction_Deadline__c != null &&
      System.now() >= season.Table_Prediction_Deadline__c;
  }

  /** teamId -> Season_Team__c, in current league table order. */
  private static Map<Id, Season_Team__c> seasonTeams(Id seasonId) {
    Map<Id, Season_Team__c> byTeam = new Map<Id, Season_Team__c>();
    for (Season_Team__c seasonTeam : [
      SELECT
        Team__c,
        Position__c,
        Team__r.Name,
        Team__r.Short_Name__c,
        Team__r.Crest_URL__c
      FROM Season_Team__c
      WHERE Season__c = :seasonId
      WITH USER_MODE
      ORDER BY Position__c NULLS LAST, Team__r.Name
    ]) {
      byTeam.put(seasonTeam.Team__c, seasonTeam);
    }
    return byTeam;
  }

  /** Before a player saves: the current league table (PO decision #18). */
  private static List<TableRow> startingOrder(
    Map<Id, Season_Team__c> seasonTeams
  ) {
    List<TableRow> rows = new List<TableRow>();
    for (Season_Team__c seasonTeam : seasonTeams.values()) {
      TableRow row = row(seasonTeam);
      row.predictedPosition = rows.size() + 1;
      rows.add(row);
    }
    return rows;
  }

  private static List<TableRow> rows(
    List<Table_Prediction__c> predictions,
    Map<Id, Season_Team__c> seasonTeams,
    Boolean finished
  ) {
    List<TableRow> rows = new List<TableRow>();
    for (Table_Prediction__c prediction : predictions) {
      Season_Team__c seasonTeam = seasonTeams.get(prediction.Team__c);
      if (seasonTeam == null) {
        continue;
      }
      TableRow row = row(seasonTeam);
      row.predictedPosition = prediction.Predicted_Position__c.intValue();
      row.points = finished
        ? toInteger(prediction.Points__c)
        : ScoringService.tablePoints(
            row.predictedPosition,
            row.currentPosition
          );
      rows.add(row);
    }
    return rows;
  }

  private static TableRow row(Season_Team__c seasonTeam) {
    TableRow row = new TableRow();
    row.teamId = seasonTeam.Team__c;
    row.teamName = seasonTeam.Team__r.Name;
    row.shortName = seasonTeam.Team__r.Short_Name__c;
    row.crest = seasonTeam.Team__r.Crest_URL__c;
    row.currentPosition = seasonTeam.Position__c == null
      ? null
      : seasonTeam.Position__c.intValue();
    return row;
  }

  /** After the deadline: every player's table, most points first. */
  private static List<PlayerTable> everyonesTables(
    Id seasonId,
    Map<Id, Season_Team__c> seasonTeams,
    Boolean finished
  ) {
    Map<Id, List<Table_Prediction__c>> byPlayer = new Map<Id, List<Table_Prediction__c>>();
    for (
      Table_Prediction__c prediction : new AcrossPlayers().tables(seasonId)
    ) {
      if (!byPlayer.containsKey(prediction.OwnerId)) {
        byPlayer.put(prediction.OwnerId, new List<Table_Prediction__c>());
      }
      byPlayer.get(prediction.OwnerId).add(prediction);
    }
    Map<Id, String> names = new AcrossPlayers().names(byPlayer.keySet());

    List<PlayerTable> players = new List<PlayerTable>();
    for (Id userId : byPlayer.keySet()) {
      PlayerTable player = new PlayerTable();
      player.userId = userId;
      player.name = names.get(userId);
      player.isCurrentUser = userId == UserInfo.getUserId();
      player.rows = rows(byPlayer.get(userId), seasonTeams, finished);
      for (TableRow row : player.rows) {
        player.points += row.points == null ? 0 : row.points;
      }
      players.add(player);
    }
    players.sort(new MostPointsFirst());
    return players;
  }

  /**
   * The only parts that reach other players' records. WITH SYSTEM_MODE skips
   * object and field permissions, but record sharing still follows the class
   * keyword, and the outer class is with sharing. So these run without
   * sharing: everyone's tables (only called after the deadline), their names,
   * and deleting the player's own old rows (players may not delete).
   */
  private without sharing class AcrossPlayers {
    List<Table_Prediction__c> tables(Id seasonId) {
      return [
        SELECT OwnerId, Team__c, Predicted_Position__c, Points__c
        FROM Table_Prediction__c
        WHERE Season__c = :seasonId
        WITH SYSTEM_MODE
        ORDER BY Predicted_Position__c
      ];
    }

    Map<Id, String> names(Set<Id> userIds) {
      Map<Id, String> names = new Map<Id, String>();
      for (User user : [
        SELECT Id, Name
        FROM User
        WHERE Id IN :userIds
        WITH SYSTEM_MODE
      ]) {
        names.put(user.Id, user.Name);
      }
      return names;
    }

    void deleteOwnTable(Id seasonId) {
      Database.delete(
        [
          SELECT Id
          FROM Table_Prediction__c
          WHERE Season__c = :seasonId AND OwnerId = :UserInfo.getUserId()
          WITH SYSTEM_MODE
        ],
        AccessLevel.SYSTEM_MODE
      );
    }
  }

  private class MostPointsFirst implements Comparator<PlayerTable> {
    public Integer compare(PlayerTable a, PlayerTable b) {
      if (a.points != b.points) {
        return a.points > b.points ? -1 : 1;
      }
      return (a.name == null ? '' : a.name)
        .compareTo(b.name == null ? '' : b.name);
    }
  }

  private static Integer toInteger(Decimal value) {
    return value == null ? null : value.intValue();
  }

  private static AuraHandledException error(String message) {
    AuraHandledException e = new AuraHandledException(message);
    e.setMessage(message);
    return e;
  }
}
