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
      rp_host: Discourse.current_hostname, rp_user_id: "u_#{user.id}", nonce: nonce,
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

  it "rejects an unexpected key id" do
    nonce = described_class.mint_nonce!(user)
    p, s = signed(payload_for(nonce, key_id: "deadbeefdeadbeef"))
    expect(described_class.verify(p, s).error).to eq("key_id")
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
