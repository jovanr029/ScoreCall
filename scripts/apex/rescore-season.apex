// Recalculates the points of every finished match in the active season, and
// the table prediction points of finished seasons, with the current
// Scoring_Rule__mdt values. Run it after a change to the points has
// been deployed. Only predictions whose points change are updated.
//
//   sf apex run --file scripts/apex/rescore-season.apex --target-org <alias>

for (Season__c season : [
  SELECT Id, Name
  FROM Season__c
  WHERE Status__c IN ('Active', 'Finished')
]) {
  ScoringService.rescoreSeason(season.Id);
  TableScoringService.refresh(new Set<Id>{ season.Id });
  AggregateResult total = [
    SELECT COUNT(Id) predictions, SUM(Points__c) points
    FROM Prediction__c
    WHERE Status__c = 'Scored' AND Gameweek__r.Season__c = :season.Id
  ];
  System.debug(
    'RESCORE ' +
      season.Name +
      ': ' +
      total.get('predictions') +
      ' scored predictions, ' +
      total.get('points') +
      ' points in total'
  );
}
