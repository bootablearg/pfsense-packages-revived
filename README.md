# pfsense-packages-revived

Add-on packages for **pfSense CE 2.9 / Plus 26.x**, rebuilt from abandoned or
paywalled originals so they install from free software only — no license keys,
no vendor-hosted binary repositories.

*[Versión en castellano: LEEME.md](LEEME.md)*

Netgate has removed a lot of packages from the official repository over the
years, and several community packages stopped being maintained around pfSense
2.4. The code is often still there and still openly licensed — it just does not
run on a modern pfSense any more: PHP 8 broke it, APIs were removed, and the
binaries it depended on were never rebuilt for the current ABI.

This repository revives them one at a time, with the same method each time:
port the GUI to the current PHP and pfSense APIs, and install the binaries from
**FreeBSD's official package repository** instead of a private one.

## Packages

| Package | What it does | Status |
|---|---|---|
| **[samba-ad](samba-ad/)** | Joins the firewall to an Active Directory domain (Samba/winbind). Optional Squid integration with single sign-on. | Verified end to end on CE 2.9.0 against a live AD |
| **[e2guardian](e2guardian/)** | Web content filtering: inspects response bodies, phrases and MIME types, with per-group policies. | Installs, generates config and starts on CE 2.9.0; GUI screens not yet reviewed |
| **[sarg](sarg/)** | Detailed Squid browsing reports by user, site and date. | Installs and registers on CE 2.9.0; reports not yet generated from real traffic |
| **[squidanalyzer](squidanalyzer/)** | Lighter, graph-oriented Squid reports. | Installs and registers on CE 2.9.0; reports not yet generated from real traffic |
| **[postfix](postfix/)** | Mail gateway and forwarder (SMTP, antispam, relay). | Code verified and install plan resolves on CE 2.9.0; **not yet run on a live system** |
| **[mailscanner](mailscanner/)** | Mail filtering with SpamAssassin and ClamAV. Needs an MTA (postfix). | Code verified and install plan resolves on CE 2.9.0; **not yet run on a live system** |

More are planned. See [docs/PATTERN.md](docs/PATTERN.md) for how a package gets
added, and the per-package README for install instructions.

## Install

Each package installs on its own. From the pfSense shell as root:

```sh
fetch -q -o - https://raw.githubusercontent.com/bootablearg/pfsense-packages-revived/main/samba-ad/install.sh | sh -s check
```

`check` reports what it would do and changes nothing. Read each package's
README before installing — they carry their own requirements and caveats.

## Licensing

**Each package keeps the license of the work it derives from**, in its own
directory. There is deliberately no single license at the root, because these
come from different authors under different terms:

| Package | License | Derived from |
|---|---|---|
| [samba-ad](samba-ad/LICENSE) | BSD 2-Clause | pf2ad, © 2013-2016 Luiz Gustavo S. Costa |
| [e2guardian](e2guardian/LICENSE) | Apache-2.0 | Unofficial-pfSense-packages, © 2015-2017 Marcello Coutinho |
| [sarg](sarg/LICENSE) | BSD 2-Clause | © 2007 Joao Henrique F. Freitas, © 2012-2024 Marcello Coutinho, © 2015 ESF, LLC |
| [squidanalyzer](squidanalyzer/LICENSE) | Apache-2.0 | © 2016 Luiz Gustavo, © 2017 Marcello Coutinho |
| [postfix](postfix/LICENSE) | Apache-2.0 | © 2011-2021 Marcello Coutinho |
| [mailscanner](mailscanner/LICENSE) | Apache-2.0 | © 2011-2019 Marcello Coutinho |

Original copyright notices are preserved as those licenses require. If you fork
this, keep them.

## What "revived" means here

Every package in this repository has been:

- **ported** to the PHP and pfSense APIs of the target release, not merely
  copied — removed functions replaced, PHP 8 breakage fixed, injection points
  closed;
- **installed from free sources only** — binaries come from FreeBSD's official
  repository, so there is no key to buy and no third-party repository to trust;
- **actually run** on a real pfSense box, with the results written down in the
  package's `docs/VERIFY.md`, including what was *not* tested.

If something is untested, it says so. Nothing here claims to work because it
looks like it should.

## Trademarks

pfSense is a registered trademark of Rubicon Communications, LLC (Netgate).
This project is not affiliated with or endorsed by Netgate.
