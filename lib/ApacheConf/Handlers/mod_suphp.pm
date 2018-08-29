#!/usr/bin/env perl

package ApacheConf::Handlers::mod_suphp;
use warnings;
use strict;
use FindBin qw( $Bin );
use lib "$Bin/lib/perl5";
use lib "$Bin/lib";
use ApacheConf::Common::Shell;
use Data::Dumper;
use Config::IniFiles;

sub main {
    my $class=shift;
    my $self=$class->new();
}

sub bin2hand {
    my $self=shift;
    my $binary=shift;

    my $handlers=$self->handlers;

    return $self->value2keys(data=>$handlers, value=>$binary);
}

sub hand2bin {
    my $self=shift;
    my $handler=shift;

    return $self->handlers->{$handler};
}

sub handlers {
    my $self=shift;
    my $parser=$self->Parser('SuPHP');
    my $conf=$parser->load_conf_cached;

    my $handlers={};
    for my $handler ($conf->Parameters('handlers')) {
        my $binary=$conf->val('handlers', $handler);
        ($binary)=$RE{'CUSTOM'}{'GENERAL'}{'DELIMITED'}{'-i'}{'-keep'}{'-delim'=>'"'}->matches($binary);
        $binary =~ s/^php://;
        $handlers->{$handler}=$binary;
    }

    return $handlers;
}

1;
