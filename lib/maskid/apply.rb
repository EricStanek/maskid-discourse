# frozen_string_literal: true

module ::Maskid
  # Turn a verified payload into the user's standing on this forum.
  module Apply
    def self.link!(user, payload)
      tier = TIERS.include?(payload["trust_index_tier"]) ? payload["trust_index_tier"] : "unproven"

      user.custom_fields[SUBJECT_FIELD] = payload["subject_id"]
      user.custom_fields[TIER_FIELD] = tier
      user.custom_fields[INDEX_FIELD] = payload["trust_index"].to_i
      user.custom_fields[VERIFIED_AT_FIELD] = payload["issued_at"]
      user.custom_fields[CHECKED_AT_FIELD] = Time.now.utc.iso8601
      user.save_custom_fields(true)

      Badges.sync!(user, tier)
      promote!(user, tier)
      tier
    end

    # The tier sets a FLOOR on trust level, never a ceiling: a member who
    # earned TL3 the hard way keeps it. Staff and manually-locked levels are
    # left alone.
    def self.promote!(user, tier)
      floor = {
        "trusted" => SiteSetting.maskid_trust_level_trusted,
        "building" => SiteSetting.maskid_trust_level_building,
        "low" => SiteSetting.maskid_trust_level_low,
      }[tier]
      return if floor.nil? || user.staff? || user.manual_locked_trust_level.present?
      return if user.trust_level >= floor
      user.change_trust_level!(floor, log_action_for: Discourse.system_user)
    rescue StandardError => e
      Rails.logger.warn("maskid: could not promote user #{user.id}: #{e.message}")
    end

    def self.unlink!(user)
      [SUBJECT_FIELD, TIER_FIELD, INDEX_FIELD, VERIFIED_AT_FIELD, CHECKED_AT_FIELD].each do |f|
        user.custom_fields.delete(f)
      end
      user.save_custom_fields(true)
      Badges.revoke_all!(user)
      # Trust level is deliberately NOT lowered on unlink — the member keeps
      # what they have; the badge and icon simply go.
    end

    # Re-read the subject endpoint; 404 = revoked/deleted → unlink.
    # Returns :linked, :unlinked, or :error (nothing changed; try again later).
    def self.refresh!(user)
      subject = user.custom_fields[SUBJECT_FIELD]
      return :unlinked if subject.blank?
      url = "#{SiteSetting.maskid_host.chomp("/")}/api/attest/v1/subject/#{subject}"
      res = Net::HTTP.get_response(URI(url))
      case res.code.to_i
      when 200
        body = JSON.parse(res.body)
        bytes = Base64.urlsafe_decode64(Key.pad(body["payload"]))
        return :error unless Key.verify?(bytes, body["signature"])
        payload = JSON.parse(bytes)
        return :error unless payload["subject_id"] == subject
        link!(user, payload)
        :linked
      when 404
        unlink!(user)
        :unlinked
      else
        :error
      end
    rescue StandardError => e
      Rails.logger.warn("maskid: refresh failed for user #{user.id}: #{e.message}")
      :error
    end

    # A revocation notice named this subject. The notice is only a prompt:
    # re-read the subject and let the 404 unlink, so a stale or replayed
    # notice can never unlink a member who has since linked again.
    # Returns :error when the re-read failed, so the caller can ask Mask.ID
    # to send the notice again.
    def self.revoked!(subject_id)
      field = UserCustomField.find_by(name: SUBJECT_FIELD, value: subject_id)
      user = field && User.find_by(id: field.user_id)
      return :unknown if user.nil?
      refresh!(user)
    end
  end
end
