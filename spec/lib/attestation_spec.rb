# frozen_string_literal: true

require "rails_helper"
require "ed25519"

RSpec.describe Maskid::Attestation do
  fab!(:user)
  let(:signing_key) { Ed25519::SigningKey.generate }
  let(:pub_b64) { Base64.urlsafe_encode64(signing_key.verify_key.to_bytes, padding: false) }
  let(:key_id) { Digest::SHA256.digest(signing_key.verify_key.to_bytes)[0, 8].unpack1("H*") }

  before do
    SiteSetting.maskid_enabled = true
    SiteSetting.maskid_public_key = pub_b64
    SiteSetting.maskid_key_id = key_id
  end

  def signed(payload)
    bytes = payload.to_json
    [Base64.urlsafe_encode64(bytes, padding: false),
     Base64.urlsafe_encode64(signing_key.sign(bytes), padding: false)]
  end

  def payload_for(nonce, overrides = {})
    {
      v: 1, type: "maskid.attestation", key_id: key_id, subject_id: "msub_abc",
      rp_host: Discourse.current_hostname, rp_user_id: described_class.ref_for(nonce), nonce: nonce,
      scopes: ["trust_index"], trust_index: 72, trust_index_tier: "building",
      issued_at: Time.now.utc.iso8601,
    }.merge(overrides)
  end

  it "accepts a correctly signed response for a minted nonce, once" do
    nonce = described_class.mint_nonce!(user)
    p, s = signed(payload_for(nonce))
    r = described_class.verify(p, s, expect_user: user)
    expect(r.ok).to eq(true)
    expect(r.user_id).to eq(user.id)
    # replay: the nonce is spent
    expect(described_class.verify(p, s, expect_user: user).error).to eq("nonce")
  end

  it "rejects a tampered payload" do
    nonce = described_class.mint_nonce!(user)
    p, s = signed(payload_for(nonce))
    tampered = Base64.urlsafe_encode64(payload_for(nonce, trust_index: 99).to_json, padding: false)
    expect(described_class.verify(tampered, s).error).to eq("signature")
  end

  it "rejects another site's response" do
    nonce = described_class.mint_nonce!(user)
    p, s = signed(payload_for(nonce, rp_host: "other.example"))
    expect(described_class.verify(p, s).error).to eq("host")
  end

  it "rejects a response for a different user than the nonce's" do
    nonce = described_class.mint_nonce!(user)
    p, s = signed(payload_for(nonce, rp_user_id: "u_999999"))
    expect(described_class.verify(p, s).error).to eq("rp_user_id")
  end

  it "no longer accepts the forum's user id as the account" do
    nonce = described_class.mint_nonce!(user)
    p, s = signed(payload_for(nonce, rp_user_id: "u_#{user.id}"))
    expect(described_class.verify(p, s).error).to eq("rp_user_id")
  end

  it "rejects an unexpected key id" do
    nonce = described_class.mint_nonce!(user)
    p, s = signed(payload_for(nonce, key_id: "deadbeefdeadbeef"))
    expect(described_class.verify(p, s).error).to eq("key_id")
  end

  describe "revocation notices" do
    def notice(overrides = {})
      signed({
        v: 1, type: "maskid.revocation", key_id: key_id, subject_id: "msub_abc",
        rp_host: Discourse.current_hostname, revoked_at: Time.now.utc.iso8601,
      }.merge(overrides))
    end

    it "accepts a signed notice for this forum" do
      r = described_class.revocation(*notice)
      expect(r.ok).to eq(true)
      expect(r.payload["subject_id"]).to eq("msub_abc")
    end

    it "is not mistaken for an attestation, nor an attestation for a notice" do
      expect(described_class.verify(*notice).error).to eq("payload")
      p, s = signed(payload_for(described_class.mint_nonce!(user)))
      expect(described_class.revocation(p, s).error).to eq("payload")
    end

    it "rejects a forged, foreign or wrong-key notice" do
      p, s = notice
      forged = Base64.urlsafe_encode64({ type: "maskid.revocation", subject_id: "msub_abc" }.to_json, padding: false)
      expect(described_class.revocation(forged, s).error).to eq("signature")
      expect(described_class.revocation(*notice(rp_host: "other.example")).error).to eq("host")
      expect(described_class.revocation(*notice(key_id: "deadbeefdeadbeef")).error).to eq("key_id")
    end
  end

  it "links the user: fields, badge, trust-level floor" do
    SiteSetting.maskid_trust_level_building = 2
    nonce = described_class.mint_nonce!(user)
    p, s = signed(payload_for(nonce))
    r = described_class.verify(p, s)
    Maskid::Apply.link!(user, r.payload)
    user.reload
    expect(user.custom_fields[Maskid::TIER_FIELD]).to eq("building")
    expect(user.custom_fields[Maskid::SUBJECT_FIELD]).to eq("msub_abc")
    expect(user.trust_level).to eq(2)
    expect(user.badges.pluck(:name)).to include("Mask.ID · Building")
    # unlink clears fields + badge, keeps the earned trust level
    Maskid::Apply.unlink!(user)
    user.reload
    expect(user.custom_fields[Maskid::TIER_FIELD]).to be_nil
    expect(user.badges.pluck(:name)).not_to include("Mask.ID · Building")
    expect(user.trust_level).to eq(2)
  end
end

RSpec.describe Maskid::Report do
  fab!(:user)

  before do
    SiteSetting.maskid_enabled = true
    SiteSetting.maskid_host = "https://app.example"
    user.custom_fields[Maskid::SUBJECT_FIELD] = "msub_test_subject"
    user.save_custom_fields(true)
  end

  it "posts one session per day and remembers it" do
    stub = stub_request(:post, "https://app.example/api/attest/v1/subject/msub_test_subject/events")
      .with { |req| JSON.parse(req.body)["event"] == "session" }
      .to_return(status: 204)
    described_class.session!(user)
    described_class.session!(user.reload)
    expect(stub).to have_been_requested.once
  end

  it "does nothing for an unlinked member or when reporting is off" do
    stub = stub_request(:post, %r{/events}).to_return(status: 204)
    SiteSetting.maskid_report_sessions = false
    described_class.session!(user)
    expect(stub).not_to have_been_requested
  end
end
