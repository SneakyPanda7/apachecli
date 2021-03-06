#!/usr/bin/env perl

package ApacheConf::Handlers;
use warnings;
use strict;
use FindBin qw($Bin);
use lib "$Bin/lib";
use lib "$Bin/lib/perl5";

my @modules=glob("$Bin/lib/ApacheConf/Handlers/*.pm");
for my $module (@modules) {
    require $module;
}

1;
