#!/usr/bin/env perl

package ApacheConf::Directives;
use warnings;
use strict;
use FindBin qw($Bin);
use lib "$Bin/lib";
use lib "$Bin/lib/perl5";

my @modules=grep( ! m|/Common.pm$|, glob("$Bin/lib/ApacheConf/Directives/*.pm"));
for my $module (@modules) {
    require $module;
}

1;
