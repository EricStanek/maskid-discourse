import { apiInitializer } from "discourse/lib/api";
import { i18n } from "discourse-i18n";

// The tier icon beside a linked member's name on their posts. The post
// serializer carries `maskid_tier` (a plugin-owned public custom field).
export default apiInitializer("1.8.0", (api) => {
  const settings = api.container.lookup("service:site-settings");
  if (!settings.maskid_enabled || !settings.maskid_show_poster_icon) {
    return;
  }

  api.addPosterIcon((_cfs, attrs) => {
    const tier = attrs.maskid_tier;
    if (!tier || tier === "unproven") {
      return;
    }
    return {
      icon: "shield-halved",
      className: `maskid-poster-icon maskid-tier-${tier}`,
      title: i18n(`maskid.poster_icon.${tier}`),
    };
  });
});
