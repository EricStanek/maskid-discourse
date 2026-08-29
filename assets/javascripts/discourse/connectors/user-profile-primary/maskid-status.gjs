import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";

// On a member's profile: their Mask.ID tier (public), and — on your OWN
// profile — the "Link my Mask.ID" / "Unlink" controls.
export default class MaskidStatus extends Component {
  @service currentUser;
  @service siteSettings;
  @tracked busy = false;

  get user() {
    return this.args.outletArgs.model;
  }

  get tier() {
    return this.user?.custom_fields?.maskid_tier;
  }

  get own() {
    return this.currentUser && this.currentUser.id === this.user?.id;
  }

  get enabled() {
    return this.siteSettings.maskid_enabled;
  }

  get tierLabel() {
    return i18n(`maskid.tier.${this.tier}`);
  }

  // A full navigation — Ember would otherwise treat the anchor as an
  // in-app route and never hit the server.
  @action
  start() {
    window.location.assign("/maskid/start");
  }

  @action
  async unlink() {
    this.busy = true;
    try {
      await ajax("/maskid/unlink", { type: "DELETE" });
      window.location.reload();
    } finally {
      this.busy = false;
    }
  }

  <template>
    {{#if this.enabled}}
      <div class="maskid-status">
        {{#if this.tier}}
          <span class="maskid-chip maskid-tier-{{this.tier}}">
            {{dIcon "shield-halved"}}
            {{this.tierLabel}}
          </span>
        {{/if}}
        {{#if this.own}}
          {{#if this.tier}}
            <button
              type="button"
              class="btn btn-flat btn-small maskid-unlink"
              disabled={{this.busy}}
              {{on "click" this.unlink}}
            >{{i18n "maskid.unlink"}}</button>
          {{else}}
            <button
              type="button"
              class="btn btn-primary btn-small maskid-link"
              {{on "click" this.start}}
            >
              {{dIcon "shield-halved"}}
              {{i18n "maskid.link"}}
            </button>
            <p class="maskid-hint">{{i18n "maskid.link_hint"}}</p>
          {{/if}}
        {{/if}}
      </div>
    {{/if}}
  </template>
}
