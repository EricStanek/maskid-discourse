# Mask.ID for Discourse

Let your members prove they are an **established, reputation-backed person** —
without an email, a phone number, or handing you any personal data. A member
links their [Mask.ID](https://mask.id) from their profile; your forum receives
a **tier** (Trusted / Building / Low) and a pairwise reference code, nothing
else. The plugin then:

- shows a **Mask.ID badge** on the member's profile and user card (native
  Discourse badges, one per tier), and a **tier icon** beside their name on
  posts;
- grants a **trust-level floor by tier** — e.g. a Trusted Mask.ID starts at
  TL2 instead of serving the new-user restrictions — never a ceiling, and
  never touching staff or manually locked levels;
- **re-reads** each linked member's tier periodically, so a revoked or
  deleted Mask.ID unlinks and a tier change moves the badge.

What your forum never receives: the member's Mask.ID username, wallet
address, referral graph, or any profile content. The reference code is
meaningless on any other site. See the
[integration guide](https://app.mask.id/api) for the exact contract.

## Install

Self-hosted Discourse: add the plugin to `containers/app.yml` and rebuild.

```yaml
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          - git clone https://github.com/discourse/docker_manager.git
          - git clone https://github.com/EricStanek/maskid-discourse.git
```

```
cd /var/discourse && ./launcher rebuild app
```

Then **Admin → Settings → Plugins → maskid**: tick *maskid enabled*. The
platform key is fetched once from `https://app.mask.id/.well-known/maskid-attest-key`
and pinned (key id `cdde5c8d68dbb162`); no API key is needed during the pilot.

Discourse's hosted plans allow third-party plugins only on the higher tiers;
self-hosted instances install anything.

## Settings

| setting | default | meaning |
|---|---|---|
| `maskid trust level trusted` | 2 | floor for the Trusted tier |
| `maskid trust level building` | 1 | floor for the Building tier |
| `maskid trust level low` | 0 | floor for the Low tier |
| `maskid refresh days` | 1 | how often a linked member's tier is re-read |
| `maskid show poster icon` | on | tier icon beside the name on posts |
| `maskid host` | `https://app.mask.id` | only change for a test instance |
| `maskid key id` / `maskid public key` | prod key / fetched | the pinned platform key |

## How it works

1. Member clicks **Link my Mask.ID** on their profile → `/maskid/start` mints a
   single-use nonce and sends them to Mask.ID's consent page with this
   forum's request (`rp_user_id`, `nonce`, `redirect`, `webhook`).
2. The member reviews exactly what will be shared and approves it with their
   wallet.
3. Mask.ID sends a platform-signed response — to the member's browser
   (`/maskid/return?maskid=<payload>.<signature>`) and to `/maskid/webhook`.
   The plugin verifies one Ed25519 signature over the raw payload bytes
   against the pinned key, checks the nonce (ours, unused), the user, and the
   host, then stores the tier.
4. Every `maskid refresh days`, a scheduled job re-reads
   `GET /api/attest/v1/subject/<code>`; a 404 unlinks.

Your forum's host must be reachable over HTTPS for the webhook; the redirect
path works on its own (including on a local dev instance).

## Development

Runs against Discourse's standard dev container. Symlink this repo into
`plugins/`, `d/shutdown_dev; d/boot_dev`, then `d/rspec plugins/maskid/spec`.
Point `maskid host` at a local Mask.ID (`http://localhost:4000`) to exercise
the full loop offline.

## License

MIT.
