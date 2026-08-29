# frozen_string_literal: true

module ::Jobs
  # Re-read every linked member's current tier so a revoked or deleted
  # Mask.ID unlinks, and a tier change moves the badge / trust-level floor.
  class MaskidRefresh < ::Jobs::Scheduled
    every 6.hours

    def execute(_args)
      return unless SiteSetting.maskid_enabled
      cutoff = SiteSetting.maskid_refresh_days.days.ago
      UserCustomField
        .where(name: Maskid::SUBJECT_FIELD)
        .find_each do |f|
          user = User.find_by(id: f.user_id) or next
          checked = user.custom_fields[Maskid::CHECKED_AT_FIELD]
          next if checked.present? && Time.parse(checked) > cutoff
          Maskid::Apply.refresh!(user)
        end
    end
  end
end
