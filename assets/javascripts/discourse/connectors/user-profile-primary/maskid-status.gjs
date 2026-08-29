import Component from "@glimmer/component";
import { service } from "@ember/service";
import { action } from "@ember/object";
import { tracked } from "@glimmer/tracking";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";
import icon from "discourse/helpers/d-icon";

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
            {{icon "shield-halved"}}
            {{i18n (concat "maskid.tier." this.tier)}}
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
            <a class="btn btn-primary btn-small maskid-link" href="/maskid/start">
              {{icon "shield-halved"}}
              {{i18n "maskid.link"}}
            </a>
            <p class="maskid-hint">{{i18n "maskid.link_hint"}}</p>
          {{/if}}
        {{/if}}
      </div>
    {{/if}}
  </template>
}
