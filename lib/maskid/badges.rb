# frozen_string_literal: true

module ::Maskid
  # One Discourse badge per Mask.ID tier, granted/revoked as the tier moves.
  # Native badges show on the user card, the profile, and as an optional
  # title — no custom UI needed for those surfaces.
  module Badges
    NAMES = {
      "trusted" => "Mask.ID · Trusted",
      "building" => "Mask.ID · Building",
      "low" => "Mask.ID · Low",
    }.freeze

    def self.ensure!
      group = BadgeGrouping.find_by(name: "Mask.ID") ||
        BadgeGrouping.create!(name: "Mask.ID", description: "Verified Mask.ID standing", position: 99)

      NAMES.each do |tier, name|
        next if Badge.exists?(name: name)
        Badge.create!(
          name: name,
          description: I18n.t("maskid.badges.#{tier}.description"),
          badge_type_id: { "trusted" => BadgeType::Gold, "building" => BadgeType::Silver, "low" => BadgeType::Bronze }[tier],
          badge_grouping_id: group.id,
          icon: "shield-halved",
          listable: true,
          enabled: true,
          multiple_grant: false,
          show_posts: false,
          system: false,
          allow_title: tier == "trusted",
        )
      end
    rescue StandardError => e
      Rails.logger.warn("maskid: could not ensure badges: #{e.message}")
    end

    def self.sync!(user, tier)
      ensure!
      NAMES.each do |t, name|
        badge = Badge.find_by(name: name) or next
        ub = UserBadge.find_by(user_id: user.id, badge_id: badge.id)
        if t == tier
          BadgeGranter.grant(badge, user) if ub.nil?
        elsif ub
          BadgeGranter.revoke(ub)
        end
      end
    end

    def self.revoke_all!(user)
      sync!(user, nil)
    end
  end
end
