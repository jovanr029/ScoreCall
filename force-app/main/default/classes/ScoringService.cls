/**
 * Scores predictions (docs/game-rules.md). The points come from the
 * Scoring_Rule__mdt record "Default" (3 and 5 at the time of writing):
 *
 *   exact score                        outcome points + exact score bonus
 *   correct outcome (home/draw/away)   outcome points
 *   anything else                      0 points
 *
 * Only predictions made in the fixture's current gameweek are scored; Voided
 * ones never are. A corrected result re-scores them, and an annulled result
 * (Finished -> not finished) puts them back to Open.
 *
 * without sharing: predictions are private to each player, and scoring must
 * reach every player's prediction, whoever updated the fixture. It only ever
 * changes Status__c, Points__c and Exact_Score__c.
 */
public without sharing class ScoringService {
  public static final String SCORED = 'Scored';
  public static final String RULES_NAME = 'Default';

  /** Lets tests use their own points, independent of the org's record. */
  @TestVisible
  private static Scoring_Rule__mdt rulesOverride;

  /** The active scoring rules. getInstance() reads from cache: no SOQL limit used. */
  @TestVisible
  private static Scoring_Rule__mdt rules() {
    if (rulesOverride != null) {
      return rulesOverride;
    }
    Scoring_Rule__mdt rules = Scoring_Rule__mdt.getInstance(RULES_NAME);
    if (rules == null) {
      throw new ScoringException(
        'Scoring rule "' + RULES_NAME + '" (Scoring_Rule__mdt) is missing'
      );
    }
    return rules;
  }

  public class ScoringException extends Exception {
  }

  /** Points for one prediction, using the active rules. */
  public static Integer points(
    Integer predictedHome,
    Integer predictedAway,
    Integer actualHome,
    Integer actualAway
  ) {
    Scoring_Rule__mdt rules = rules();
    Integer outcomePoints = rules.Outcome_Points__c.intValue();
    if (isExact(predictedHome, predictedAway, actualHome, actualAway)) {
      return outcomePoints + rules.Exact_Score_Bonus__c.intValue();
    }
    if (
      outcome(predictedHome, predictedAway) == outcome(actualHome, actualAway)
    ) {
      return outcomePoints;
    }
    return 0;
  }

  private static Boolean isExact(
    Integer predictedHome,
    Integer predictedAway,
    Integer actualHome,
    Integer actualAway
  ) {
    return predictedHome == actualHome && predictedAway == actualAway;
  }

  /**
   * Recalculates every finished fixture of a season with the current rules,
   * e.g. after the points in Scoring_Rule__mdt were changed. Only predictions
   * whose points actually change are updated.
   * See scripts/apex/rescore-season.apex.
   */
  public static void rescoreSeason(Id seasonId) {
    score(
      [
        SELECT Id, Gameweek__c, Status__c, Home_Goals__c, Away_Goals__c
        FROM Fixture__c
        WHERE Gameweek__r.Season__c = :seasonId AND Status__c = 'Finished'
      ]
    );
  }

  /** 1 = home win, 0 = draw, -1 = away win. */
  private static Integer outcome(Integer home, Integer away) {
    return home > away ? 1 : (home == away ? 0 : -1);
  }

  /**
   * Scores (or un-scores) the predictions of the given fixtures according to
   * their current status and result.
   */
  public static void score(List<Fixture__c> fixtures) {
    Map<Id, Fixture__c> fixturesById = new Map<Id, Fixture__c>(fixtures);
    List<Prediction__c> changed = new List<Prediction__c>();

    for (Prediction__c prediction : [
      SELECT
        Id,
        Fixture__c,
        Gameweek__c,
        Home_Goals__c,
        Away_Goals__c,
        Status__c,
        Points__c,
        Exact_Score__c
      FROM Prediction__c
      WHERE
        Fixture__c IN :fixturesById.keySet()
        AND Status__c IN (:PredictionStatusService.OPEN, :SCORED)
    ]) {
      Fixture__c fixture = fixturesById.get(prediction.Fixture__c);
      if (prediction.Gameweek__c != fixture.Gameweek__c) {
        continue; // made in another gameweek: voiding handles it
      }

      Prediction__c change = fixture.Status__c == 'Finished'
        ? scored(prediction, fixture)
        : reopened(prediction);
      if (change != null) {
        changed.add(change);
      }
    }
    update changed;
  }

  /** The scored version of the prediction, or null if nothing changes. */
  private static Prediction__c scored(
    Prediction__c prediction,
    Fixture__c fixture
  ) {
    Integer predictedHome = prediction.Home_Goals__c.intValue();
    Integer predictedAway = prediction.Away_Goals__c.intValue();
    Integer actualHome = fixture.Home_Goals__c.intValue();
    Integer actualAway = fixture.Away_Goals__c.intValue();
    Integer points = points(
      predictedHome,
      predictedAway,
      actualHome,
      actualAway
    );
    // Compare the scores, not the points: stays right whatever the bonus is.
    Boolean exact = isExact(
      predictedHome,
      predictedAway,
      actualHome,
      actualAway
    );
    if (
      prediction.Status__c == SCORED &&
      prediction.Points__c == points &&
      prediction.Exact_Score__c == exact
    ) {
      return null;
    }
    return new Prediction__c(
      Id = prediction.Id,
      Status__c = SCORED,
      Points__c = points,
      Exact_Score__c = exact
    );
  }

  /** A scored prediction whose fixture is no longer finished goes back to Open. */
  private static Prediction__c reopened(Prediction__c prediction) {
    if (prediction.Status__c != SCORED) {
      return null;
    }
    return new Prediction__c(
      Id = prediction.Id,
      Status__c = PredictionStatusService.OPEN,
      Points__c = null,
      Exact_Score__c = false
    );
  }
}
