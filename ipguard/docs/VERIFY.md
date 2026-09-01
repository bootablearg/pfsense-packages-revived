# Verification checklist — ipguard

What was actually run, on a real pfSense box, and what is still open.

## Environment

| | |
|---|---|
| Product | pfSense CE 2.9.0-RELEASE |
| ABI | `FreeBSD:16:amd64` |
| PHP | 8.5.7 |
| ipguard | 1.04_5, from FreeBSD's repository |

## Done

### 1. The install-time crash, reproduced and fixed

The package's resync command runs at install time, before any configuration
exists. Called in that state, the original aborts:

```sh
php -r 'require_once("config.inc"); require_once("util.inc");
        require_once("service-utils.inc"); require_once("interfaces.inc");
        require_once("ipguard.inc"); ipguard_custom_php_write_config();'
```

| | result |
|---|---|
| original | `count(): Argument #1 ($value) must be of type Countable|array, null given` |
| this package | terminates without error |

Both files pass `php -l`. The failure only appears when the function runs,
which is why linting the whole repository said nothing about it.

### 2. Install and registration

```
pfSense-pkg-IPguard            1.1.0
menu: IPguard                  Services
```

The binary installs from FreeBSD's repository, and the package appears in
System > Package Manager.

## Changed, and why

Beyond the crash above, two defects in the original logic:

- The service started only when `$ipguard['enable']` was true, where `$ipguard`
  was whatever the preceding `foreach` left behind -- the last entry in the
  list. A disabled entry at the bottom kept ipguard down regardless of how many
  enabled entries preceded it. Entries only reach the config array when they
  are enabled, so counting them is the whole test.
- Each per-interface config file was written twice with identical content, the
  first result discarded.

The pfSense 2.2 PBI symlink workaround was dropped: PBI was retired with
pfSense 2.3 in 2016 and `/usr/pbi` does not exist on any supported release.

## Open

### A. It has never guarded anything

**No host has been permitted or blocked by this.** The daemon has not been
started against a real segment, no ARP replies have been observed, and the
effect on a host missing from the list has not been seen. This is the test that
matters and it has not been done.

### B. Multiple interfaces

The code starts one daemon per configured interface. Only the single-interface
path has been reasoned about; none has been run.

### C. What it does to the firewall's own traffic

ipguard answers ARP on a segment the firewall is also on. Whether it can
interfere with the firewall's own neighbours -- or with CARP, if a pair is in
use -- has not been investigated. Do not put this on a CARP cluster without
testing that first.

### D. pfSense Plus

Untested.
