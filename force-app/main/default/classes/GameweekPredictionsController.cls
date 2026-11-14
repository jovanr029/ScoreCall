/**
 * Everyone's predictions for one gameweek, once its deadline has passed (#11).
 *
 *   getGameweekPredictions(null)        the latest gameweek past its deadline
 *   getGameweekPredictions(gameweekId)  that gameweek; refused before its
 *                                       deadline, whatever the browser asks
 *
 * Before the deadline every player sees only their own predictions (game
 * rules); the deadline check here is what enforces it, not the UI.
 *
 * without sharing + WITH SYSTEM_MODE: predictions are private to their
 * owner, so reading other players' needs system mode (since API 67 even a
 * without sharing class only sees the running user's own records without it).
 */
public without sharing class GameweekPredictionsController {
  public class GameweekPredictionsView {
    @AuraEnabled
    public Id gameweekId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Id previousGameweekId;
    @AuraEnabled
    public Id nextGameweekId;
    @AuraEnabled
    public List<PlayerTotal> players = new List<PlayerTotal>();
    @AuraEnabled
    public List<MatchView> matches = new List<MatchView>();
  }

  public class PlayerTotal {
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

  public class MatchView {
    @AuraEnabled
    public Id fixtureId;
    @AuraEnabled
    public String homeTeam;
    @AuraEnabled
    public String awayTeam;
    @AuraEnabled
    public Datetime kickoff;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Integer homeGoals;
    @AuraEnabled
    public Integer awayGoals;
    @AuraEnabled
    public List<PlayerPrediction> predictions = new List<PlayerPrediction>();
  }

  public class PlayerPrediction {
    @AuraEnabled
    public Id userId;
    @AuraEnabled
    public String name;
    /** null = no prediction for this match */
    @AuraEnabled
    public Integer homeGoals;
    @AuraEnabled
    public Integer awayGoals;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Integer points;
    @AuraEnabled
    public Boolean exactScore = false;
    @AuraEnabled
    public Boolean isCurrentUser = false;
  }

  @AuraEnabled(cacheable=true)
  public static GameweekPredictionsView getGameweekPredictions(Id gameweekId) {
    GameweekPredictionsView view = new GameweekPredictionsView();
    List<Gameweek__c> visible = visibleGameweeks();
    if (visible.isEmpty()) {
      if (gameweekId != null) {
        throw notYet();
      }
      return view;
    }

    Integer index = 0;
    if (gameweekId != null) {
      index = -1;
      for (Integer i = 0; i < visible.size(); i++) {
        if (visible[i].Id == gameweekId) {
          index = i;
        }
      }
      if (index == -1) {
        throw notYet();
      }
    }
    Gameweek__c gameweek = visible[index];
    view.gameweekId = gameweek.Id;
    view.name = gameweek.Name;
    // visible is newest first: "previous" is older, "next" is newer
    view.previousGameweekId = index + 1 < visible.size()
      ? visible[index + 1].Id
      : null;
    view.nextGameweekId = index > 0 ? visible[index - 1].Id : null;

    List<Prediction__c> predictions = [
      SELECT
        OwnerId,
        Fixture__c,
        Home_Goals__c,
        Away_Goals__c,
        Status__c,
        Points__c,
        Exact_Score__c
      FROM Prediction__c
      WHERE Gameweek__c = :gameweek.Id
      WITH SYSTEM_MODE
    ];

    Map<Id, PlayerTotal> players = new Map<Id, PlayerTotal>();
    Map<String, Prediction__c> byFixtureAndPlayer = new Map<String, Prediction__c>();
    for (Prediction__c prediction : predictions) {
      PlayerTotal player = players.get(prediction.OwnerId);
      if (player == null) {
        player = new PlayerTotal();
        player.userId = prediction.OwnerId;
        player.isCurrentUser = prediction.OwnerId == UserInfo.getUserId();
        players.put(prediction.OwnerId, player);
      }
      if (prediction.Status__c == 'Scored') {
        player.points += toInteger(prediction.Points__c);
        player.exactScores += prediction.Exact_Score__c ? 1 : 0;
      }
      byFixtureAndPlayer.put(
        prediction.Fixture__c + '-' + prediction.OwnerId,
        prediction
      );
    }
    for (User user : [
      SELECT Id, Name
      FROM User
      WHERE Id IN :players.keySet()
      WITH SYSTEM_MODE
    ]) {
      players.get(user.Id).name = user.Name;
    }
    view.players = sortedPlayers(players.values());

    for (Fixture__c fixture : [
      SELECT
        Id,
        Kickoff__c,
        Status__c,
        Home_Goals__c,
        Away_Goals__c,
        Home_Team__r.Name,
        Away_Team__r.Name
      FROM Fixture__c
      WHERE Gameweek__c = :gameweek.Id
      WITH SYSTEM_MODE
      ORDER BY Kickoff__c, Home_Team__r.Name
    ]) {
      MatchView match = new MatchView();
      match.fixtureId = fixture.Id;
      match.homeTeam = fixture.Home_Team__r.Name;
      match.awayTeam = fixture.Away_Team__r.Name;
      match.kickoff = fixture.Kickoff__c;
      match.status = fixture.Status__c;
      match.homeGoals = toNullableInteger(fixture.Home_Goals__c);
      match.awayGoals = toNullableInteger(fixture.Away_Goals__c);
      for (PlayerTotal player : view.players) {
        match.predictions.add(
          playerPrediction(
            player,
            byFixtureAndPlayer.get(fixture.Id + '-' + player.userId)
          )
        );
      }
      view.matches.add(match);
    }
    return view;
  }

  /** Gameweeks of the active season whose deadline has passed, newest first. */
  private static List<Gameweek__c> visibleGameweeks() {
    List<Gameweek__c> visible = new List<Gameweek__c>();
    for (Gameweek__c gameweek : [
      SELECT Id, Name, Locked__c, Deadline__c
      FROM Gameweek__c
      WHERE Season__r.Status__c = 'Active'
      WITH SYSTEM_MODE
      ORDER BY Number__c DESC
    ]) {
      if (
        gameweek.Locked__c ||
        (gameweek.Deadline__c != null &&
        gameweek.Deadline__c <= System.now())
      ) {
        visible.add(gameweek);
      }
    }
    return visible;
  }

  private static PlayerPrediction playerPrediction(
    PlayerTotal player,
    Prediction__c prediction
  ) {
    PlayerPrediction result = new PlayerPrediction();
    result.userId = player.userId;
    result.name = player.name;
    result.isCurrentUser = player.isCurrentUser;
    if (prediction != null) {
      result.homeGoals = toNullableInteger(prediction.Home_Goals__c);
      result.awayGoals = toNullableInteger(prediction.Away_Goals__c);
      result.status = prediction.Status__c;
      result.points = toNullableInteger(prediction.Points__c);
      result.exactScore = prediction.Exact_Score__c;
    }
    return result;
  }

  /** Most points first; equal points: more exact scores, then by name. */
  private static List<PlayerTotal> sortedPlayers(List<PlayerTotal> players) {
    List<PlayerComparable> sortable = new List<PlayerComparable>();
    for (PlayerTotal player : players) {
      sortable.add(new PlayerComparable(player));
    }
    sortable.sort();
    List<PlayerTotal> sorted = new List<PlayerTotal>();
    for (PlayerComparable item : sortable) {
      sorted.add(item.player);
    }
    return sorted;
  }

  private class PlayerComparable implements Comparable {
    private final PlayerTotal player;

    PlayerComparable(PlayerTotal player) {
      this.player = player;
    }

    public Integer compareTo(Object other) {
      PlayerTotal that = ((PlayerComparable) other).player;
      if (player.points != that.points) {
        return player.points > that.points ? -1 : 1;
      }
      if (player.exactScores != that.exactScores) {
        return player.exactScores > that.exactScores ? -1 : 1;
      }
      return (player.name == null ? '' : player.name)
        .compareTo(that.name == null ? '' : that.name);
    }
  }

  private static AuraHandledException notYet() {
    String message = 'Other players\' predictions are visible after the gameweek deadline.';
    AuraHandledException e = new AuraHandledException(message);
    e.setMessage(message);
    return e;
  }

  private static Integer toInteger(Decimal value) {
    return value == null ? 0 : value.intValue();
  }

  private static Integer toNullableInteger(Decimal value) {
    return value == null ? null : value.intValue();
  }
}
