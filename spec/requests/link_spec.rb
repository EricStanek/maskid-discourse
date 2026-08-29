# frozen_string_literal: true

require "rails_helper"

RSpec.describe Maskid::LinkController do
  fab!(:user)

  before { SiteSetting.maskid_enabled = true }

  it "/maskid/start requires login" do
    get "/maskid/start"
    expect(response.status).to eq(403).or eq(302)
  end

  it "/maskid/start sends the member to Mask.ID with a request naming this forum" do
    sign_in(user)
    get "/maskid/start"
    expect(response.status).to eq(302)
    uri = URI(response.location)
    expect(uri.host).to eq(URI(SiteSetting.maskid_host).host)
    c = Rack::Utils.parse_query(uri.query)["c"]
    req = JSON.parse(Base64.urlsafe_decode64(c + "=" * ((4 - c.length % 4) % 4)))
    expect(req["rp_user_id"]).to eq("u_#{user.id}")
    expect(req["redirect"]).to end_with("/maskid/return")
    expect(req["webhook"]).to end_with("/maskid/webhook")
    expect(req["nonce"]).to be_present
  end

  it "/maskid/webhook rejects garbage without a session" do
    post "/maskid/webhook", params: { payload: "x", signature: "y" }.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    expect(response.status).to eq(422)
  end
end
