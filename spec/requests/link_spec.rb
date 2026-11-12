# frozen_string_literal: true

require "rails_helper"

RSpec.describe Maskid::LinkController do
  fab!(:user)

  before { SiteSetting.maskid_enabled = true }

  it "/maskid/start requires login" do
    get "/maskid/start"
    # Discourse answers a logged-out HTML request to a login-required action
    # with its not-found page (no information leak), or a redirect/403.
    expect([302, 403, 404]).to include(response.status)
  end

  it "/maskid/start sends the member to Mask.ID with a request naming this forum" do
    sign_in(user)
    get "/maskid/start"
    expect(response.status).to eq(302)
    uri = URI(response.location)
    expect(uri.host).to eq(URI(SiteSetting.maskid_host).host)
    c = Rack::Utils.parse_query(uri.query)["c"]
    req = JSON.parse(Base64.urlsafe_decode64(c + "=" * ((4 - c.length % 4) % 4)))
    # Mask.ID is told a throwaway reference, never the forum's user id.
    expect(req["rp_user_id"]).to match(/\Ar_[\w-]{12}\z/)
    expect(req["rp_user_id"]).to eq(Maskid::Attestation.ref_for(req["nonce"]))
    expect(req.to_json).not_to include("u_#{user.id}")
    expect(req["redirect"]).to end_with("/maskid/return")
    # webhook only on https forums (test base_url is http)
    expect(req["webhook"]).to be_nil
    expect(req["nonce"]).to be_present
  end

  describe "a revocation notice on /maskid/webhook" do
    require "ed25519"

    let(:signing_key) { Ed25519::SigningKey.generate }
    let(:key_id) { Digest::SHA256.digest(signing_key.verify_key.to_bytes)[0, 8].unpack1("H*") }
    let(:subject_url) { "https://app.example/api/attest/v1/subject/msub_linked" }

    before do
      SiteSetting.maskid_host = "https://app.example"
      SiteSetting.maskid_public_key = Base64.urlsafe_encode64(signing_key.verify_key.to_bytes, padding: false)
      SiteSetting.maskid_key_id = key_id
      user.custom_fields[Maskid::SUBJECT_FIELD] = "msub_linked"
      user.custom_fields[Maskid::TIER_FIELD] = "building"
      user.save_custom_fields(true)
    end

    def post_notice(subject_id)
      bytes = {
        v: 1, type: "maskid.revocation", key_id: key_id, subject_id: subject_id,
        rp_host: Discourse.current_hostname, revoked_at: Time.now.utc.iso8601,
      }.to_json
      body = {
        payload: Base64.urlsafe_encode64(bytes, padding: false),
        signature: Base64.urlsafe_encode64(signing_key.sign(bytes), padding: false),
        key_id: key_id,
      }
      post "/maskid/webhook", params: body.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    end

    it "unlinks the member once Mask.ID confirms with a 404" do
      stub_request(:get, subject_url).to_return(status: 404)
      post_notice("msub_linked")
      expect(response.status).to eq(200)
      expect(user.reload.custom_fields[Maskid::SUBJECT_FIELD]).to be_nil
    end

    it "does not unlink on the notice alone: a member Mask.ID still vouches for stays linked" do
      # e.g. a replayed notice after the member linked again. The re-read
      # here answers with something that isn't a valid signed payload, so
      # nothing changes and Mask.ID is asked to retry.
      stub_request(:get, subject_url).to_return(status: 200, body: { payload: "eA", signature: "eA" }.to_json)
      post_notice("msub_linked")
      expect(response.status).to eq(503)
      expect(user.reload.custom_fields[Maskid::SUBJECT_FIELD]).to eq("msub_linked")
    end

    it "asks for a retry when the re-read fails" do
      stub_request(:get, subject_url).to_return(status: 500)
      post_notice("msub_linked")
      expect(response.status).to eq(503)
      expect(user.reload.custom_fields[Maskid::SUBJECT_FIELD]).to eq("msub_linked")
    end

    it "answers 200 for a subject it doesn't know" do
      post_notice("msub_someone_else")
      expect(response.status).to eq(200)
      expect(user.reload.custom_fields[Maskid::SUBJECT_FIELD]).to eq("msub_linked")
    end
  end

  it "/maskid/webhook rejects garbage without a session" do
    post "/maskid/webhook", params: { payload: "x", signature: "y" }.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    expect(response.status).to eq(422)
  end
end
