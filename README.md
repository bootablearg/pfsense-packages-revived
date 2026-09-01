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
| **[wpad](wpad/)** | Serves wpad.dat and proxy.pac so browsers find the proxy through DHCP option 252 or DNS, instead of being configured one by one. | Installs and registers on CE 2.9.0; not yet served to a real client |
| **[e2guardian](e2guardian/)** | Web content filtering: inspects response bodies, phrases and MIME types, with per-group policies. | Installs and runs on CE 2.9.0, GUI reviewed in a browser; no real traffic filtered yet |
| **[sarg](sarg/)** | Detailed Squid browsing reports by user, site and date. | Installs and registers on CE 2.9.0, GUI reviewed; reports not yet generated from real traffic |
| **[squidanalyzer](squidanalyzer/)** | Lighter, graph-oriented Squid reports. | Installs and registers on CE 2.9.0, GUI reviewed; reports not yet generated from real traffic |
| **[speedtest](speedtest/)** | Runs a bandwidth test from the firewall itself, with a choice of source address. | Verified on CE 2.9.0: a real measurement runs and is displayed |
| **[ipguard](ipguard/)** | Keeps unlisted hosts off a LAN segment by enforcing a list of permitted MAC/IP pairs. **Works by ARP spoofing — read its README first.** | Installs and registers on CE 2.9.0; **has never actually guarded a segment** |
| **[postfix](postfix/)** | Mail gateway and forwarder (SMTP, antispam, relay). | Installs and registers on CE 2.9.0, GUI reviewed; **no mail has been passed through it** |
| **[mailscanner](mailscanner/)** | Mail filtering with SpamAssassin and ClamAV. Needs an MTA (postfix). | Installs and registers on CE 2.9.0; **no mail has been passed through it** |

More are planned. See [docs/PATTERN.md](docs/PATTERN.md) for how a package gets
added, and the per-package README for install instructions.

## Install

Each package installs on its own. From the pfSense shell as root:

```sh
fetch -q -o - https://raw.githubusercontent.com/bootablearg/pfsense-packages-revived/main/samba-ad/install.sh | sh -s check
```

`check` reports what it would do and changes nothing. Read each package's
README before installing — they carry their own requirements and caveats.

## Uninstalling

Each installer builds a real `pfSense-pkg-*` package and installs it, so these
behave like any other pfSense package: they are listed under **System →
Package Manager → Installed Packages**, and the trash icon removes them
properly — files, menu entries, service, privileges and the `config.xml` entry.

Anything the installer pulled in from FreeBSD's repository goes too. Whatever
was already on the box before is left alone.

The command line does the same thing:

```sh
./install.sh remove
```

How that is wired up, and the several ways it can go quietly wrong, is written
down in [docs/PACKAGING.md](docs/PACKAGING.md).

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
| [wpad](wpad/LICENSE) | Apache-2.0 | © 2017-2025 Marcello Coutinho |
| [speedtest](speedtest/LICENSE) | Apache-2.0 + BSD 2-Clause | © 2019 Marcello Coutinho, © 2015 ESF LLC, © 2004-2018 Netgate |
| [ipguard](ipguard/LICENSE) | BSD 2-Clause | © 2012-2017 Marcello Coutinho, © 2015 ESF, LLC |

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
