#!/usr/bin/env perl

package ApacheConf::Directives::ServerAlias;
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

sub server_aliases {
    my $self=shift;
    my $args={@_};
    my $map=$args->{'map'};

    my $parser=$self->Parser('Apache');

    my $valid=$parser->find_valid_directives(directive=>'ServerAlias', map=>$map)
        or return;

    my $return=[];
    if (@{$valid}) {
        if (grep $_ eq 'VirtualHost', @{$map}) {
            push @{$return}, $_->{'value'} for @{$valid};
        } else {
            for my $meta (@{$valid}) {
                my ($map, $value)=@{$meta}{qw(map value)};
                next if grep $_ eq 'VirtualHost', @{$map};
                push @{$return}, $value;
            }
        }
    }

    return $return;
}

1;
