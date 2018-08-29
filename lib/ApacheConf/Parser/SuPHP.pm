#!/usr/bin/env perl

package ApacheConf::Parser::SuPHP;
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

sub _conf {
    my $self=shift;
    my $conf='';
    my @path=qw(/etc /opt/suphp/etc);
    for my $path (@path) {
        $conf=$path . "/suphp.conf";
        return $conf
            if -r $conf;
    }

    return;
}

sub load_conf {
    my $self=shift;

    my $file=$self->_conf
        or return;

    my $conf=eval {Config::IniFiles->new( -file => $file ) }
        or return;

    return $conf;
}

sub load_conf_cached {
    my $self=shift;

    return $self->{'load_conf_cached'}
        if defined $self->{'load_conf_cached'};

    $self->{'load_conf_cached'}=$self->load_conf();

    return $self->{'load_conf_cached'};
}

1;
