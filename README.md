# Zephyr, A Links Development Tool

Zephyr is a lightweight piece of software that live reloads a Links project. Inspired by a piece of software I believe is called Air. Zephyr aims to fill a similar role in the Links ecosystem.

## Notes
 + Requires geckodriver for Firefox.
 + As well, currently only works for Firefox.
 + Mostly horribly broken but is convienent.

## Building

Uses PAR-packer to create a binary. But of course this can just be ran as a Perl script if you have the dependencies and perl installed on your machine.

``` bash
pp -o zephyr zephyr.pl
```

## License

BSD-3
