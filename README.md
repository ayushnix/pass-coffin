## pass-coffin

A [pass](https://www.passwordstore.org/) extension that hides password store data inside a GPG
encrypted file, which we'll call a coffin.

Because of how pass works, directory and file names aren't encrypted by default and anyone who has
access to your computer can see which websites you use and your usernames on those websites. This is
different from how password managers like [keepassxc](https://github.com/keepassxreboot/keepassxc)
work by keeping your entire password store database inside an encrypted file and can also
automatically lock access to the application itself after a certain amount of time.

pass-coffin tries to fill this gap by encrypting the entire password-store database inside a single
GPG encrypted file, which we'll call a 'coffin'. It can also automatically hide password store data
after a certain amount of time.

`pass-coffin` is heavily inspired from [pass-tomb](https://github.com/roddhjav/pass-tomb) and
[pass-grave](https://github.com/8go/pass-grave).

## Why should I use this instead of pass-tomb or pass-grave?

- `pass-coffin` doesn't depend on a [3000+ line ZSH
  script](https://github.com/dyne/Tomb/blob/master/tomb) and doesn't [need root
  access](https://github.com/roddhjav/pass-tomb/issues/19#issuecomment-395232044) to work

- `pass-coffin` focuses on being (mostly) compatible with the interface of `pass-tomb` while writing
  "better" quality shell script code than `pass-grave`

- the code is linted using [shellcheck](https://github.com/koalaman/shellcheck) and formatted using
  [shfmt](https://github.com/mvdan/sh)

## :warning: Please Use Git

Before using this extension or any other password store extension, I **highly recommend** that you
check in your password store in a local git repository and sync it with a remote git repository
(doesn't have to be an online remote repo) as a backup. You don't want to lose your password store
data because of a bug in an extension. Using git also helps you verify the integrity of your
password store data.

Use `pass git init` to initialize a local git repository in your password store and add a remote git
repository using `pass git remote add backup <location>`.

For more details, please read the "EXTENDED GIT EXAMPLE" section of the [man page of
pass](https://git.zx2c4.com/password-store/about/).

## Installation

Before installing `pass-coffin`, make sure you've added the following line in `~/.bash_profile` or
an equivalent file and have logged out and logged back in.

```
export PASSWORD_STORE_ENABLE_EXTENSIONS=true
```

Password Store extensions will not work if this environment variable isn't set.

Since pass-coffin has a similar interface as pass-tomb, both packages cannot exist at the same time
and will conflict each other. Please install either pass-tomb or pass-coffin, not both.

### Dependencies

- [pass](https://git.zx2c4.com/password-store/) and its dependencies like bash, coreutils, gpg,
  find, tree
- [GNU tar](https://www.gnu.org/software/tar/) (although [busybox
  tar](https://busybox.net/downloads/BusyBox.html#tar) and [FreeBSD
  tar](https://www.freebsd.org/cgi/man.cgi?query=tar&sektion=1) should work as well)
- [systemd-run](https://github.com/systemd/systemd) (*optional*, if you want to use the timer
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
wget https://github.com/ayushnix/pass-coffin/releases/download/v1.1/pass-coffin-1.1.tar.gz
tar xvzf pass-coffin-1.1.tar.gz
cd pass-coffin-1.1
sudo make install
```

or, you know, `doas make install`.

## Usage

Create a password store coffin

```
$ pass close
[#] Password Store data is now hidden inside a GPG coffin
```

Open the password store coffin

```
$ pass open
[#] Password Store data has been retrieved from the GPG coffin
```

Create a password store coffin and close it automatically after 10 minutes.

```
$ pass open -t 10min
[#] Password Store data has been retrieved from the GPG coffin
[#] Password Store will be hidden inside a coffin after 10min
```

The time syntax should be [valid systemd
time](https://www.freedesktop.org/software/systemd/man/systemd.time.html).

Show the status of the timer set by `pass open -t`

```
$ pass timer

NEXT                        LEFT     LAST PASSED UNIT              ACTIVATES
Mon 2021-10-04 19:44:13 IST 28s left n/a  n/a    pass-coffin.timer pass-coffin.service

1 timers listed.
Pass --all to see loaded but inactive timers, too.
```

Stop the timer set by `pass open -t`

```
$ pass timer stop
[#] The timer to hide password store data has been stopped
```

## Contributions

Please see [this](https://github.com/ayushnix/pass-coffin/blob/master/CONTRIBUTING.md) file.

### TODO

- parse the time left from `systemctl list-timers` and show only that when using `pass timer`,
  preferably without using additional dependencies
- add fish completion
