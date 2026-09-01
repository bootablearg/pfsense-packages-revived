# Optional add-ons that are no longer downloaded automatically

Two packages here used to fetch third-party code from the internet while they
were being installed, and install it as root-executable files on the firewall.
That behaviour has been removed. This page says what was removed, why, and how
to put it back deliberately if you want it.

## What was happening

`mailscanner` downloaded four GitHub branch tarballs and one zip:

| what | where from |
|---|---|
| spf-tools | `github.com/jsarenik/spf-tools/archive/master.zip` |
| extremeshok_fromreplyto | `github.com/extremeshok/spamassassin-extremeshok_fromreplyto/archive/master.zip` |
| DecodeShortURLs | `github.com/smfreegard/DecodeShortURLs/archive/master.zip` |
| clamav-unofficial-sigs | `github.com/extremeshok/clamav-unofficial-sigs/archive/master.zip` |
| pdfid | `http://didierstevens.com/files/software/pdfid_v0_2_5.zip` |

`postfix` downloaded the first of those as well.

Four problems, in rising order of importance:

1. **It crashed.** Unpacking used PHP's `ZipArchive`, and pfSense does not build
   the zip extension. Installation died with `Class "ZipArchive" not found`
   before the package finished registering.
2. **Nothing was pinned.** Every URL points at `master`. What you got depended
   entirely on when you installed.
3. **Nothing was verified.** No signature, no checksum, no release tag.
4. **One of them was plain HTTP.** The pdfid archive travelled unencrypted, and
   was then made executable and run as root. Anyone positioned between the
   firewall and that host could choose what ran.

There is also a fifth, smaller problem: the pdfid step rewrote the scripts'
shebang to `/usr/local/bin/python2`, which has not existed in FreeBSD's package
repository for years.

## What happens now

Nothing is downloaded during installation. Both packages log which optional
add-ons are absent and carry on. The features that depend on them stay inactive
rather than half-working:

- **Postwhite** (the SPF-based sender whitelist on Postfix's Antispam tab) is
  ignored when `/usr/local/bin/postwhite` is missing. It used to hand postscreen
  a `cidr:` map that nothing ever created, and Postfix refuses to start on a
  missing lookup table — so the old behaviour was a mail gateway that would not
  come up.
- The SpamAssassin plugins simply are not loaded.

## Installing them anyway

These run as root, some of them from cron. Review what you are installing, and
take a tagged release rather than a branch.

```sh
# Example: postwhite and spf-tools, from a release rather than master.
cd /root
fetch https://github.com/stevejenkins/postwhite/archive/refs/tags/<version>.tar.gz
fetch https://github.com/jsarenik/spf-tools/archive/refs/tags/<version>.tar.gz
# review, then:
tar -x -f <version>.tar.gz -C /usr/local/bin
chmod 755 /usr/local/bin/postwhite
```

MailScanner's helper is still there for the same job, fixed: it unpacks with
`bsdtar` instead of `ZipArchive`, and refuses `http://` URLs outright.

```php
require_once('/usr/local/pkg/mailscanner.inc');
get_github_plugin(
    'https://github.com/smfreegard/DecodeShortURLs/archive/refs/tags/<version>.tar.gz',
    array('/*pm', '/*cf'),
    '/usr/local/etc/mail/spamassassin/plugins'
);
```

It also accepts a local path, which is the better habit: download, read, then
install from the file you have already looked at.

## Why not just pin the versions and keep the download

That would fix problems 2 and 4 but not the underlying one: a firewall package
that reaches out to four third-party repositories during installation has four
more ways to fail and four more parties to trust, for features most installs do
not use. Making it explicit costs the operator five minutes and makes the
default install smaller, faster and easier to reason about.
