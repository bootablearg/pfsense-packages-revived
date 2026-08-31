# pfsense-samba-ad

Join a pfSense firewall to an Active Directory domain using Samba's winbind,
with no license key and no proprietary package repository.

*[Versión en castellano: LEEME.md](LEEME.md)*

This is a modernised, freely redistributable derivative of the
[pf2ad](https://github.com/pf2ad/pf2ad) project, branch `2.4.3-SAMBA4`, which
was released by Luiz Gustavo S. Costa under the BSD 2-Clause License. Later
pf2ad releases moved to a commercial model with per-install download keys and a
vendor-hosted binary repository; this project goes back to the BSD-licensed
base and rebuilds it on top of the **official FreeBSD package repository**, so
everything here is free software that anyone can install, inspect and fork.

## Status

Verified working on **pfSense CE 2.9.0-RELEASE** (FreeBSD 16.0-CURRENT,
`FreeBSD:16:amd64`, PHP 8.5.7) with **Samba 4.24.6**.

Joined to a live Samba 4 Active Directory domain and verified end to end.

| Verified | Not yet verified |
|---|---|
| **Domain join succeeds**: `net ads testjoin` → `Join is OK`; the machine account appears in the directory | pfSense Plus (the installer detects it, but it has not been run there) |
| **Trust and winbind**: `wbinfo -t` and `wbinfo -p` both succeed | Real browsers authenticating through the proxy (needs an SPN-covered proxy hostname) |
| **Users and groups resolve** from the directory (`wbinfo -u`, `wbinfo -g`) | Survival across a pfSense upgrade |
| **idmap `rid` maps correctly** into the configured range (uid 10500, 11109, 11111 …) | |
| **Authentication works**: `ntlm_auth --helper-protocol=squid-2.5-basic` returns `OK` — the exact path Squid uses | |
| **Both screens render correctly** in the pfSense web GUI | |
| **Installs from this repository** with the one-line command below, verified on a clean run | |
| **Squid integration**: "Active Directory" appears in the Authentication Method dropdown, and selecting it produces the full set of helper directives plus the `password` ACL | |
| **The Squid patch is reversible**: `revert` restores both package files byte-identically | |
| Kerberos keytab created with `HOST/` and `RestrictedKrbHost/` principals | |
| Samba installs cleanly from the FreeBSD repo (57 packages, no upgrades or replacements of pfSense packages) | |
| `winbindd`, `net`, `ntlm_auth`, `wbinfo` all execute; `ldd` reports no missing libraries | |
| Installer is idempotent across install → remove → install; removal restores the config | |
| Generated `smb4.conf` passes `testparm` (`Loaded services file OK`, `ROLE_DOMAIN_MEMBER`, no warnings) | |
| PHP files lint clean against PHP 8.5.7; XML parses through pfSense's own package parser | |
| The failure path behaves: on a failed join the daemons are **not** started, and the reason is logged | |

## What it does

* Installs Samba (winbind) from the official FreeBSD package repository.
* Adds a **Services → Samba AD** screen to join the firewall to an AD domain.
* Adds a **Diagnostics** screen to test domain membership and troubleshoot.
* Generates `smb4.conf` and `krb5.conf`, performs the join, and creates the
  Kerberos keytab.
* Makes `ntlm_auth` available so Squid *can* authenticate against AD, without
  depending on Squid being installed.

## What it does not do

* **It does not patch the Squid package.** The original rewrote Squid's
  `squid.inc` and `squid_auth.xml` with a diff guarded by a hardcoded MD5 of
  one exact vendor build. That broke on every Squid update and is the single
  most fragile thing it did. Squid integration here is three lines of config
  you paste yourself — see below.
* **It does not turn pfSense into a domain controller.** This joins the
  firewall as a domain *member*. File sharing (`smbd`) is off by default.
* **It does not ship binaries.** Samba comes from FreeBSD's own repository.

## Requirements

* pfSense CE 2.8/2.9 or pfSense Plus 25.x/26.x.
* Around **400 MiB of free space**. Samba pulls in Python and roughly 30
  `py312-*` modules. Check `df -h /` first on appliances with small eMMC.
* Working DNS resolution for your AD domain, and time within five minutes of
  the domain controllers (Kerberos will refuse to authenticate otherwise).

## Two installers

Pick the one that matches what you want:

| | `install.sh` | `install-with-squid.sh` |
|---|---|---|
| Joins the firewall to Active Directory | yes | yes |
| Adds the Samba AD screens | yes | yes |
| Installs the Squid proxy | no | yes |
| Links `ntlm_auth` into Squid | only if Squid is already installed | yes |
| Adds "Active Directory" to Squid's Authentication Method dropdown | no | yes |
| Single sign-on for domain-joined browsers | no | yes |

Use `install.sh` if you only need the firewall in the domain — for example to
authenticate VPN or GUI users against AD. Use `install-with-squid.sh` if you
want an authenticating proxy. The second one calls the first, so you never run
both.

## Install

Run everything from the pfSense shell as root (console option 8, or over SSH).

**Check first — this changes nothing:**

```sh
fetch -q -o - https://raw.githubusercontent.com/bootablearg/pfsense-samba-ad/main/install.sh | sh -s check
```

It prints the detected product, release and ABI, whether a suitable Samba is
available, and what installing it would pull in.

**Then install:**

```sh
fetch -q -o - https://raw.githubusercontent.com/bootablearg/pfsense-samba-ad/main/install.sh | sh -s install
```

Piping a script from the internet into a root shell on a firewall deserves a
second of thought. Read it first if you prefer — it is a few hundred lines and
commented throughout:

```sh
fetch -q -o - https://raw.githubusercontent.com/bootablearg/pfsense-samba-ad/main/install.sh | less
```

**Or from a clone**, which needs no network access for the package files:

```sh
git clone https://github.com/bootablearg/pfsense-samba-ad.git
cd pfsense-samba-ad
chmod +x install.sh install-with-squid.sh
./install.sh check
./install.sh install
```

Then open **Services → Samba AD**, fill in the domain details, and tick
*Enable* to perform the join.

### With the Squid proxy

Same thing, using the other script — it installs Samba AD first, then Squid,
then wires the two together:

```sh
fetch -q -o - https://raw.githubusercontent.com/bootablearg/pfsense-samba-ad/main/install-with-squid.sh | sh -s install
```

It adds an entry to Squid's own **Authentication Method** dropdown:

> *Services → Squid Proxy Server → Authentication → Authentication Method →*
> **Active Directory (Samba winbind SSO)**

Select it and save. Squid then writes the Negotiate, NTLM and Basic helper
directives itself, honouring the existing *Authentication processes*, *prompt*
and *TTL* fields, and creates the `password` ACL that its own access rules
already reference — so **no access rule has to be edited by hand**.

With Negotiate offered first, domain-joined browsers authenticate silently:
users are never prompted for a password.

For that single sign-on to actually happen, clients must reach the proxy by a
**hostname covered by a Kerberos SPN**, not by IP address. Against a bare IP,
browsers fall back to NTLM or to a password prompt.

#### How the dropdown entry gets there, and what that costs you

The dropdown is hardcoded in `squid_auth.xml`, and each method's directives
come from a `switch` in `squid.inc`. Squid offers no hook for adding a method,
so those two package files have to be edited. `pkg/squid_ad_patch.php` does it:

```sh
php /usr/local/pkg/squid_ad_patch.php status   # is it applied?
php /usr/local/pkg/squid_ad_patch.php apply    # apply or repair
php /usr/local/pkg/squid_ad_patch.php revert   # restore Squid's files
```

It finds its anchors by content rather than by line number, is idempotent,
marks what it inserted, and keeps a backup of each file — `revert` restores
them byte for byte.

**Updating or reinstalling the Squid package removes the patch**, because the
package restores its own files. If that happens while the method is still set
to Active Directory, Squid emits no authentication directives at all. Re-run
`apply` after any Squid update, and use `status` if authentication ever stops
being requested.

This is the one part of the project that touches software it does not own. The
original pf2ad did the same with a unified diff guarded by a hardcoded MD5 of
one exact build — which is precisely why it broke on every Squid update.

### Options

| Variable | Purpose |
|---|---|
| `SAMBA_PKG` | Pin a Samba branch instead of the newest, e.g. `SAMBA_PKG=samba423` |
| `SAMBA_AD_SRC_URL` | Base URL for the package files — point it at your own fork or branch |
| `SAMBA_AD_REPO_URL` | Alternative pkg repository, if you build Samba yourself |

```sh
SAMBA_PKG=samba423 ./install.sh install
```

## The screens

Two screens are added, both registered automatically by the installer:

**Services → Samba AD → Settings** (`pkg/samba_ad.xml`)
The screen that joins the firewall to the domain:

| Field | Notes |
|---|---|
| Enable | Unticking stops the daemons but keeps domain membership, so re-enabling needs no rejoin |
| Listen interface(s) | Multi-select. Loopback is always added automatically |
| Domain / Realm | Full DNS name, e.g. `example.local` |
| Workgroup | Short NetBIOS name, e.g. `EXAMPLE` |
| Join Username / Password | Only used for the join and keytab creation |
| idmap backend | `rid` (default) or `ad` — see below |
| idmap ranges | Validated for overlap before anything is written |
| Also run smbd/nmbd | Off by default; only needed to serve SMB shares |
| Log level, Custom options | Passthrough to `smb4.conf` |

**Services → Samba AD → Diagnostics** (`pkg/diag_samba_ad.php`)
Status of winbindd, keytab, the winbind privileged pipe and ntlm_auth, plus
one-click tests: verify domain membership (`net ads testjoin`), ping winbindd,
check the trust secret, show domain info, list the keytab, and validate
`smb4.conf` with `testparm`.

Every diagnostic command is a fixed string; the request only selects which one
to run, so no user input ever reaches a shell.

### A note on the idmap backend

The default is **`rid`**, not `ad`. The `ad` backend requires `uidNumber` and
`gidNumber` attributes to be populated in the directory (RFC2307). Most domains
do not have them, and winbind then silently maps no users at all — a confusing
failure the original invited by defaulting to `ad`. `rid` derives IDs
algorithmically and works against a stock Active Directory. Only choose `ad` if
you know your directory carries POSIX attributes.

## Manual alternative: wiring Squid by hand

Use this if you installed with `install.sh` and do not want anything editing
the Squid package, or if the dropdown patch fails to apply on a future Squid
release. It achieves the same authentication without touching Squid's files.

Install Squid normally (**System → Package Manager**), leave *Authentication
Method* as **None**, and paste this into Squid's *Custom Options (Before
Auth)*:

```
# Kerberos / Negotiate -- preferred. Transparent for domain-joined clients.
auth_param negotiate program /usr/local/libexec/squid/ntlm_auth --helper-protocol=gss-spnego
auth_param negotiate children 20
auth_param negotiate keep_alive on

# NTLM -- fallback for clients that cannot do Kerberos.
auth_param ntlm program /usr/local/libexec/squid/ntlm_auth --helper-protocol=squid-2.5-ntlmssp
auth_param ntlm children 20
auth_param ntlm keep_alive on

# Basic -- last resort. Sends credentials in the clear unless the connection is TLS.
auth_param basic program /usr/local/libexec/squid/ntlm_auth --helper-protocol=squid-2.5-basic
auth_param basic children 5
auth_param basic realm Proxy
auth_param basic credentialsttl 2 hours

acl domain_users proxy_auth REQUIRED
http_access allow domain_users
```

Mind the ordering of access rules: an earlier `allow` wins. If your
configuration already permits the client subnets unconditionally,
authentication is never requested no matter how correct the `auth_param` lines
are — check the generated `/usr/local/etc/squid/squid.conf`. This is the main
reason the dropdown method is easier: there, Squid builds its access rules
around its own `password` ACL for you.

`/usr/local/libexec/squid/ntlm_auth` is a **symlink** to Samba's binary, created
by this package. The original copied the file instead, which went stale on
every Samba update and then failed in ways that looked like domain problems.

Prefer Negotiate over NTLM: Microsoft has moved NTLM to deprecation, and Samba
disables NTLMv1 by default. This package sets `ntlm auth = ntlmv2-only`.

If the Diagnostics screen shows *ntlm_auth linked into Squid: not in use*, you
installed Squid after this package — re-run `./install.sh install` to create
the link.

## Notes and caveats

**OS version mismatch.** pfSense tracks a FreeBSD snapshot slightly behind the
one FreeBSD's official packages are built against. On CE 2.9.0 the userland
reports `1600018` while the packages are built for `1600020`, and `pkg` refuses
the repository by default. The installer sets `IGNORE_OSVERSION=yes`. This was
tested: the ABI matches (`FreeBSD:16:amd64`), the binaries run, and `ldd`
reports no missing libraries. It is nonetheless the one assumption in this
project that could break on a future release — if Samba binaries start
misbehaving after a pfSense upgrade, this is the first thing to check.

**The extra repository is never written into your firewall's configuration.**
It lives in a temporary `REPOS_DIR` used only during install. The original
wrote into `/usr/local/etc/pkg/repos/` and deleted it afterwards; if it died in
between, a third-party repository stayed enabled and could override pfSense
packages later. Here, an interrupted run leaves nothing behind.

**Upgrades.** pfSense major upgrades replace the base system. Expect to re-run
the installer afterwards, and to reinstall Samba for the new ABI. Netgate
recommends removing add-on packages before major upgrades.

**Credentials.** The join account's password is stored in `config.xml`, as with
every pfSense package that needs one. Use a delegated account that can join
computers, not Domain Admin.

## Uninstall

```sh
./install.sh remove
```

This leaves the domain (removing the machine account from the directory),
unregisters the GUI, restores the previous `krb5.conf`, and removes the package
files. Samba itself is left installed; the script prints the command to remove
it.

## Differences from the original pf2ad script

| Original | Here |
|---|---|
| Refused to run unless `/etc/version` matched one exact string | Detects product, release and ABI at runtime |
| Per-install download key against a vendor endpoint | No key; files ship with the project |
| Vendor-hosted binary repository | Official FreeBSD repository |
| Patched Squid via a diff guarded by a hardcoded MD5 | No patching; documented config instead |
| Password interpolated into a shell command (`ps`-visible, injectable) | Mode-0600 credentials file, `escapeshellarg` throughout |
| `killall smbd` / `ps axuw \| grep` | `pkill -x` / `pgrep -x` |
| `foreach` over possibly-absent config arrays (a no-op warning on PHP 8) | `config_get_path()` with defaults |
| `conf_mount_rw()` / `conf_mount_ro()` (removed in pfSense 2.5) | Dropped |
| Copied `ntlm_auth` (goes stale on Samba updates) | Symlink |
| `continue` outside a loop; unused `ARCH` variable | Removed |
| Removal "Not implemented yet" — orphaned machine accounts | `net ads leave` plus full cleanup |
| idmap defaulted to `ad` (fails without RFC2307 attributes) | Defaults to `rid`, ranges validated for overlap |
| RC4/single-DES Kerberos profiles for Windows 2003 | AES only |
| No comments | Commented, with the reasoning for non-obvious choices |

## License

BSD 2-Clause. Copyright (c) 2013-2016 Luiz Gustavo S. Costa; copyright (c) 2026
pfsense-samba-ad contributors. See [LICENSE](LICENSE).

Samba is licensed under the GPLv3 and is not distributed with this project; it
is installed from FreeBSD's package repository at install time.

pfSense is a registered trademark of Rubicon Communications, LLC (Netgate).
This project is not affiliated with or endorsed by Netgate, nor by the pf2ad
project.
