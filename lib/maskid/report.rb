# frozen_string_literal: true

module ::Maskid
  # Write-back (Mask.ID attestation API §4a): tell Mask.ID a linked member
  # was present today. Counts only — Mask.ID publishes "sites active" as a
  # number, never which site. Fire-and-forget; failures are logged, never
  # surfaced to the member.
  module Report
    def self.session!(user)
      subject = user.custom_fields[SUBJECT_FIELD]
      return if subject.blank? || !SiteSetting.maskid_report_sessions
      return if reported_today?(user)

      uri = URI("#{SiteSetting.maskid_host.chomp("/")}/api/attest/v1/subject/#{subject}/events")
      body = { event: "session", nonce: SecureRandom.hex(12) }.to_json
      res =
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 4, read_timeout: 6) do |h|
          h.post(uri.request_uri, body, "Content-Type" => "application/json")
        end
      if res.code.to_i == 204
        user.custom_fields[REPORTED_AT_FIELD] = Time.now.utc.iso8601
        user.save_custom_fields(true)
      else
        Rails.logger.warn("maskid: session report for user #{user.id} answered #{res.code}")
      end
    rescue StandardError => e
      Rails.logger.warn("maskid: session report failed for user #{user.id}: #{e.message}")
    end

    def self.reported_today?(user)
      at = user.custom_fields[REPORTED_AT_FIELD]
      at.present? && Time.parse(at).to_date == Time.now.utc.to_date
    end
  end
end
