# Interactive installation profiles

Every fresh interactive installation has an explicit mode and confirmation
boundary. **Quick installation** selects the backward-compatible
`recommended` profile and states that Frappe and ERPNext will both be installed.
**Advanced installation** asks for `recommended` or `frappe-only`, then asks for
Native or Docker. Frappe-only installs Frappe without fetching, installing, or
including ERPNext; ERPNext can later be added through the verified
`app install erpnext --site SITE` App Management operation.

Before saving settings, the wizard displays the setup target, mode, site/domain,
engine, profile, Frappe action, ERPNext action, and Docker environment when
applicable. Back, Quit, or a negative answer leaves the existing configuration
unchanged and performs no installation or network mutation. Confirmed settings
are written by atomic replacement before the selected Native or Docker adapter
runs.

Profile precedence is: a valid explicit `--profile`; a selection made in the
current wizard; a valid saved profile when saved configuration is being reused;
then `recommended` only as the non-interactive compatibility default. Invalid
values stop before configuration or deployment changes.

Existing managed installations do not enter the fresh-profile selector. The
Toolkit displays and preserves their current profile. Changing a recommended
stack to Frappe-only is the separate protected `stack convert` lifecycle, not an
installer setting. Legacy v1.20.4 configurations without `INSTALLATION_PROFILE`
retain the historical recommended Frappe + ERPNext interpretation; read-only and
maintenance commands do not rewrite that configuration merely to add the field.

Both profiles are supported by Native, Docker development, and Docker production.
Docker production uses the profile-aware cumulative immutable manifest: ERPNext
is required for recommended and absent for Frappe-only.
