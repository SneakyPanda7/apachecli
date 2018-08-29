#!/usr/bin/env perl

package ApacheConf::Directives::ServerRoot;
use warnings;
use strict;
use FindBin qw( $Bin );
use lib "$Bin/lib/perl5";
use lib "$Bin/lib";
use ApacheConf::Directives::Common;
use Data::Dumper;

sub main {
    my $class=shift;
    my $self=$class->new(@_);
}

sub server_root {
    my $self=shift;
    my $args={@_};
    my $map=$args->{'map'};

    my $parser=$self->Parser('Apache');
    my $params=$parser->params()
        or return;
    my $default=$params->{'HTTPD_ROOT'};

    my $server_root;
    if (defined $map and grep $_ eq 'VirtualHost', @{$map}) {
        my $valid=$parser->find_valid_directives(directive=>'ServerRoot', map=>$map)
            or return;
        $server_root=$valid->[-1]->{'value'}
            if @{$valid};
    } else {
        $server_root=$self->root_server_root;
    }

    $server_root=defined $server_root ? $server_root : $default;

    return $self->pathname(\$server_root);
}

sub root_server_root {
    my $self=shift;

    my $parser=$self->Parser('Apache');
    my $params=$parser->params()
        or return;
    my $default=$params->{'HTTPD_ROOT'};

    my $valid=$parser->find_valid_directives(directive=>'ServerRoot')
        or return;

    my $root_server_root;
    if (@{$valid}) {
        my @root_server_roots=();
        for my $meta (@{$valid}) {
            my ($map, $value)=@{$meta}{qw(map value)};
            next if grep $_ eq 'VirtualHost', @{$map};
            push @root_server_roots, $value;
        }

        $root_server_root=$root_server_roots[-1]
            if @root_server_roots;
    }

    $root_server_root=defined $root_server_root ? $root_server_root : $default;

    return $self->pathname(\$root_server_root);
}

1;
