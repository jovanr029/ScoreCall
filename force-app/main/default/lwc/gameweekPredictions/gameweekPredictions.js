import { LightningElement, wire } from "lwc";
import getGameweekPredictions from "@salesforce/apex/GameweekPredictionsController.getGameweekPredictions";

const STATUS_LABELS = {
  Live: "Live",
  Finished: "Full time",
  Postponed: "Postponed"
};

/**
 * Everyone's predictions for a gameweek whose deadline has passed (#11).
 * Apex decides what may be shown: a gameweek before its deadline is refused
 * there, so this component only offers gameweeks Apex returned.
 */
export default class GameweekPredictions extends LightningElement {
  /** null = the latest gameweek past its deadline (chosen by Apex). */
  gameweekId = null;
  view;
  error;

  @wire(getGameweekPredictions, { gameweekId: "$gameweekId" })
  wiredPredictions({ data, error }) {
    if (data) {
      this.view = data;
      this.error = undefined;
    } else if (error) {
      this.view = undefined;
      this.error = reduceError(error);
    }
  }

  get isLoading() {
    return !this.view && !this.error;
  }

  get hasGameweek() {
    return Boolean(this.view?.gameweekId);
  }

  get hasPlayers() {
    return this.view?.players?.length > 0;
  }

  get noPrevious() {
    return !this.view?.previousGameweekId;
  }

  get noNext() {
    return !this.view?.nextGameweekId;
  }

  get players() {
    return (this.view?.players || []).map((player) => ({
      ...player,
      chipClass: player.isCurrentUser ? "total me" : "total"
    }));
  }

  get matches() {
    return (this.view?.matches || []).map((match) => ({
      ...match,
      hasResult: match.homeGoals !== null && match.homeGoals !== undefined,
      statusLabel: STATUS_LABELS[match.status] || "",
      predictions: match.predictions.map((prediction) => ({
        ...prediction,
        score: scoreLabel(prediction),
        pointsLabel: pointsLabel(prediction),
        rowClass: prediction.isCurrentUser ? "prediction me" : "prediction",
        pointsClass: prediction.exactScore ? "points exact" : "points"
      }))
    }));
  }

  handlePrevious() {
    this.gameweekId = this.view.previousGameweekId;
  }

  handleNext() {
    this.gameweekId = this.view.nextGameweekId;
  }
}

function scoreLabel(prediction) {
  if (prediction.homeGoals === null || prediction.homeGoals === undefined) {
    return "–";
  }
  return `${prediction.homeGoals}–${prediction.awayGoals}`;
}

function pointsLabel(prediction) {
  if (prediction.status === "Voided") {
    return "Void";
  }
  if (prediction.status === "Scored") {
    return `+${prediction.points}`;
  }
  return "";
}

export function reduceError(error) {
  return error?.body?.message || error?.message || "Unknown error";
}
