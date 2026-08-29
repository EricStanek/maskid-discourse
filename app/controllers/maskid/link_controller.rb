# frozen_string_literal: true

module ::Maskid
  class LinkController < ::ApplicationController
    requires_plugin PLUGIN_NAME
    requires_login except: [:webhook]
    skip_before_action :verify_authenticity_token, only: [:webhook]
    skip_before_action :redirect_to_login_if_required, only: [:webhook]

    # "Link my Mask.ID": mint a single-use nonce and send the member to the
    # Mask.ID consent page with this forum's request (redirect + webhook).
    def start
      nonce = Attestation.mint_nonce!(current_user)
      base = Discourse.base_url
      request = {
        v: 1,
        rp_user_id: "u_#{current_user.id}",
        nonce: nonce,
        redirect: "#{base}/maskid/return",
        expires: (Time.now + Attestation::NONCE_TTL).to_i,
      }
      # Mask.ID only POSTs webhooks to public https hosts; a local or http
      # forum works on the redirect alone (the member's browser carries the
      # signed response back).
      request[:webhook] = "#{base}/maskid/webhook" if base.start_with?("https://")
      c = Base64.urlsafe_encode64(request.to_json, padding: false)
      redirect_to "#{SiteSetting.maskid_host.chomp("/")}/verify-trust?c=#{c}", allow_other_host: true
    end

    # Redirect mode: the member comes back with ?maskid=<payload>.<signature>.
    def return
      payload, signature = params[:maskid].to_s.split(".", 2)
      result = Attestation.verify(payload, signature, expect_user: current_user)
      if result.ok
        tier = Apply.link!(current_user, result.payload)
        flash[:maskid] = I18n.t("maskid.linked", tier: tier)
      else
        # A webhook may already have consumed the nonce — that's success too.
        linked = current_user.reload.custom_fields[SUBJECT_FIELD].present?
        flash[:maskid] = linked ? I18n.t("maskid.linked", tier: current_user.custom_fields[TIER_FIELD]) : I18n.t("maskid.failed", reason: result.error)
      end
      redirect_to "/u/#{current_user.username_lower}"
    end

    # Webhook mode: Mask.ID POSTs {payload, signature, key_id}. No session —
    # the single-use nonce binds the response to the user who started it.
    def webhook
      body = JSON.parse(request.raw_post) rescue {}
      result = Attestation.verify(body["payload"], body["signature"], key_id: body["key_id"])
      if result.ok
        user = User.find_by(id: result.user_id)
        Apply.link!(user, result.payload) if user
        render json: { ok: true }
      else
        render json: { ok: false, error: result.error }, status: 422
      end
    end

    def unlink
      Apply.unlink!(current_user)
      render json: { ok: true }
    end
  end
end
