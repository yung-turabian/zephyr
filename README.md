# Zephyr, A Links Development Tool

Zephyr is a lightweight piece of software that performs live reloads for a [Links](https://links-lang.org/) project. Inspired by Air for Go webservers. Zephyr aims to fill a similar role for the Links ecosystem.

## Notes
 + Requires geckodriver for Firefox.
 + As well, currently only works for Firefox.
 + Mostly horribly broken but is convienent.

## Building

Uses PAR-packer to create a binary. But of course this can just be ran as a Perl script if you have the dependencies and perl installed on your machine.

Requires the following pacakges:

```perl
use Net::EmptyPort qw<check_port>;
use Log::Log4perl;
use Firefox::Marionette();
use Try::Tiny;
```

Also requires:

+ curl

``` bash
pp -o zephyr zephyr.pl
```

## License

BSD-3
