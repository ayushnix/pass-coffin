[<img src="https://gitlab.com/uploads/-/system/project/avatar/3157196/logo.png" align="right" height="110"/>][github-link]

## pass-coffin

`pass-coffin` is a [pass](https://www.passwordstore.org/) extension that hides password store data
inside a GPG encrypted file, which we'll call a coffin.

Because of how `pass` works, directory and file names aren't encrypted by default and anyone who has
access to your computer can see which websites you use and your usernames on those websites. This is
different from how password managers like [keepassxc](https://github.com/keepassxreboot/keepassxc)
work by keeping your entire password store database inside an encrypted file and can also
automatically lock access to the application itself after a certain amount of time. `pass-coffin` is
meant to provide similar features to `pass`.

`pass-coffin` is heavily inspired from [pass-tomb](https://github.com/roddhjav/pass-tomb) and
[pass-grave](https://github.com/8go/pass-grave). A lot of credit goes to the authors of these
extensions for making `pass-coffin` possible.

## Why use `pass-coffin`?

- `pass-coffin` doesn't depend on a [3000+ line ZSH
  script](https://github.com/dyne/Tomb/blob/master/tomb) and it doesn't [need root
  access](https://github.com/roddhjav/pass-tomb/issues/19#issuecomment-395232044) to work like
  `pass-tomb` does

- if `PASSWORD_STORE_SIGNING_KEY` is set, `pass-coffin` will sign the encrypted coffin file as well
  which ensures data integrity and authenticity

- `pass-coffin` focuses on being (mostly) compatible with the interface of `pass-tomb` while writing
  "better" quality shell script code than `pass-grave`

- the encrypted coffin is just a tar file which can be easily synced to other devices or cloud
  storage to create backups, similar to how keepassxc databases work

- the code is linted using [shellcheck](https://github.com/koalaman/shellcheck) and formatted using
  [shfmt](https://github.com/mvdan/sh)

## :warning: Please Create Backups or Use Git

Before using this extension or any other password store extension, I **highly recommend** that you
check in your password store in a local git repository and sync it with a remote git repository
(doesn't have to be an online remote repo) or make regular backups of your password store using
tools like [borgbackup](https://www.borgbackup.org/). You don't want to lose your password store
data because of an unintentional bug in an extension.

Use `pass git init` to initialize a local git repository in your password store and add a remote git
repository using `pass git remote add backup <location>`.

For more details, please read the "EXTENDED GIT EXAMPLE" section of the [man page of
pass](https://git.zx2c4.com/password-store/about/).

## Installation

Before installing `pass-coffin`, make sure that the `PASSWORD_STORE_ENABLE_EXTENSIONS` environment
variable is set to `true`. If this environment variable isn't set, password store extensions will
not work.

Since `pass-coffin` has a similar interface as `pass-tomb`, both of these password store extensions
**cannot exist and cannot be used at the same time**. Please install either `pass-tomb` or
`pass-coffin`, not both.

### Dependencies

- [pass](https://git.zx2c4.com/password-store/)
- [GNU tar](https://www.gnu.org/software/tar/) (although [busybox
  tar](https://busybox.net/downloads/BusyBox.html#tar) and [FreeBSD
  tar](https://www.freebsd.org/cgi/man.cgi?query=tar&sektion=1) should work as well)
- [GNU find](https://www.gnu.org/software/findutils/) (although [busybox
  find](https://busybox.net/downloads/BusyBox.html#find), [FreeBSD
  tar](https://www.freebsd.org/cgi/man.cgi?query=find&sektion=1&manpath=FreeBSD+13.0-RELEASE+and+Ports),
  and [OpenBSD find](https://man.openbsd.org/find.1) should also work)
- [systemd-run](https://github.com/systemd/systemd) (optional, if you want to use the timer
  functionality)

### Arch Linux

`pass-coffin` is available in the [Arch User
Repository](https://aur.archlinux.org/packages/pass-coffin/).

### Git Release

```
git clone https://github.com/ayushnix/pass-coffin.git
cd pass-coffin
sudo make install
```

You can also do `doas make install` if you're using [doas](https://github.com/Duncaen/OpenDoas),
which you probably should.

### Stable Release

```
curl -LO https://github.com/ayushnix/pass-coffin/releases/download/v1.2.0/pass-coffin-1.2.0.tar.gz
tar xvzf pass-coffin-1.2.0.tar.gz
cd pass-coffin-1.2.0/
sudo make install
```

or, you know, `doas make install`.

## Usage

The password store data can be hidden inside a coffin using `pass close`

```
$ pass close
password store data has been signed and buried inside a coffin
```

If `PASSWORD_STORE_SIGNING_KEY` is set, `pass close` will automatically create and verify a
signature for the coffin.

The hidden data can be retrieved using `pass open`

```
$ pass open
the signature for the coffin is valid
password store data has been retrieved from the coffin
```

If `PASSWORD_STORE_SIGNING_KEY` is set, `pass open` will automatically verify the signature for the
coffin.

The hidden data can be retrieved and closed automatically after a certain amount of time using `pass
open -t <systemd time>`

```
$ pass open -t 10min
the signature for the coffin is valid
password store data has been retrieved from the coffin
password store data will be hidden inside a coffin after 10min
```

The time syntax should be [valid systemd
time](https://www.freedesktop.org/software/systemd/man/systemd.time.html).

The status of any active timers to hide password data can be viewed using `pass timer`

```
$ pass timer
NEXT                        LEFT     LAST PASSED UNIT              ACTIVATES
Mon 2021-10-04 19:44:13 IST 28s left n/a  n/a    pass-coffin.timer pass-coffin.service
```

If you want to stop a timer prematurely, execute `pass timer stop`

```
$ pass timer stop
the timer to create the coffin has been stopped
```

`pass-coffin` uses yellow color for printing warnings and red color for printing error messages. If
you don't want to see colors while using `pass-coffin`, use the [NO_COLOR](https://no-color.org/)
environment variable and set it to anything you like (`1`, `true`, `yes`).

### Using `pass close`

The `pass close` command can be used in a variety of ways to ensure that your password store
metadata isn't exposed when you're not using your computer. Although screen locker security is still
[a joke on Wayland](https://github.com/swaywm/swaylock/issues/163) (although it should hopefully be
[fixed](https://gitlab.freedesktop.org/wayland/wayland-protocols/-/merge_requests/131)
[soon](https://github.com/swaywm/swaylock/commit/1d1c75b6316d21933069a9d201f966d84099f6ca)) just
like [it's a joke on Xorg](https://github.com/linuxmint/cinnamon-screensaver/issues/354), you can
write something like this

```sh
pass close > /dev/null 2>&1 || printf "%s\n" "unable to close password store" >&2
swaylock || "$HOME"/.local/bin/screenlock_script
```

You can also run `pass close` before your system goes to sleep and before it is issued a
shutdown/reboot command. On Linux distributions with systemd,
[systemd-lock-handler](https://git.sr.ht/~whynothugo/systemd-lock-handler) can help with this.

## Contributions

Please see [this](https://github.com/ayushnix/pass-coffin/blob/master/CONTRIBUTING.md) file.
