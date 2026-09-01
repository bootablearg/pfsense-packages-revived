# ipguard — keep unknown hosts off the LAN

Enforces a list of MAC/IP pairs on a network segment. Anything not on the list
is denied the ability to communicate.

Revived from [Marcello Coutinho's ipguard package](https://github.com/marcelloc/Unofficial-pfSense-packages),
ported to pfSense CE 2.9 / PHP 8.5. BSD-2-Clause; see [LICENSE](LICENSE).

## Read this before installing

**ipguard works by ARP spoofing.** It watches the segment and answers ARP for
addresses that are not on its allow-list with bogus replies, so unauthorised
hosts cannot reach anything. That is the mechanism, and it has consequences:

- A host you forget to list **loses the network**, with no error message that
  points at the firewall. Printers, IP phones, IoT devices and anything with a
  randomising MAC are the usual casualties.
- It is a nuisance barrier, not a security control. An attacker who can set
  their own MAC and IP can copy a permitted pair and walk straight through.
  Treat it as tidiness enforcement, not as authentication.
- If you want actual port-level control, 802.1X on the switch is the real
  answer. This exists for networks whose switches cannot do that.

Start with a couple of test hosts, not with the whole office.

## What it installs

`ipguard` from FreeBSD's repository, plus the GUI. It runs one daemon per
configured interface.

```sh
./install.sh check      # reports what it would do; changes nothing
./install.sh install
./install.sh remove
```

Then: **Firewall → IPguard**. Add one entry per permitted host: interface, MAC,
IP and a description. The daemon starts once at least one enabled entry exists,
and stops when none do.

Logs land in `/var/log/ipguard_<interface>.log`.

## Fixed on the way in

The package as published **could not be installed** on pfSense 2.9. Its resync
command runs at install time, when no configuration exists yet, and it reached
`count()` with an undefined variable:

```
count(): Argument #1 ($value) must be of type Countable|array, null given
```

PHP 7 counted null as zero and carried on; PHP 8 makes it fatal. `php -l` does
not see it — the file parses cleanly and only dies when called.

Two more, both original logic rather than PHP versions:

- Whether the daemon started depended on `$ipguard['enable']` left over from a
  preceding `foreach` — that is, on **the last entry in the list**. A disabled
  entry at the bottom kept the service down no matter what was above it.
- Each config file was written twice with identical content.

The pfSense 2.2 PBI symlink workaround was removed as well; PBI was retired in
2016 and `/usr/pbi` does not exist on any supported release.

## Status

Installs and registers on CE 2.9.0-RELEASE, and the install path that used to
crash now completes. **No host has actually been blocked or permitted by it** —
see [docs/VERIFY.md](docs/VERIFY.md).
