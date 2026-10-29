/**
 * Keeps predictions in line with their fixture (docs/game-rules.md, Postponed
 * matches). For each Open or Voided prediction of the given fixtures:
 *
 *   - Voided (0 points) when the fixture is postponed, or when the prediction
 *     was made in a different gameweek from the one the fixture is in now
 *     (the match moved, forwards or backwards);
 *   - otherwise re-opened if it was voided (a postponed match came back into
 *     the same gameweek).
 *
 * Scored predictions are never touched.
 *
 * without sharing: predictions are private to each player, and voiding must
 * reach every player's prediction, whoever changed the fixture. It only ever
 * changes Status__c and Points__c.
 */
public without sharing class PredictionStatusService {
  public static final String OPEN = 'Open';
  public static final String VOIDED = 'Voided';

  public static void reconcile(List<Fixture__c> fixtures) {
    Map<Id, Fixture__c> fixturesById = new Map<Id, Fixture__c>(fixtures);
    List<Prediction__c> changed = new List<Prediction__c>();

    for (Prediction__c prediction : [
      SELECT Id, Fixture__c, Gameweek__c, Status__c
      FROM Prediction__c
      WHERE
        Fixture__c IN :fixturesById.keySet()
        AND Status__c IN (:OPEN, :VOIDED)
    ]) {
      Fixture__c fixture = fixturesById.get(prediction.Fixture__c);
      Boolean shouldBeVoid =
        fixture.Status__c == 'Postponed' ||
        prediction.Gameweek__c != fixture.Gameweek__c;

      if (shouldBeVoid && prediction.Status__c == OPEN) {
        changed.add(
          new Prediction__c(
            Id = prediction.Id,
            Status__c = VOIDED,
            Points__c = 0
          )
        );
      } else if (!shouldBeVoid && prediction.Status__c == VOIDED) {
        changed.add(
          new Prediction__c(
            Id = prediction.Id,
            Status__c = OPEN,
            Points__c = null
          )
        );
      }
    }
    update changed;
  }
}
