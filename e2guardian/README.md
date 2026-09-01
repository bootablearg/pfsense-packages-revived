# E2guardian

Web content filtering for **pfSense CE 2.9 / Plus 26.x**. Filters by the
*content* of a response — phrases, MIME types, file types — and can apply
different policies per user group.

*[Versión en castellano: LEEME.md](LEEME.md)*

Revived from the [e2guardian package by Marcello
Coutinho](https://github.com/marcelloc/Unofficial-pfSense-packages)
(Apache-2.0, 2015-2017), ported to pfSense 2.9 / PHP 8.5 and to e2guardian
5.3.x. The binary comes from FreeBSD's official package repository — no private
repository and no key.

## Status

| Verified | Not yet verified |
|---|---|
| Installs from FreeBSD's repository: **3 packages, 13 MiB**, no pfSense package touched | The GUI screens rendered in a browser |
| **0 known vulnerabilities** in the port (`pkg audit`) | Filtering real traffic end to end |
| All **18 package XMLs** parse with pfSense's own parser | Blacklist download and category filtering |
| `e2guardian.inc` (2394 lines) loads clean under **PHP 8.5** | Chained behind Squid with AD authentication |
| Configuration generator runs and produces a valid `e2guardian.conf` + `e2guardianf1.conf` | pfSense Plus |
| **e2guardian starts and listens** on the configured port | |
| Menu entry and service register correctly | |

## Requirements

* pfSense CE 2.9 (tested) or Plus 26.x (untested).
* ~13 MiB. Far lighter than most proxy stacks — it pulls in only `harfbuzz`
  and `talloc`.
* A proxy in front of it, or transparent mode, depending on your design.

## Install

From the pfSense shell as root:

```sh
fetch -q -o - https://raw.githubusercontent.com/bootablearg/pfsense-packages-revived/main/e2guardian/install.sh | sh -s check
```

`check` changes nothing. Then:

```sh
fetch -q -o - https://raw.githubusercontent.com/bootablearg/pfsense-packages-revived/main/e2guardian/install.sh | sh -s install
```

Then open **Services → E2guardian Proxy**.

Blacklists are **not** downloaded during install — they are large and slow to
fetch. Get them from the package's Blacklist tab when you actually want them.

## The fix that makes it work on 5.3.x

The original package emits `transparenthttpsport` unconditionally. As
e2guardian's own configuration comment says, *defining* that directive is what
enables transparent HTTPS — its mere presence, not its value. Older releases
tolerated it while SSL was off; **5.3.x tries to bind the socket anyway and
aborts at startup**:

```
Error binding server thttps socket: (Address already in use)
```

That message is doubly misleading: the port is free, and it points at a
conflict that does not exist. This package emits the directive only when SSL or
SSL MITM is enabled. Without that change, e2guardian 5.3.4 does not start at
all on a default configuration.

## Where this fits

Worth being clear, so you build the right thing:

| | Filters by | Status |
|---|---|---|
| **pfBlockerNG** | domain and IP (DNS) | official, supported by Netgate |
| **e2guardian** | response content, and per group | third party, this package |

If you only need to block categories of sites, **pfBlockerNG covers most of
that** with official support and no proxy. e2guardian earns its place when you
need to inspect what comes back, or apply different rules to different groups —
which pairs naturally with the [samba-ad](../samba-ad/) package in this
repository for Active Directory authentication.

## Caveats

**The FreeBSD port lags upstream.** FreeBSD ships e2guardian **5.3.4** while
upstream is at 5.5.x. `pkg audit` reports no known vulnerabilities for 5.3.4,
but you are running software a couple of years behind. If that matters for your
threat model, build 5.5.x with poudriere — see
[../docs/PATTERN.md](../docs/PATTERN.md).

**Squid is deprecated.** If you plan to chain e2guardian behind Squid, be aware
Netgate deprecated the Squid package. e2guardian can also run standalone.

**The GUI is the original one.** It works, but it was designed in 2015-2017 and
looks it. Reworking it is a separate job from making it run.

## Uninstall

```sh
./install.sh remove
```

Unregisters the GUI and removes the package files. e2guardian itself and
`/usr/local/etc/e2guardian` are left in place; the script prints the command to
remove them.

## License

Apache-2.0. Copyright © 2015-2017 Marcello Coutinho; © 2026
pfsense-packages-revived contributors. See [LICENSE](LICENSE), which lists the
changes made to the original as Section 4(b) requires.

e2guardian itself is GPLv2 and is not distributed here — it is installed from
FreeBSD's repository.
