# Verification checklist

What has actually been tested, how to reproduce it, and what is still open.
Nothing here is aspirational: every item marked done was run on a real pfSense
box against a real Active Directory domain.

Hostnames, IP addresses, domain names and usernames below are examples
substituted for the real ones used during testing.

## Environment used

| | |
|---|---|
| Product | pfSense CE 2.9.0-RELEASE |
| Kernel | FreeBSD 16.0-CURRENT (userland `1600018`) |
| ABI | `FreeBSD:16:amd64` |
| PHP | 8.5.7 |
| Samba | 4.24.6 (`samba424`, from FreeBSD's repository) |
| Directory | Samba 4 AD domain controller |

## Done

### 1. Samba availability and installation

```sh
pkg config abi                       # -> FreeBSD:16:amd64
pkg search -q samba                  # -> empty: not in the pfSense repo
```

FreeBSD publishes `samba416` through `samba424` for this exact ABI. `pkg`
initially refuses the repository:

```
- package: 1600020
- running userland: 1600018
pkg: repository FreeBSD-ports contains packages for wrong OS version
```

With `IGNORE_OSVERSION=yes`, the dry run reports **57 packages to install, no
upgrades, no reinstalls, no removals** — Samba does not disturb any pfSense
package. Cost: 408 MiB on disk, 79 MiB downloaded.

### 2. Binaries actually run

```sh
winbindd --version    # -> Version 4.24.6
net --version         # -> Version 4.24.6
ntlm_auth --version   # -> Version 4.24.6
ldd /usr/local/sbin/winbindd | grep "not found"   # -> nothing
ldd /usr/local/bin/ntlm_auth | grep "not found"   # -> nothing
```

This is the key result: the userland mismatch does not prevent execution.

### 3. Code validity

```sh
php -l pkg/samba_ad.inc         # -> No syntax errors detected
php -l pkg/diag_samba_ad.php    # -> No syntax errors detected
sh -n install.sh                # -> clean
```

pfSense's own package parser reads the XML:

```php
parse_xml_config_pkg('/usr/local/pkg/samba_ad.xml', 'packagegui');
// -> 18 fields, title "Samba AD: Domain Membership"
```

### 4. Installer

```sh
./install.sh check
```

```
Product : pfSense
Version : 2.9.0-RELEASE
ABI     : FreeBSD:16:amd64
Samba   : installed (samba424-4.24.6)
Squid   : not installed (not required)
Package : not installed
```

After `./install.sh install`, the configuration contains the menu entry and the
service. `install.sh remove` reverses both, and reinstalling is idempotent.

### 5. Generated configuration is valid to Samba

```sh
testparm -s /usr/local/etc/smb4.conf
```

```
Loaded services file OK.
Server role: ROLE_DOMAIN_MEMBER
```

No warnings. Notes:

* Interface resolution works: selecting an interface with no IPv4 address logs
  a warning and skips it rather than emitting a broken `interfaces` line.
* `sync machine password to keytab` is emitted only on Samba >= 4.24. Older
  branches get `kerberos method = secrets and keytab`. Using the old parameter
  on 4.24 makes `testparm` print a deprecation suggestion; the version check
  keeps the generated config clean either way.
* No `password server` is emitted even when a controller is pinned: `testparm`
  rejects combining it with `security = ADS`.

### 6. Input validation

Overlapping idmap ranges are rejected before anything is written:

```
The Default and Domain idmap ranges overlap. Give each backend its own range.
```

### 7. Domain join against a live Active Directory

Joined through the package's own `samba_ad_sync()` — the same code path the GUI
runs when you save the form.

```sh
net ads testjoin -s /usr/local/etc/smb4.conf
# -> Join is OK

wbinfo -t
# -> checking the trust secret for domain EXAMPLE via RPC calls succeeded

wbinfo -p
# -> Ping to winbindd succeeded

wbinfo -u        # -> domain users listed
wbinfo -g        # -> domain admins, domain controllers, schema admins, ...

klist -k /etc/krb5.keytab
# -> HOST/PFSENSE.example.local@EXAMPLE.LOCAL
#    RestrictedKrbHost/PFSENSE.example.local@EXAMPLE.LOCAL
```

idmap with the `rid` backend maps into the configured 10000-69999 range:

```
administrator -> 10500    someuser -> 11109    otheruser -> 11111
```

Confirmed independently from the directory side: the machine account appears at
`CN=PFSENSE,CN=Computers,DC=example,DC=local` with `sAMAccountName: PFSENSE$`,
`userAccountControl: 4096` (workstation trust account), `dNSHostName:
pfsense.example.local`, the four expected SPNs, and
`msDS-SupportedEncryptionTypes: 28` (AES256 + AES128 + RC4) — so the AES-only
Kerberos profile this package writes is what the account actually negotiates.

### 8. Authentication through the Squid helper path

The exact helper protocol Squid uses:

```sh
echo "administrator <password>" | ntlm_auth --helper-protocol=squid-2.5-basic
# -> OK

ntlm_auth --username=administrator --password=<password> --domain=EXAMPLE
# -> : (0x0)   i.e. NT_STATUS_OK
```

### 9. Failure path

Observed in `/var/log/system.log` from an attempt without valid credentials:

```
ERROR Samba AD: daemons not started because the domain join failed.
```

The daemons are deliberately left stopped when a join fails, rather than
running a winbindd that cannot reach its domain.

### 10. Service integration

pfSense reports the package's service as its own, so it appears under
**Status → Services** with working start/stop/restart controls:

```
Servicio: sambaad | rcfile: samba_ad.sh | executable: winbindd
state according to pfSense: RUNNING
```

## A note on DNS

During testing the firewall's resolver returned NXDOMAIN for
`_ldap._tcp.<domain>` and `_kerberos._tcp.<domain>`, although the domain name
itself resolved. Kerberos cannot locate the KDC without those SRV records, and
the join fails.

That is what the optional **Domain controller** field exists for: it pins the
KDC in `krb5.conf` under `[realms]` and passes `-S` to `net`, and the join then
succeeds without touching the firewall's DNS configuration.

The tidier fix in production is a Domain Override in the DNS Resolver
(**Services → DNS Resolver → Domain Overrides**) pointing the AD zone at a
domain controller, so the whole zone resolves normally.

### 11. Both screens render in the web GUI

**Services → Samba AD** appears in the menu, and both the Settings form and the
Diagnostics tab render correctly in the pfSense web interface.

### 12. Installation from the public repository

Verified on the LAB by fetching straight from GitHub, exactly as a third party
would:

```sh
fetch -q -o - https://raw.githubusercontent.com/bootablearg/pfsense-samba-ad/main/install.sh | sh -s check
```

The script runs identically whether executed from a clone or piped from the
network, and the package files download complete. The files served by
raw.githubusercontent contain 0 CR bytes, so the LF line endings enforced by
`.gitattributes` survive publication — a CRLF in `install.sh` would make
FreeBSD fail with "bad interpreter".

### 13. The Squid installer and the Authentication Method patch

`install-with-squid.sh` was run against Squid `pfSense-pkg-squid-0.5.11`.

The patch adds one dropdown option and one `switch` case. The Squid package
already accepts `ntlm` as a method everywhere else — `squid.inc:845`,
`squid_auth.xml:286` and `squid_js.inc:38` all match
`(local|ldap|radius|ntlm)` — which is why the value must stay `ntlm` and why
the insertion can be this small.

After `apply`:

* `php -l /usr/local/pkg/squid.inc` — still valid PHP.
* `parse_xml_config_pkg()` reads the patched `squid_auth.xml` — 21 fields.
* The option appears in the dropdown, wrapped in its markers.

Selecting it and saving produces, in `squid.conf`:

```
auth_param negotiate program /usr/local/libexec/squid/ntlm_auth --helper-protocol=gss-spnego
auth_param negotiate children 15
auth_param negotiate keep_alive on
auth_param ntlm program /usr/local/libexec/squid/ntlm_auth --helper-protocol=squid-2.5-ntlmssp
auth_param ntlm children 15
auth_param ntlm keep_alive on
auth_param basic program /usr/local/libexec/squid/ntlm_auth --helper-protocol=squid-2.5-basic
auth_param basic children 15
auth_param basic realm Proxy corporativo
auth_param basic credentialsttl 5 minutes
acl password proxy_auth REQUIRED
```

The GUI's own *Authentication processes* (set to 15) and *prompt* fields are
honoured, and the `password` ACL — which the package's access rules already
reference — is created by the package itself. `squid -k parse` accepts the
result.

* **Idempotent**: applying twice leaves exactly one marked block in each file.
* **Reversible**: after `revert`, `diff` reports both files byte-identical to
  the backups taken before patching, and `squid.inc` still lints clean.

Two `ERROR` lines in `squid -k parse` output — `dns_v4_first is obsolete` and
the `/var/squid/cache` cache type — come from the pfSense Squid package's own
defaults, not from this patch.

No `http_access` rule referencing the `password` ACL appears in the test box's
`squid.conf` because Squid itself is disabled there, with no interfaces or
allowed subnets configured; the package only emits its base rules in that
state.

Not exercised end to end: a real browser authenticating through the proxy with
Kerberos, which needs clients and an SPN-covered proxy hostname.

## Open

### A. pfSense Plus

The installer detects Plus (`$g['product_name']`) but has not been run on it.
Plus 26.07 shares its FreeBSD base commit with CE 2.9.0, so the same packages
should apply; other Plus releases track different snapshots and need their own
check of the userland version.

### C. Squid end-to-end

`ntlm_auth` authenticates correctly against the domain, but a full run with
Squid installed — clients authenticating transparently through the proxy via
Negotiate — has not been done.

### D. Survival across a pfSense upgrade

Confirm behaviour after a minor upgrade, and document what has to be re-run.

### E. Target OU for the machine account

The account is created in the default `CN=Computers` container. Environments
that require a specific OU would need `createcomputer=` passed to the join.
