#!/usr/bin/env perl

package ApacheConf::CLI::Methods;
use warnings;
no warnings 'portable';
use strict;
use FindBin qw( $Bin );
use lib "$Bin/lib";
use lib "$Bin/lib/perl5";
use namespace::clean;

my @methods=glob("$Bin/lib/ApacheConf/CLI/Methods/*.method");
for my $method (@methods) {
    do $method;
}

1;
