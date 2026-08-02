# Application uninstall and recovery

Phase 6 treats site installation and shared code as different states. The default
`site` scope invokes the supported application uninstall lifecycle only on explicit
sites and retains Bench/image code, the Docker manifest, and the current profile.
`remove-unused-code` removes shared code only after inventory proves that no site or
installed dependent still requires it. Frappe is protected; there is no automatic
cascade and no force bypass.

```bash
sudo erpnext-dev app removal-check helpdesk --site one.test
sudo erpnext-dev app uninstall helpdesk --site one.test --scope site --preview
sudo erpnext-dev app uninstall helpdesk --site one.test \
  --scope remove-unused-code --ack-app-data-removal --yes
```

The supported uninstall hook may remove or transform application-owned data;
reinstalling code does not restore it. Mutation requires exact sites and scope plus
the distinct data-removal acknowledgement. Every selected site is backed up and
verified first. Shared-code removal backs up every site and retains a native source
bundle or previous Docker image, manifest, configuration, profile, and service state.

ERPNext site removal retains ERPNext code and the recommended profile. Whole-stack
conversion needs a separate profile acknowledgement:

```bash
sudo erpnext-dev app uninstall erpnext --site one.test \
  --scope erpnext-site --ack-app-data-removal --yes
sudo erpnext-dev stack convert --profile frappe-only \
  --ack-app-data-removal --ack-profile-transition --yes
```

Docker site-only removal does not rebuild. Durable shared-code removal builds and
verifies a cumulative candidate without the app, uninstalls while old code remains,
deploys the replacement, verifies the stack, and only then promotes the manifest.

`operation status ID` is read-only. `operation recover ID --preview` shows the safe
order: restore compatible code/image, exact database and file backups,
configuration/profile, maintenance, original services, then inventory verification.
Automatic restoration remains blocked unless every checkpoint and absence of an
intervening mutation can be proven. Custom-app removal, cascades, manual SQL cleanup,
site deletion, package pruning, and release publication remain out of scope.
