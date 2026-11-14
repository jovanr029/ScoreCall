import { LightningElement, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import Toast from "lightning/toast";
import ToastContainer from "lightning/toastContainer";
import getGameweek from "@salesforce/apex/PredictionController.getGameweek";
import saveGameweekPredictions from "@salesforce/apex/PredictionController.saveGameweekPredictions";

const TICK_MS = 1000;
const MAX_GOALS = 20;
const STATUS_LABELS = {
  Live: "Live",
  Finished: "Full time",
  Postponed: "Postponed"
};

/**
 * Lets the current user predict the scores of one gameweek.
 *
 * Data flow:
 *   @wire(getGameweek)            reads the gameweek (cached, re-runs when gameweekId changes)
 *   handleScoreChange()           keeps unsaved edits in `drafts`
 *   saveGameweekPredictions()     imperative Apex call on Save, then refreshApex()
 *
 * The deadline is enforced in Apex; this component only reflects it.
 */
export default class PredictionEntry extends LightningElement {
  /** null = let Apex choose the next open gameweek. */
  gameweekId = null;
  gameweek;
  error;
  /** fixtureId -> { home, away }: edits not saved yet. */
  drafts = {};
  saving = false;
  now = Date.now();

  wiredGameweekResult;
  timer;

  // '$gameweekId' makes the parameter reactive: changing this.gameweekId
  // (the ◀ ▶ buttons) makes the wire service call Apex again.
  @wire(getGameweek, { gameweekId: "$gameweekId" })
  wiredGameweek(result) {
    this.wiredGameweekResult = result; // kept for refreshApex()
    const { data, error } = result;
    if (data) {
      this.gameweek = data;
      this.error = undefined;
      this.drafts = {};
    } else if (error) {
      this.gameweek = undefined;
      this.error = reduceError(error);
    }
  }

  // Lifecycle hooks: start the countdown when the component is inserted in
  // the page, and always stop it when it's removed (or it keeps running).
  connectedCallback() {
    // LWR sites have no toast container until one is created; Lightning
    // Experience already has one. instance() returns the same container
    // every time, so calling it from every component is safe.
    const toastContainer = ToastContainer.instance();
    if (toastContainer) {
      toastContainer.toastPosition = "top-center";
    }
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- the countdown needs a timer
    this.timer = setInterval(() => {
      this.now = Date.now();
    }, TICK_MS);
  }

  disconnectedCallback() {
    clearInterval(this.timer);
  }

  // ---------- Getters: the template only reads simple values ----------

  get isLoading() {
    return !this.gameweek && !this.error;
  }

  get title() {
    return this.gameweek ? this.gameweek.name : "Predictions";
  }

  get deadlinePassed() {
    return (
      Boolean(this.gameweek?.deadline) &&
      Date.parse(this.gameweek.deadline) <= this.now
    );
  }

  get isLocked() {
    return Boolean(this.gameweek?.locked) || this.deadlinePassed;
  }

  get countdown() {
    if (!this.gameweek?.deadline) {
      return "";
    }
    return formatDuration(Date.parse(this.gameweek.deadline) - this.now);
  }

  get hasFixtures() {
    return this.gameweek?.fixtures?.length > 0;
  }

  get rows() {
    return (this.gameweek?.fixtures || []).map((fixture) => {
      const draft = this.drafts[fixture.fixtureId];
      const isPostponed = fixture.status === "Postponed";
      const hasResult =
        fixture.status === "Finished" || fixture.status === "Live";
      return {
        ...fixture,
        home: draft ? draft.home : fixture.predictedHome,
        away: draft ? draft.away : fixture.predictedAway,
        // Phones show the three-letter code; fall back to the full name.
        homeShortName: fixture.homeShort || fixture.homeTeam,
        awayShortName: fixture.awayShort || fixture.awayTeam,
        homeLabel: `${fixture.homeTeam} goals`,
        awayLabel: `${fixture.awayTeam} goals`,
        disabled: this.isLocked || isPostponed,
        statusLabel: STATUS_LABELS[fixture.status],
        hasResult,
        pointsLabel: pointsLabel(fixture),
        pointsClass: pointsClass(fixture)
      };
    });
  }

  get hasUnsavedChanges() {
    return Object.keys(this.drafts).length > 0;
  }

  get showSave() {
    return Boolean(this.gameweek) && this.hasFixtures && !this.isLocked;
  }

  get saveDisabled() {
    return !this.hasUnsavedChanges || this.saving;
  }

  get noPrevious() {
    return !this.gameweek?.previousGameweekId;
  }

  get noNext() {
    return !this.gameweek?.nextGameweekId;
  }

  // ---------- Event handlers ----------

  handleScoreChange(event) {
    const { fixtureId, side } = event.target.dataset;
    const fixture = this.gameweek.fixtures.find(
      (f) => f.fixtureId === fixtureId
    );
    const current = this.drafts[fixtureId] || {
      home: fixture.predictedHome ?? null,
      away: fixture.predictedAway ?? null
    };
    // Assign a NEW object: LWC re-renders when a field is reassigned, not
    // when something deep inside it is mutated.
    this.drafts = {
      ...this.drafts,
      [fixtureId]: { ...current, [side]: toGoals(event.target.value) }
    };
  }

  handlePrevious() {
    this.gameweekId = this.gameweek.previousGameweekId;
  }

  handleNext() {
    this.gameweekId = this.gameweek.nextGameweekId;
  }

  async handleSave() {
    if (!this.allInputsValid()) {
      return;
    }
    this.saving = true;
    try {
      const predictions = Object.entries(this.drafts).map(
        ([fixtureId, draft]) => ({
          fixtureId,
          homeGoals: draft.home,
          awayGoals: draft.away
        })
      );
      // Imperative call: runs only when we call it, and may change data
      // (a cacheable @wire method can't).
      await saveGameweekPredictions({
        gameweekId: this.gameweek.gameweekId,
        predictions
      });
      this.toast("Predictions saved", "Good luck!", "success");
      // The wired data is cached: ask the wire service to fetch it again.
      await refreshApex(this.wiredGameweekResult);
      this.drafts = {};
    } catch (error) {
      this.toast("Couldn't save your predictions", reduceError(error), "error");
    } finally {
      this.saving = false;
    }
  }

  allInputsValid() {
    return [...this.template.querySelectorAll("lightning-input")].reduce(
      (valid, input) => input.reportValidity() && valid,
      true
    );
  }

  // lightning/toast works in Lightning Experience and on LWR sites.
  // (ShowToastEvent needs the Lightning Experience container: on an LWR site
  // nothing listens for it, so the toast would silently not appear.)
  toast(label, message, variant) {
    Toast.show({ label, message, variant }, this);
  }

  get maxGoals() {
    return MAX_GOALS;
  }
}

// ---------- Helpers (plain functions, easy to test) ----------

function toGoals(value) {
  return value === "" || value === null || value === undefined
    ? null
    : parseInt(value, 10);
}

function pointsLabel(fixture) {
  if (fixture.predictionStatus === "Voided") {
    return "Void";
  }
  if (fixture.predictionStatus === "Scored") {
    return `+${fixture.points}`;
  }
  return "";
}

function pointsClass(fixture) {
  if (fixture.predictionStatus !== "Scored") {
    return "slds-badge";
  }
  if (fixture.exactScore) {
    return "slds-badge slds-theme_success";
  }
  return fixture.points > 0 ? "slds-badge slds-badge_lightest" : "slds-badge";
}

export function formatDuration(milliseconds) {
  if (milliseconds <= 0) {
    return "0m";
  }
  const totalMinutes = Math.floor(milliseconds / 60000);
  const days = Math.floor(totalMinutes / 1440);
  const hours = Math.floor((totalMinutes % 1440) / 60);
  const minutes = totalMinutes % 60;
  if (days > 0) {
    return `${days}d ${hours}h`;
  }
  if (hours > 0) {
    return `${hours}h ${minutes}m`;
  }
  const seconds = Math.floor((milliseconds % 60000) / 1000);
  return `${minutes}m ${seconds}s`;
}

export function reduceError(error) {
  return error?.body?.message || error?.message || "Unknown error";
}
