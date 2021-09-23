## pass-coffin

A [pass](https://www.passwordstore.org/) extension that hides password store data inside a GPG
encrypted file, which we'll call a coffin.

`pass-coffin` is heavily inspired from [pass-grave](https://github.com/8go/pass-grave) and
[pass-tomb](https://github.com/roddhjav/pass-tomb).

## Why should I use this instead of pass-tomb or pass-grave?

- `pass-coffin` doesn't depend on a [3000+ line ZSH
  script](https://github.com/dyne/Tomb/blob/master/tomb) and doesn't [need root
  access](https://github.com/roddhjav/pass-tomb/issues/19#issuecomment-395232044) to work

- `pass-coffin` focuses on being (mostly) compatible with the interface of `pass-tomb` while writing
  "better" quality shell script code than `pass-grave`

## Installation

Before installing `pass-coffin`, make sure you've added the following line in `~/.bash_profile` or
an equivalent file and have logged out and logged back in.

```
export PASSWORD_STORE_ENABLE_EXTENSIONS=true
```

Password Store extensions will not work if this environment variable isn't set.
