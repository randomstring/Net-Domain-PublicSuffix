#!/usr/bin/env perl

# dump the current public suffix trie

use strict;
use Net::Domain::PublicSuffix;

Net::Domain::PublicSuffix::dump_tree();
