# Verification checklist — wpad

What was actually run, on a real pfSense box, and what is still open.

## Environment

| | |
|---|---|
| Product | pfSense CE 2.9.0-RELEASE |
| ABI | `FreeBSD:16:amd64` |
| PHP | 8.5.7 |
| nginx | 1.30.4 (from pfSense; no extra binary is installed) |

## Done

### 1. The original code against PHP 8.5

```sh
php -l wpad.inc                  # -> No syntax errors
php -l wpad.priv.inc             # -> No syntax errors
php -l shortcuts/pkg_wpad.inc    # -> No syntax errors
```

### 2. Install and registration

```
pfSense-pkg-WPAD               1.1.0
menu: WPAD                     Services
```

`pkg_edit.php?xml=wpad.xml` returns 200 where a missing file returns 404. No
package is installed from any repository: this runs a second nginx, which
pfSense already ships.

## Changed, and why

`wpad_nginx.template` emitted this inside the server block:

```nginx
server_name wpad.localdomain
server name 127.0.0.1
client_max_body_size 200m;
```

Neither of the first two lines ended in a semicolon, and the second is not a
directive at all. nginx therefore read all three as a single `server_name` with
six arguments — which parses without complaint, and quietly swallowed
`client_max_body_size` along with it. Replaced with a correct
`server_name wpad wpad.localdomain localhost;` and the body-size limit restored.

## Open

### A. Serving a PAC file to a real client

The package registers and its GUI page loads, but **no nginx instance has been
configured and started from it, and no browser has fetched a PAC file**. That
is the substantive test and it has not been done.

### B. DHCP option 252 and DNS discovery

Neither delivery mechanism has been set up or observed working.

### C. Chained with samba-ad and Squid

The combination this package exists for -- discovery, then Kerberos single
sign-on, then filtering -- has not been exercised end to end.

### D. Port conflicts

The listener defaults to port 80, which on pfSense may already be taken by the
redirect to the web GUI. The behaviour when it is has not been tested.

### E. pfSense Plus

Untested.
