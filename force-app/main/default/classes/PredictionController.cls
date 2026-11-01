/**
 * Backend for the predictionEntry LWC: one gameweek's fixtures with the
 * current user's predictions, and saving them.
 *
 * Security: with sharing, every query WITH USER_MODE and every DML in
 * AccessLevel.USER_MODE, so a player only reads what ScoreCall_Player allows
 * and only writes their own predictions. The deadline is enforced here, not
 * only in the UI: a gameweek is locked when Locked__c is true OR its deadline
 * has passed (docs/game-rules.md).
 */
public with sharing class PredictionController {
  @TestVisible
  private static final Integer MAX_GOALS = 20;

  // ---------- What the component receives ----------

  public class GameweekView {
    @AuraEnabled
    public Id gameweekId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Integer gameweekNumber;
    @AuraEnabled
    public Datetime deadline;
    @AuraEnabled
    public Boolean locked;
    @AuraEnabled
    public Id previousGameweekId;
    @AuraEnabled
    public Id nextGameweekId;
    @AuraEnabled
    public List<FixtureView> fixtures = new List<FixtureView>();
  }

  public class FixtureView {
    @AuraEnabled
    public Id fixtureId;
    @AuraEnabled
    public String homeTeam;
    @AuraEnabled
    public String awayTeam;
    @AuraEnabled
    public String homeCrest;
    @AuraEnabled
    public String awayCrest;
    @AuraEnabled
    public Datetime kickoff;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Integer homeGoals;
    @AuraEnabled
    public Integer awayGoals;
    @AuraEnabled
    public Integer predictedHome;
    @AuraEnabled
    public Integer predictedAway;
    @AuraEnabled
    public String predictionStatus;
    @AuraEnabled
    public Integer points;
    @AuraEnabled
    public Boolean exactScore;
  }

  // ---------- What the component sends ----------

  public class PredictionInput {
    @AuraEnabled
    public Id fixtureId { get; set; }
    @AuraEnabled
    public Integer homeGoals { get; set; }
    @AuraEnabled
    public Integer awayGoals { get; set; }
  }

  // ---------- API ----------

  /**
   * The given gameweek, or (when null) the next open one: the open gameweek
   * with the earliest deadline. When nothing is open any more, the latest one.
   * cacheable=true: the result is cached on the client and can be @wire'd.
   */
  @AuraEnabled(cacheable=true)
  public static GameweekView getGameweek(Id gameweekId) {
    Gameweek__c gameweek = gameweekId != null
      ? findGameweek(gameweekId)
      : defaultGameweek();
    return gameweek == null ? null : view(gameweek);
  }

  /**
   * Inserts or updates the current user's predictions for one gameweek and
   * returns the refreshed gameweek. Fixtures left completely empty are skipped.
   */
  @AuraEnabled
  public static GameweekView saveGameweekPredictions(
    Id gameweekId,
    List<PredictionInput> predictions
  ) {
    Gameweek__c gameweek = findGameweek(gameweekId);
    if (gameweek == null) {
      throw error('This gameweek doesn\'t exist.');
    }
    if (isLocked(gameweek)) {
      throw error(
        'The deadline for ' +
          gameweek.Name +
          ' has passed. Predictions are locked.'
      );
    }

    Map<Id, Fixture__c> fixtures = new Map<Id, Fixture__c>(
      [
        SELECT Id, Name, Status__c
        FROM Fixture__c
        WHERE Gameweek__c = :gameweekId
        WITH USER_MODE
      ]
    );
    Map<Id, Prediction__c> mine = myPredictionsByFixture(gameweekId);

    List<Prediction__c> toInsert = new List<Prediction__c>();
    List<Prediction__c> toUpdate = new List<Prediction__c>();
    for (PredictionInput input : predictions) {
      if (input.homeGoals == null && input.awayGoals == null) {
        continue; // not predicted (yet)
      }
      Fixture__c fixture = fixtures.get(input.fixtureId);
      validate(input, fixture);

      Prediction__c existing = mine.get(input.fixtureId);
      if (existing == null) {
        toInsert.add(
          new Prediction__c(
            Fixture__c = input.fixtureId,
            Gameweek__c = gameweekId,
            Home_Goals__c = input.homeGoals,
            Away_Goals__c = input.awayGoals
          )
        );
      } else if (
        existing.Home_Goals__c != input.homeGoals ||
        existing.Away_Goals__c != input.awayGoals
      ) {
        toUpdate.add(
          new Prediction__c(
            Id = existing.Id,
            Home_Goals__c = input.homeGoals,
            Away_Goals__c = input.awayGoals
          )
        );
      }
    }
    Database.insert(toInsert, AccessLevel.USER_MODE);
    Database.update(toUpdate, AccessLevel.USER_MODE);

    return view(findGameweek(gameweekId));
  }

  // ---------- Helpers ----------

  private static void validate(PredictionInput input, Fixture__c fixture) {
    if (fixture == null) {
      throw error('This match isn\'t part of the gameweek.');
    }
    if (fixture.Status__c == 'Postponed') {
      throw error(fixture.Name + ' is postponed and can\'t be predicted.');
    }
    if (
      input.homeGoals == null ||
      input.awayGoals == null ||
      input.homeGoals < 0 ||
      input.awayGoals < 0 ||
      input.homeGoals > MAX_GOALS ||
      input.awayGoals > MAX_GOALS
    ) {
      throw error(
        'Enter both scores for ' +
          fixture.Name +
          ' (whole numbers from 0 to ' +
          MAX_GOALS +
          ').'
      );
    }
  }

  @TestVisible
  private static Boolean isLocked(Gameweek__c gameweek) {
    return gameweek.Locked__c ||
      (gameweek.Deadline__c != null &&
      System.now() >= gameweek.Deadline__c);
  }

  private static Gameweek__c findGameweek(Id gameweekId) {
    List<Gameweek__c> found = [
      SELECT Id, Name, Number__c, Deadline__c, Locked__c, Season__c
      FROM Gameweek__c
      WHERE Id = :gameweekId
      WITH USER_MODE
    ];
    return found.isEmpty() ? null : found[0];
  }

  private static Gameweek__c defaultGameweek() {
    Datetime now = System.now();
    List<Gameweek__c> open = [
      SELECT Id, Name, Number__c, Deadline__c, Locked__c, Season__c
      FROM Gameweek__c
      WHERE
        Locked__c = FALSE
        AND Deadline__c > :now
        AND Season__r.Status__c IN ('Active', 'Upcoming')
      WITH USER_MODE
      ORDER BY Deadline__c
      LIMIT 1
    ];
    if (!open.isEmpty()) {
      return open[0];
    }
    List<Gameweek__c> latest = [
      SELECT Id, Name, Number__c, Deadline__c, Locked__c, Season__c
      FROM Gameweek__c
      WITH USER_MODE
      ORDER BY Season__r.Start_Date__c DESC NULLS LAST, Number__c DESC
      LIMIT 1
    ];
    return latest.isEmpty() ? null : latest[0];
  }

  private static Map<Id, Prediction__c> myPredictionsByFixture(Id gameweekId) {
    Id me = UserInfo.getUserId();
    Map<Id, Prediction__c> byFixture = new Map<Id, Prediction__c>();
    for (Prediction__c prediction : [
      SELECT
        Id,
        Fixture__c,
        Home_Goals__c,
        Away_Goals__c,
        Status__c,
        Points__c,
        Exact_Score__c
      FROM Prediction__c
      WHERE Gameweek__c = :gameweekId AND OwnerId = :me
      WITH USER_MODE
    ]) {
      byFixture.put(prediction.Fixture__c, prediction);
    }
    return byFixture;
  }

  private static GameweekView view(Gameweek__c gameweek) {
    GameweekView result = new GameweekView();
    result.gameweekId = gameweek.Id;
    result.name = gameweek.Name;
    result.gameweekNumber = gameweek.Number__c.intValue();
    result.deadline = gameweek.Deadline__c;
    result.locked = isLocked(gameweek);

    for (Gameweek__c neighbour : [
      SELECT Id, Number__c
      FROM Gameweek__c
      WHERE
        Season__c = :gameweek.Season__c
        AND (Number__c = :gameweek.Number__c - 1
        OR Number__c = :gameweek.Number__c + 1)
      WITH USER_MODE
    ]) {
      if (neighbour.Number__c < gameweek.Number__c) {
        result.previousGameweekId = neighbour.Id;
      } else {
        result.nextGameweekId = neighbour.Id;
      }
    }

    Map<Id, Prediction__c> mine = myPredictionsByFixture(gameweek.Id);
    for (Fixture__c fixture : [
      SELECT
        Id,
        Kickoff__c,
        Status__c,
        Home_Goals__c,
        Away_Goals__c,
        Home_Team__r.Name,
        Home_Team__r.Crest_URL__c,
        Away_Team__r.Name,
        Away_Team__r.Crest_URL__c
      FROM Fixture__c
      WHERE Gameweek__c = :gameweek.Id
      WITH USER_MODE
      ORDER BY Kickoff__c, Name
    ]) {
      FixtureView row = new FixtureView();
      row.fixtureId = fixture.Id;
      row.homeTeam = fixture.Home_Team__r.Name;
      row.awayTeam = fixture.Away_Team__r.Name;
      row.homeCrest = fixture.Home_Team__r.Crest_URL__c;
      row.awayCrest = fixture.Away_Team__r.Crest_URL__c;
      row.kickoff = fixture.Kickoff__c;
      row.status = fixture.Status__c;
      row.homeGoals = toInteger(fixture.Home_Goals__c);
      row.awayGoals = toInteger(fixture.Away_Goals__c);

      Prediction__c prediction = mine.get(fixture.Id);
      if (prediction != null) {
        row.predictedHome = toInteger(prediction.Home_Goals__c);
        row.predictedAway = toInteger(prediction.Away_Goals__c);
        row.predictionStatus = prediction.Status__c;
        row.points = toInteger(prediction.Points__c);
        row.exactScore = prediction.Exact_Score__c;
      }
      result.fixtures.add(row);
    }
    return result;
  }

  private static Integer toInteger(Decimal value) {
    return value == null ? null : value.intValue();
  }

  /** AuraHandledException hides its message unless setMessage() is called. */
  private static AuraHandledException error(String message) {
    AuraHandledException e = new AuraHandledException(message);
    e.setMessage(message);
    return e;
  }
}
