# frozen_string_literal: true

module ::Maskid
  # Verify a signed response exactly as the Mask.ID spec (§3) tells a relying
  # party to: decode the payload, verify the signature over those BYTES, then
  # parse; check key_id, nonce (single-use, ours), rp_user_id, rp_host.
  class Attestation
    NONCE_TTL = 15.minutes

    Result = Struct.new(:ok, :error, :payload, :user_id, keyword_init: true)

    # ---- nonces: minted at /start, consumed exactly once -------------------
    def self.mint_nonce!(user)
      nonce = SecureRandom.hex(12)
      PluginStore.set(PLUGIN_NAME, "nonce:#{nonce}", { "user_id" => user.id, "at" => Time.now.to_i })
      nonce
    end

    def self.take_nonce!(nonce)
      return nil if nonce.blank?
      row = PluginStore.get(PLUGIN_NAME, "nonce:#{nonce}")
      return nil if row.nil?
      PluginStore.remove(PLUGIN_NAME, "nonce:#{nonce}")
      return nil if Time.now.to_i - row["at"].to_i > NONCE_TTL
      row["user_id"]
    end

    # ---- verify ------------------------------------------------------------
    # `payload_b64`/`signature_b64` from the webhook body or the redirect's
    # `?maskid=<payload>.<signature>`. `expect_user` (redirect mode) must
    # match the nonce's user; the webhook has no session, so the nonce alone
    # binds the response to the user.
    def self.verify(payload_b64, signature_b64, key_id: nil, expect_user: nil)
      return fail("missing") if payload_b64.blank? || signature_b64.blank?
      return fail("key_id") if key_id.present? && key_id != SiteSetting.maskid_key_id

      bytes = Base64.urlsafe_decode64(Key.pad(payload_b64)) rescue nil
      return fail("encoding") if bytes.nil?
      return fail("signature") unless Key.verify?(bytes, signature_b64)

      payload = JSON.parse(bytes) rescue nil
      return fail("payload") unless payload.is_a?(Hash) && payload["type"] == "maskid.attestation"
      return fail("key_id") if payload["key_id"] != SiteSetting.maskid_key_id
      return fail("host") unless host_ok?(payload["rp_host"])

      user_id = take_nonce!(payload["nonce"])
      return fail("nonce") if user_id.nil?
      return fail("user") if expect_user && expect_user.id != user_id
      return fail("rp_user_id") unless payload["rp_user_id"] == "u_#{user_id}"

      Result.new(ok: true, payload: payload, user_id: user_id)
    end

    def self.host_ok?(rp_host)
      rp_host.present? && rp_host.downcase == Discourse.current_hostname.downcase
    end

    def self.fail(code)
      Result.new(ok: false, error: code)
    end
  end
end
