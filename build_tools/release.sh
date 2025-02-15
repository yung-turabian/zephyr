#!/usr/bin/bash

gpg --detach-sign --armor zephyr
tar cf zephyr.tar LICENSE zephyr zephyr.asc
