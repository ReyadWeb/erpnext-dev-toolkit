# Frappe-aligned frontend assets

How ERPNext/Frappe serve login CSS/JS, how this toolkit differs, and how to
diagnose an unstyled login page **before** changing nginx heuristics.

Official references:

- [Create a Site](https://docs.frappe.io/framework/user/en/tutorial/create-a-site) — `http://{site}:8000`, Host = site name
- [Setup Production](https://docs.frappe.io/framework/user/en/bench/guides/setup-production) — nginx serves static files; proxies app
- Bench nginx template: `bench/config/templates/nginx.conf` (`location /assets { try_files $uri =404; }` with `root` = `sites/`)
- Asset hash cache: Redis key `assets_json` ([frappe#29901](https://github.com/frappe/frappe/issues/29901))
- Incomplete builds / OOM: ([frappe#33468](https://github.com/frappe/frappe/issues/33468))

---

## Official vs toolkit matrix

| Topic | Official development | Official production | Toolkit (native) before this alignment | Target after alignment |
|-------|---------------------|---------------------|----------------------------------------|-------------------------|
| Process | `bench start` | supervisor + gunicorn | Local: systemd → `bench start`; production: `bench setup supervisor` | Unchanged |
| Assets served by | Werkzeug on `:8000` | **Nginx from `sites/assets`** | Hand-written nginx **proxied all `/` to `:8000`** (no disk `/assets`) | Nginx **`location /assets` from disk** (Frappe contract) + proxy app |
| Nginx config source | n/a | `bench setup nginx` → `config/nginx.conf` | Toolkit-written sites under `/etc/nginx` | Toolkit still owns TLS; **static path matches Frappe** |
| Canonical browser URL | `http://SITE:8000` | `:80` / `:443` via generated nginx | `https://SITE` and/or `:8000` | **Local primary: `:8000`**; HTTPS optional after assets OK |
| After `bench build` | `clear-cache` | same + nginx sees new files | `clear-cache` only | `clear-cache` + website-cache + explicit `assets_json` eviction |
| Build completeness | Disk under `sites/assets` | same | Install checked `website.bundle` only | Also `login.bundle` + `erpnext-web.bundle` |

---

## Phase B — nginx model diff

### Official (`bench setup nginx` template)

```nginx
root {{ sites_path }};   # typically .../frappe-bench/sites

location /assets {
    try_files $uri =404;
    add_header Cache-Control "max-age=31536000";
}

location / {
    try_files /{{ site_name }}/public/$uri @webserver;
}

location @webserver {
    proxy_pass http://…-frappe;   # gunicorn :8000
    proxy_set_header Host $host;
    proxy_set_header X-Frappe-Site-Name {{ site_name }};
}
```

HTTP→HTTPS redirect is a separate `listen 80` server when SSL is enabled.

### Toolkit (historical)

- `root` / `location /assets` **absent**
- `location / { proxy_pass http://127.0.0.1:8000; }` for both local SSL and production TLS
- Assets only worked when the **app server** could serve them; bare `:80` without redirect could diverge from verified `:443`/`:8000`

### Alignment choice

Keep toolkit TLS/cert/firewall ownership, but add Frappe-style **disk `/assets`** on every toolkit nginx server block that fronts the site. Do not assume proxy-everything equals `bench setup nginx`.

---

## Phase A — official `:8000` baseline (procedure)

Run on a clean local VM **before** trusting HTTPS:

```bash
sudo erpnext-dev frappe-asset-checklist
# or:
sudo bash /opt/erpnext-dev/current/scripts/frappe-frontend-asset-checklist.sh
```

Manual steps:

1. Ensure ERPNext is running (`sudo erpnext-dev start` / `wait-ready`).
2. Prefer **no** reliance on bare `http://SITE` — open from the **host**:
   `http://SITE:8000/login` (correct `/etc/hosts`, hard refresh).
3. Confirm disk bundles exist under `sites/assets/frappe/dist/css/` and
   `sites/assets/erpnext/dist/css/`.
4. Confirm HTML bundle names match files on disk (stale `assets_json` if not).

**Success:** styled login on `:8000` without toolkit nginx. If that fails, the bug is Frappe build/cache/Host — not port 80.

### Phase A result (field synthesis, Debian local VM, v1.19.8)

| Check | Result |
|-------|--------|
| `bench build` after “Assets for Release … don't exist” | Produced new hashed CSS/JS on disk |
| Toolkit probe `:8000` / `:443` after rebuild | HTTP 200 for login CSS/JS |
| Host browser bare `http://SITE` (:80) | Unstyled; same hashes 404 |
| Classification | Primary: **incomplete post-install build** then fixed by rebuild; secondary: **wrong entry URL / non-Frappe `:80` path**. Official `:8000` was the correct first browser URL. |

---

## Phase C — field classification ladder

Run on the broken VM (read-only first):

```bash
sudo erpnext-dev frappe-asset-checklist
```

Classify in order:

1. **Incomplete build** — missing `login.bundle.*.css` / `website.bundle.*.css` on disk; dmesg OOM; log “Assets for Release don’t exist” without a completed yarn build.
2. **Stale `assets_json`** — HTML references hashes not on disk (or opposite after rebuild without cache clear). Bench cache is **`redis://127.0.0.1:13000`** — `redis-cli` without `-p 13000` is the wrong instance. Also compare `sites/assets/assets.json` to files under `sites/assets/*/dist/`.
3. **Host / DNS** — raw IP or wrong `/etc/hosts`; Host header ≠ site name.
4. **Permissions** — files exist but not readable by nginx/frappe user.
5. **Wrong entry URL** — bare `http://SITE` while only `:8000` / HTTPS proxy is valid.
6. **Static route failure** — file on disk, HTTP 404 through nginx (missing disk `/assets` location).

Do **not** treat “toolkit ready OK” as proof the host browser path is correct until this ladder passes.

---

## Operator ladder (if login is unstyled)

1. Open **`http://SITE:8000/login`** (Frappe dev contract). Hard refresh.
2. `sudo erpnext-dev frappe-asset-checklist`
3. `sudo erpnext-dev repair-frontend-assets` (build + clear-cache + assets_json + restart)
4. If using HTTPS: `https://SITE/login` only after checklist says disk + `:8000` OK
5. `sudo erpnext-dev configure-local-ssl` if `:80` should 301 to HTTPS
6. `sudo erpnext-dev support-bundle`

### Fresh local install — check before and after HTTPS

On a clean VM (guided local quickstart):

1. **Before HTTPS:** after install/`wait-ready`, open **`http://SITE:8000/login`** — must be styled.
2. Accept trusted mkcert when prompted. The toolkit **auto-settles** (ERPNext + nginx restart + `wait-ready`) before printing `https://` URLs — do not treat that bounce as optional.
3. **After HTTPS:** open **`https://SITE/login`** (hard refresh). Must match the `:8000` look. A full VM reboot should not be required.

---

## Related toolkit commands

| Command | Role |
|---------|------|
| `frappe-asset-checklist` | Frappe-first disk / OOM / `:8000` / Host checks |
| `verify-frontend-assets` | Live HTTP GET of every `/login` CSS/JS |
| `repair-frontend-assets` | `bench build` + cache/`assets_json` + restart |
| `doctor` | Includes frontend asset disk + RAM summary |
| `wait-ready` | Ports + HTTP + asset probe (+ one auto-rebuild) |
