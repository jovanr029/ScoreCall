import { LightningElement, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import Toast from "lightning/toast";
import ToastContainer from "lightning/toastContainer";
import getTablePrediction from "@salesforce/apex/TablePredictionController.getTablePrediction";
import saveTablePrediction from "@salesforce/apex/TablePredictionController.saveTablePrediction";

/**
 * Season table prediction (#18): put the 20 teams in your predicted final
 * order with the up/down buttons (drag and drop doesn't work reliably on
 * phones), save before the deadline. After the deadline: read-only, with
 * points "if the season ended today" and everyone's tables.
 *
 * The deadline is enforced in Apex; this component only reflects it.
 */
export default class TablePrediction extends LightningElement {
  view;
  error;
  /** Team rows in the order on screen; differs from Apex until saved. */
  order = [];
  dirty = false;
  saving = false;
  /** Whose table to show after the deadline (userId). */
  selectedPlayer;

  wiredResult;

  connectedCallback() {
    // LWR sites only show toasts once a container exists (see predictionEntry).
    ToastContainer.instance();
  }

  @wire(getTablePrediction)
  wiredTable(result) {
    this.wiredResult = result;
    const { data, error } = result;
    if (data) {
      this.showView(data);
    } else if (error) {
      this.view = undefined;
      this.error = reduceError(error);
    }
  }

  showView(view) {
    this.view = view;
    this.error = undefined;
    this.order = view.myTable.map((row) => ({ ...row }));
    this.dirty = false;
    const me = view.players?.find((player) => player.isCurrentUser);
    this.selectedPlayer = me ? me.userId : view.players?.[0]?.userId;
  }

  // ---------- state ----------

  get isLoading() {
    return !this.view && !this.error;
  }

  get hasSeason() {
    return Boolean(this.view?.seasonId);
  }

  get isOpen() {
    return Boolean(this.view?.isOpen);
  }

  /** No deadline yet: the PO hasn't opened table predictions. */
  get notOpenYet() {
    return this.hasSeason && !this.view.deadline;
  }

  get isClosed() {
    return this.hasSeason && Boolean(this.view.deadline) && !this.isOpen;
  }

  get pointsLabel() {
    return this.view?.isFinished ? "Points" : "Points if it ended today";
  }

  get saveDisabled() {
    return !this.dirty || this.saving;
  }

  get editRows() {
    const last = this.order.length - 1;
    return this.order.map((row, index) => ({
      ...row,
      index,
      position: index + 1,
      shortLabel: row.shortName || row.teamName,
      nowLabel: row.currentPosition ? `now ${row.currentPosition}` : "",
      upDisabled: index === 0,
      downDisabled: index === last
    }));
  }

  get playerOptions() {
    return (this.view?.players || []).map((player) => ({
      label: `${player.name} (${player.points})`,
      value: player.userId
    }));
  }

  get hasPlayers() {
    return this.view?.players?.length > 0;
  }

  /** Read-only table shown after the deadline: the picked player's. */
  get shownTable() {
    const player = this.view?.players?.find(
      (p) => p.userId === this.selectedPlayer
    );
    const rows = player ? player.rows : this.view?.myTable || [];
    return rows.map((row) => ({
      ...row,
      shortLabel: row.shortName || row.teamName,
      nowLabel: row.currentPosition ? `now ${row.currentPosition}` : "",
      pointsText:
        row.points === null || row.points === undefined ? "" : `+${row.points}`
    }));
  }

  get shownTotal() {
    return this.shownTable.reduce((sum, row) => sum + (row.points || 0), 0);
  }

  // ---------- handlers ----------

  handleUp(event) {
    this.move(Number(event.currentTarget.dataset.index), -1);
  }

  handleDown(event) {
    this.move(Number(event.currentTarget.dataset.index), 1);
  }

  move(index, step) {
    const target = index + step;
    if (target < 0 || target >= this.order.length) {
      return;
    }
    // A new array: LWC re-renders when the field is reassigned.
    const order = [...this.order];
    [order[index], order[target]] = [order[target], order[index]];
    this.order = order;
    this.dirty = true;
  }

  handlePlayerChange(event) {
    this.selectedPlayer = event.detail.value;
  }

  async handleSave() {
    this.saving = true;
    try {
      const view = await saveTablePrediction({
        seasonId: this.view.seasonId,
        teamIds: this.order.map((row) => row.teamId)
      });
      this.showView(view);
      Toast.show(
        { label: "Table saved", message: "Good luck!", variant: "success" },
        this
      );
      await refreshApex(this.wiredResult);
    } catch (error) {
      Toast.show(
        {
          label: "Couldn't save your table",
          message: reduceError(error),
          variant: "error"
        },
        this
      );
    } finally {
      this.saving = false;
    }
  }
}

export function reduceError(error) {
  return error?.body?.message || error?.message || "Unknown error";
}
