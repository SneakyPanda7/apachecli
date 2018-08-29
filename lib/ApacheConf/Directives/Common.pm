#!/usr/bin/env perl

package ApacheConf::Directives::Common;
use warnings;
use strict;
use parent qw(ApacheConf::Common::Shell);
use ApacheConf::Common::Shell;

my @methods=keys %{namespace::clean->get_functions(__PACKAGE__)};
our @EXPORT=('%RE', @methods);
sub params {
    my $self=shift;
    my $params=shift;

    if (defined $params) {
        $self->{'params'}=$params;
    } else {
        return $self->{'params'};
    }
}

sub map {
    my $self=shift;
    my $map=shift;

    if (defined $map) {
        $self->{'map'}=$map;
    } else {
        return $self->{'map'};
    }
}

1;
