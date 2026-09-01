# Sarg Reports

Squid Analysis Report Generator for **pfSense CE 2.9 / Plus 26.x** — detailed
browsing reports by user, site, date and downloaded volume.

*[Versión en castellano: LEEME.md](LEEME.md)*

Revived from the sarg package in
[Unofficial-pfSense-packages](https://github.com/marcelloc/Unofficial-pfSense-packages).
This one was part of pfSense itself at one point — hence the ESF, LLC copyright
(Electric Sheep Fencing, the company behind pfSense before Netgate).

## Sarg or SquidAnalyzer?

Both read Squid's access log and both are in this repository. They overlap, so
pick one rather than running both:

| | Sarg | SquidAnalyzer |
|---|---|---|
| Reports | very detailed, many breakdowns, scheduled | lighter, graph-oriented |
| Size | 17 MiB | 11 MiB |
| Scheduling | built-in schedule tab | cron |

Sarg is the more thorough of the two; SquidAnalyzer is easier to read at a
glance. Neither is better in the abstract.

Both benefit enormously from the proxy authenticating against Active Directory
(see [samba-ad](../samba-ad/)): reports keyed by **domain username** instead of
by IP address, which on a DHCP network is what makes them usable at all.

## Status

| Verified | Not yet verified |
|---|---|
| Installs from FreeBSD's repository: **17 MiB**, 0 known CVEs | Reports rendered in a browser |
| All 5 package XMLs parse with pfSense's own parser | Report generation from real traffic |
| `sarg.inc` (662 lines) loads clean under **PHP 8.5** | The scheduler over time |
| Configuration generator runs and writes its config | pfSense Plus |

The package's PHP and XML are carried **unmodified** — they were already
compatible. Only an installer and documentation were added.

## Install

```sh
fetch -q -o - https://raw.githubusercontent.com/bootablearg/pfsense-packages-revived/main/sarg/install.sh | sh -s check
```

`check` changes nothing. Then `| sh -s install`, and open **Status → Sarg
Reports**.

## Requirements

Squid installed and logging. `check` warns if it is missing.

## Uninstall

```sh
./install.sh remove
```

## License

BSD 2-Clause. See [LICENSE](LICENSE) for the attributions and the list of
changes. Sarg itself is GPLv2 and is installed from FreeBSD's repository.
