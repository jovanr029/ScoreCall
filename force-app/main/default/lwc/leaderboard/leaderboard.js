import { LightningElement, wire } from "lwc";
import getLeaderboard from "@salesforce/apex/LeaderboardController.getLeaderboard";

const SEASON = "";

/**
 * Standings for the active season (#9): the whole season, or one gameweek
 * picked from the combobox. Ranking and tie-breaker are done in Apex.
 */
export default class Leaderboard extends LightningElement {
  /** "" = the whole season; otherwise a gameweek Id. */
  selected = SEASON;
  leaderboard;
  error;

  // The combobox can't hold null, so "" stands for "whole season".
  @wire(getLeaderboard, { gameweekId: "$gameweekId" })
  wiredLeaderboard({ data, error }) {
    if (data) {
      this.leaderboard = data;
      this.error = undefined;
    } else if (error) {
      this.leaderboard = undefined;
      this.error = reduceError(error);
    }
  }

  get gameweekId() {
    return this.selected === SEASON ? null : this.selected;
  }

  get isLoading() {
    return !this.leaderboard && !this.error;
  }

  get subtitle() {
    const season = this.leaderboard?.seasonName;
    if (!season) {
      return "";
    }
    const picked = this.leaderboard.gameweeks?.find(
      (gameweek) => gameweek.gameweekId === this.selected
    );
    return picked ? picked.name : `Season ${season}`;
  }

  get options() {
    return [
      { label: "Whole season", value: SEASON },
      ...(this.leaderboard?.gameweeks || []).map((gameweek) => ({
        label: gameweek.name,
        value: gameweek.gameweekId
      }))
    ];
  }

  get hasRows() {
    return this.leaderboard?.rows?.length > 0;
  }

  get rows() {
    return (this.leaderboard?.rows || []).map((row) => ({
      ...row,
      rowClass: row.isCurrentUser ? "me" : ""
    }));
  }

  handleChange(event) {
    this.selected = event.detail.value;
  }
}

export function reduceError(error) {
  return error?.body?.message || error?.message || "Unknown error";
}
