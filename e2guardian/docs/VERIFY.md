# Verification checklist — e2guardian

What was actually run, on a real pfSense box, and what is still open.

## Environment

| | |
|---|---|
| Product | pfSense CE 2.9.0-RELEASE |
| ABI | `FreeBSD:16:amd64` |
| PHP | 8.5.7 |
| e2guardian | 5.3.4_3 (`www/e2guardian`, FreeBSD repository) |
| Upstream original | pkg-e2guardian5, Marcello Coutinho, Apache-2.0 |

## Done

### 1. Availability and safety of the port

```sh
pkg audit -F
pkg audit e2guardian-5.3.4_3     # -> 0 problem(s) in 0 package(s)
```

The dry run is remarkably small — no Python, nothing heavy:

```
e2guardian: 5.3.4_3   harfbuzz: 14.2.1   talloc: 2.4.1_1
3 packages · 13 MiB on disk · 2 MiB downloaded
```

No pfSense package is upgraded, reinstalled or removed.

### 2. The original code against PHP 8.5

Contrary to expectation, the 2015-2017 code needed almost no porting:

```sh
php -l e2guardian.inc            # -> No syntax errors
php -l e2guardian_antivirus.inc  # -> No syntax errors
php -l pkg_e2guardian.inc        # -> No syntax errors
```

* No use of removed functions. `each`, `ereg` and `split` appear only as
  substrings inside identifiers such as `sslsit**ereg**explist` — false
  positives on a naive grep.
* `$config` global **still exists in pfSense 2.9** (verified: 30 keys), so the
  148 remaining old-style accesses keep working. They are technical debt, not
  breakage.
* The upstream migration to `config_get_path()` is about 25% done (46 calls);
  both APIs are verified to share state, so the mixture is safe.

All **18 package XMLs** parse through pfSense's own parser, and
`e2guardian.inc` (2394 lines) loads with no fatal error.

### 3. Configuration generation

`sync_package_e2guardian('no', true)` runs and produces:

```
e2guardian.conf        (~27 KB)
e2guardianf1.conf      (528 lines, groupname = 'Default')
common.story, g_Default.story, lists/, ssl/
```

The package creates a default filter group by itself when none exists.

### 4. The startup defect, and its fix

With the original template, e2guardian 5.3.4 refuses to start:

```
Invalid maxuploadsize: 0
Error opening filter group config: .../e2guardianf1.conf
...
master: Error binding server thttps socket: (Address already in use)
```

Both symptoms are misleading. The first came from an incomplete file set during
testing. The real one is the second: **the port is free**, and nothing else
binds it. The cause is that `transparenthttpsport` is emitted unconditionally,
and — per e2guardian's own documentation — *defining* that directive enables
transparent HTTPS. 5.3.x binds the socket even with `enablessl = off`.

Fixed by emitting the directive only when SSL or SSL MITM is enabled. With the
fix, the generated config contains:

```
#transparenthttpsport = 8081  # disabled: SSL is off
```

and e2guardian starts:

```
$ pgrep -x e2guardian     -> running
$ sockstat -4l | grep e2g -> e2guardian  tcp4  127.0.0.1:8080
```

### 5. Installer and registration

```sh
./install.sh check      # product, version, ABI, PHP, install plan
./install.sh install    # files, GUI registration, config generation
```

Afterwards the configuration holds `menu: E2guardian Proxy` and
`servicio: e2guardian`, and `parse_xml_config_pkg()` returns
`Services: E2guardian`.

### 6. The GUI in a browser

Every screen was opened in a browser on 2026-09-01, on pfSense CE 2.9.0.

One defect came out of it, in the postfix package rather than this one:
`postfix_queue.php` and two other pages re-loaded jQuery and Bootstrap in the
middle of the body, which re-registered Bootstrap's plugins and left the top
navigation bar's dropdowns dead. Fixed in `ae5e597`.

Nine of this package's own pages had simply never been installed -- the
upstream fetch enumerated `/usr/local/pkg` and skipped `/usr/local/www`
entirely. Among them `e2gerror.php`, the page an end user sees when a request
is blocked: the filter worked and answered with a 404. Fixed in `1dd8b6d`.

## Open

### B. Filtering actual traffic

Nothing has been proxied through it. Confirm a client's request is filtered,
that a banned phrase or site is blocked, and that the block page appears.

### C. Blacklists

The installer deliberately skips the download. The Blacklist tab's fetch and
extract paths are untested.

### D. Chained behind Squid with AD authentication

The interesting combination with [samba-ad](../../samba-ad/): per-group
filtering driven by Active Directory group membership.

### E. pfSense Plus

Not run there.
