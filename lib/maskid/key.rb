# frozen_string_literal: true

require "ed25519"

module ::Maskid
  # The pinned Mask.ID platform key. Verification is one Ed25519 signature
  # over the raw payload bytes — nothing PIVX-specific anywhere.
  module Key
    STORE_KEY = "public_key"

    # Raw 32-byte public key, or nil when it can't be established.
    def self.raw
      b64 = SiteSetting.maskid_public_key.presence || cached || fetch_and_cache
      return nil if b64.blank?
      Base64.urlsafe_decode64(pad(b64))
    rescue ArgumentError
      nil
    end

    def self.verify?(bytes, signature_b64)
      key = raw
      return false if key.nil? || bytes.nil? || signature_b64.blank?
      sig = Base64.urlsafe_decode64(pad(signature_b64))
      Ed25519::VerifyKey.new(key).verify(sig, bytes)
      true
    rescue Ed25519::VerifyError, ArgumentError
      false
    end

    def self.cached
      PluginStore.get(PLUGIN_NAME, STORE_KEY)
    end

    # Fetch once from the well-known URL and pin — only if its key_id is the
    # one the admin expects (default: the production key).
    def self.fetch_and_cache
      url = "#{SiteSetting.maskid_host.chomp("/")}/.well-known/maskid-attest-key"
      uri = URI(url)
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 6, read_timeout: 6) { |h| h.get(uri.request_uri) }
      return nil unless res.code.to_i == 200
      json = JSON.parse(res.body)
      return nil unless json["alg"] == "ed25519" && json["key_id"] == SiteSetting.maskid_key_id
      PluginStore.set(PLUGIN_NAME, STORE_KEY, json["public_key"])
      json["public_key"]
    rescue StandardError => e
      Rails.logger.warn("maskid: could not fetch platform key from #{url}: #{e.message}")
      nil
    end

    def self.forget!
      PluginStore.remove(PLUGIN_NAME, STORE_KEY)
    end

    def self.pad(b64)
      b64 + "=" * ((4 - b64.length % 4) % 4)
    end
  end
end
