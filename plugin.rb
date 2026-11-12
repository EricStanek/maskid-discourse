# frozen_string_literal: true

# name: maskid
# about: Let members prove they are an established Mask.ID identity — badge, poster icon, and a starting trust level by tier. No email, no phone, no personal data.
# version: 0.3.0
# authors: Mask.ID
# url: https://mask.id/works-with
# required_version: 3.3.0

enabled_site_setting :maskid_enabled

register_asset "stylesheets/maskid.scss"
register_svg_icon "shield-halved"

module ::Maskid
  PLUGIN_NAME = "maskid"

  # user.custom_fields keys (all written only by this plugin)
  SUBJECT_FIELD = "maskid_subject_id"
  TIER_FIELD = "maskid_tier"
  INDEX_FIELD = "maskid_trust_index"
  VERIFIED_AT_FIELD = "maskid_verified_at"
  CHECKED_AT_FIELD = "maskid_checked_at"
  REPORTED_AT_FIELD = "maskid_reported_at"

  TIERS = %w[trusted building low unproven].freeze
end

require_relative "lib/maskid/engine"

after_initialize do
  # Mount the engine the way core plugins do: appended into the main route
  # set when it loads (a file-level routes.draw gets clobbered).
  Discourse::Application.routes.append { mount ::Maskid::Engine, at: "/maskid" }

  # lib/ is on the engine's autoload path — Maskid::Key, ::Attestation,
  # ::Badges, ::Apply load on first reference (no require_relative, or they
  # load twice and warn).

  # Custom fields: typed, and the tier is public so it can ride on posts and
  # user cards. The subject id stays private (it is the site's own
  # cross-reference — meaningless elsewhere, but still not for display).
  register_user_custom_field_type(Maskid::SUBJECT_FIELD, :string)
  register_user_custom_field_type(Maskid::TIER_FIELD, :string)
  register_user_custom_field_type(Maskid::INDEX_FIELD, :integer)
  register_user_custom_field_type(Maskid::VERIFIED_AT_FIELD, :string)
  register_user_custom_field_type(Maskid::CHECKED_AT_FIELD, :string)
  register_user_custom_field_type(Maskid::REPORTED_AT_FIELD, :string)
  allow_public_user_custom_field(Maskid::TIER_FIELD)
  allow_public_user_custom_field(Maskid::INDEX_FIELD)

  # Posts: the tier next to the poster's name (the JS poster icon reads it).
  add_to_serializer(:post, :maskid_tier, include_condition: -> { SiteSetting.maskid_enabled }) do
    object.user&.custom_fields&.[](Maskid::TIER_FIELD)
  end

  # The signed-in member's own status (the profile connector reads it).
  add_to_serializer(:current_user, :maskid_tier) do
    object.custom_fields[Maskid::TIER_FIELD]
  end
  add_to_serializer(:current_user, :maskid_trust_index) do
    object.custom_fields[Maskid::INDEX_FIELD]
  end

  # Write-back: a linked member signing in = one "session" report per day
  # (counts only; Mask.ID never learns which site).
  on(:user_logged_in) do |user|
    Maskid::Report.session!(user) if SiteSetting.maskid_enabled
  end

  # Make sure the badges exist once the plugin is on.
  Maskid::Badges.ensure!
end
