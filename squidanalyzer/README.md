# SquidAnalyzer

Per-user reports from Squid's access log, for **pfSense CE 2.9 / Plus 26.x**.

*[Versión en castellano: LEEME.md](LEEME.md)*

Revived from the squidanalyzer package in
[Unofficial-pfSense-packages](https://github.com/marcelloc/Unofficial-pfSense-packages)
(Apache-2.0, Luiz Gustavo and Marcello Coutinho). The binary comes from
FreeBSD's official package repository.

## Why it pairs with samba-ad

Squid logs by client IP. On a DHCP network that makes reports nearly useless —
the same address is a different person next week. Once the proxy authenticates
against Active Directory (see [samba-ad](../samba-ad/)), SquidAnalyzer reports
**by domain username** instead, and the numbers start meaning something.

## Status

| Verified | Not yet verified |
|---|---|
| Installs from FreeBSD's repository: **11 MiB**, 0 known CVEs | Reports rendered in a browser |
| All package XMLs parse with pfSense's own parser | Report generation from real traffic |
| `squidanalyzer.inc` loads clean under **PHP 8.5** | The cron schedule over time |
| Configuration generator runs; menu registers under Status | pfSense Plus |

The package's PHP and XML are carried **unmodified** — they were already
compatible. Only an installer and documentation were added.

## Install

```sh
fetch -q -o - https://raw.githubusercontent.com/bootablearg/pfsense-packages-revived/main/squidanalyzer/install.sh | sh -s check
```

`check` changes nothing. Then `| sh -s install`, and open **Status →
SquidAnalyzer**.

Reports are produced by a cron job from Squid's log, so nothing shows up until
Squid has logged traffic and the job has run at least once.

## Requirements

Squid installed and logging. Without it there is no log to analyse — `check`
warns you about this.

## Uninstall

```sh
./install.sh remove
```

## License

Apache-2.0. See [LICENSE](LICENSE) for the attributions and the list of
changes. SquidAnalyzer itself is GPLv3 and is installed from FreeBSD's
repository.
