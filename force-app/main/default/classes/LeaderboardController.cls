/**
 * Standings for the active season (#9): the whole season or one gameweek.
 *
 *   getLeaderboard(null)        season: match points + table prediction points
 *   getLeaderboard(gameweekId)  that gameweek's match points
 *
 * Players are everyone with at least one prediction in the season (a friend
 * who hasn't predicted yet appears after their first prediction, at 0 if
 * nothing is scored yet). Ranking: points, then exact scores; still equal =
 * shared place (1, 2, 2, 4). PO decisions on #9.
 *
 * without sharing, and WITH SYSTEM_MODE on every query that reads across
 * players: predictions are private to their owner, and a standings table needs
 * everyone's. (Since API 67, static SOQL respects the running user's sharing
 * even in a without sharing class; only WITH SYSTEM_MODE reads all records.) Only totals and names leave this class, never a
 * single prediction. Gameweeks offered in the picker are the ones whose
 * deadline has passed.
 */
public without sharing class LeaderboardController {
  public class LeaderboardView {
    @AuraEnabled
    public String seasonName;
    /** null = the whole season */
    @AuraEnabled
    public Id gameweekId;
    @AuraEnabled
    public List<GameweekOption> gameweeks = new List<GameweekOption>();
    @AuraEnabled
    public List<Row> rows = new List<Row>();
  }

  public class GameweekOption {
    @AuraEnabled
    public Id gameweekId;
    @AuraEnabled
    public String name;
  }

  public class Row {
    @AuraEnabled
    public Integer rank;
    @AuraEnabled
    public Id userId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Integer points = 0;
    @AuraEnabled
    public Integer exactScores = 0;
    @AuraEnabled
    public Boolean isCurrentUser = false;
  }

  @AuraEnabled(cacheable=true)
  public static LeaderboardView getLeaderboard(Id gameweekId) {
    LeaderboardView view = new LeaderboardView();
    view.gameweekId = gameweekId;

    List<Season__c> seasons = [
      SELECT Id, Name
      FROM Season__c
      WHERE Status__c = 'Active'
      ORDER BY Start_Date__c DESC NULLS LAST
      LIMIT 1
    ];
    if (seasons.isEmpty()) {
      return view;
    }
    Season__c season = seasons[0];
    view.seasonName = season.Name;

    for (Gameweek__c gameweek : [
      SELECT Id, Name
      FROM Gameweek__c
      WHERE Season__c = :season.Id AND Deadline__c <= :System.now()
      ORDER BY Number__c DESC
    ]) {
      GameweekOption option = new GameweekOption();
      option.gameweekId = gameweek.Id;
      option.name = gameweek.Name;
      view.gameweeks.add(option);
    }

    Map<Id, Row> rows = gameweekId == null
      ? seasonRows(season.Id)
      : gameweekRows(season.Id, gameweekId);
    for (User player : [
      SELECT Id, Name
      FROM User
      WHERE Id IN :rows.keySet()
      WITH SYSTEM_MODE
    ]) {
      rows.get(player.Id).name = player.Name;
    }
    view.rows = rank(rows.values());
    return view;
  }

  /** Match points of the season plus table prediction points. */
  private static Map<Id, Row> seasonRows(Id seasonId) {
    Map<Id, Row> rows = new Map<Id, Row>();
    addPredictionTotals(
      rows,
      [
        SELECT OwnerId player, SUM(Points__c) points
        FROM Prediction__c
        WHERE Gameweek__r.Season__c = :seasonId
        WITH SYSTEM_MODE
        GROUP BY OwnerId
      ],
      [
        SELECT OwnerId player, COUNT(Id) exactScores
        FROM Prediction__c
        WHERE Gameweek__r.Season__c = :seasonId AND Exact_Score__c = TRUE
        WITH SYSTEM_MODE
        GROUP BY OwnerId
      ]
    );
    for (AggregateResult result : [
      SELECT OwnerId player, SUM(Points__c) points
      FROM Table_Prediction__c
      WHERE Season__c = :seasonId
      WITH SYSTEM_MODE
      GROUP BY OwnerId
    ]) {
      Row row = rowFor(rows, (Id) result.get('player'));
      row.points += toInteger(result.get('points'));
    }
    return rows;
  }

  private static Map<Id, Row> gameweekRows(Id seasonId, Id gameweekId) {
    Map<Id, Row> rows = new Map<Id, Row>();
    addPredictionTotals(
      rows,
      [
        SELECT OwnerId player, SUM(Points__c) points
        FROM Prediction__c
        WHERE Gameweek__c = :gameweekId AND Gameweek__r.Season__c = :seasonId
        WITH SYSTEM_MODE
        GROUP BY OwnerId
      ],
      [
        SELECT OwnerId player, COUNT(Id) exactScores
        FROM Prediction__c
        WHERE
          Gameweek__c = :gameweekId
          AND Gameweek__r.Season__c = :seasonId
          AND Exact_Score__c = TRUE
        WITH SYSTEM_MODE
        GROUP BY OwnerId
      ]
    );
    return rows;
  }

  private static void addPredictionTotals(
    Map<Id, Row> rows,
    List<AggregateResult> points,
    List<AggregateResult> exactScores
  ) {
    for (AggregateResult result : points) {
      rowFor(rows, (Id) result.get('player')).points += toInteger(
        result.get('points')
      );
    }
    for (AggregateResult result : exactScores) {
      rowFor(rows, (Id) result.get('player')).exactScores += toInteger(
        result.get('exactScores')
      );
    }
  }

  private static Row rowFor(Map<Id, Row> rows, Id userId) {
    if (!rows.containsKey(userId)) {
      Row row = new Row();
      row.userId = userId;
      row.isCurrentUser = userId == UserInfo.getUserId();
      rows.put(userId, row);
    }
    return rows.get(userId);
  }

  /**
   * Sorts by points, then exact scores, then name (display order only), and
   * gives equal points + exact scores the same rank: 1, 2, 2, 4.
   */
  @TestVisible
  private static List<Row> rank(List<Row> unsorted) {
    List<RowComparable> sortable = new List<RowComparable>();
    for (Row row : unsorted) {
      sortable.add(new RowComparable(row));
    }
    sortable.sort();

    List<Row> ranked = new List<Row>();
    Row previous;
    for (Integer i = 0; i < sortable.size(); i++) {
      Row row = sortable[i].row;
      Boolean tied =
        previous != null &&
        row.points == previous.points &&
        row.exactScores == previous.exactScores;
      row.rank = tied ? previous.rank : i + 1;
      ranked.add(row);
      previous = row;
    }
    return ranked;
  }

  private class RowComparable implements Comparable {
    private final Row row;

    RowComparable(Row row) {
      this.row = row;
    }

    public Integer compareTo(Object other) {
      Row that = ((RowComparable) other).row;
      if (row.points != that.points) {
        return row.points > that.points ? -1 : 1;
      }
      if (row.exactScores != that.exactScores) {
        return row.exactScores > that.exactScores ? -1 : 1;
      }
      String mine = row.name == null ? '' : row.name;
      String theirs = that.name == null ? '' : that.name;
      return mine.compareTo(theirs);
    }
  }

  private static Integer toInteger(Object value) {
    return value == null ? 0 : ((Decimal) value).intValue();
  }
}
