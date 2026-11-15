/**
 * Scores season table predictions (#18, docs/game-rules.md).
 *
 * A season's table predictions get their points once the season is Finished:
 * each team's predicted position against Season_Team__c.Position__c, points
 * from ScoringService.tablePoints (Scoring_Rule__mdt). If the final table is
 * corrected later, the points follow; if a season stops being Finished, the
 * points are cleared again.
 *
 * Called from the Season__c trigger (status changes) and the Season_Team__c
 * trigger (positions change). The sync writes the season before the table,
 * so both are needed to end up with the final positions.
 *
 * System mode: table predictions are private to each player, and scoring
 * must reach everyone's. It only ever changes Points__c.
 */
public without sharing class TableScoringService {
  public static void refresh(Set<Id> seasonIds) {
    if (seasonIds == null || seasonIds.isEmpty()) {
      return;
    }
    Set<Id> finished = new Set<Id>();
    for (Season__c season : [
      SELECT Id
      FROM Season__c
      WHERE Id IN :seasonIds AND Status__c = 'Finished'
      WITH SYSTEM_MODE
    ]) {
      finished.add(season.Id);
    }

    // seasonId -> (teamId -> final position)
    Map<Id, Map<Id, Integer>> positions = new Map<Id, Map<Id, Integer>>();
    for (Season_Team__c seasonTeam : [
      SELECT Season__c, Team__c, Position__c
      FROM Season_Team__c
      WHERE Season__c IN :finished
      WITH SYSTEM_MODE
    ]) {
      if (!positions.containsKey(seasonTeam.Season__c)) {
        positions.put(seasonTeam.Season__c, new Map<Id, Integer>());
      }
      positions.get(seasonTeam.Season__c)
        .put(
          seasonTeam.Team__c,
          seasonTeam.Position__c == null
            ? null
            : seasonTeam.Position__c.intValue()
        );
    }

    List<Table_Prediction__c> changed = new List<Table_Prediction__c>();
    for (Table_Prediction__c prediction : [
      SELECT Id, Season__c, Team__c, Predicted_Position__c, Points__c
      FROM Table_Prediction__c
      WHERE Season__c IN :seasonIds
      WITH SYSTEM_MODE
    ]) {
      Decimal points = null;
      if (finished.contains(prediction.Season__c)) {
        Map<Id, Integer> table = positions.get(prediction.Season__c);
        points = ScoringService.tablePoints(
          prediction.Predicted_Position__c.intValue(),
          table == null ? null : table.get(prediction.Team__c)
        );
      }
      if (prediction.Points__c != points) {
        changed.add(
          new Table_Prediction__c(Id = prediction.Id, Points__c = points)
        );
      }
    }
    Database.update(changed, AccessLevel.SYSTEM_MODE);
  }
}
