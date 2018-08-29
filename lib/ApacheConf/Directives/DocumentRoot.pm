#!/usr/bin/env perl

package ApacheConf::Directives::DocumentRoot;
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

sub document_root {
    my $self=shift;
    my $args={@_};
    my $map=$args->{'map'};

    my $parser=$self->Parser('Apache');

    if (defined $map and grep $_ eq 'VirtualHost', @{$map}) {
        my $valid=$parser->find_valid_directives(directive=>'DocumentRoot', map=>$map)
            or return;
        @{$valid}
            or return;

        my $document_root=$valid->[-1]->{'value'};
        if ($document_root !~ m|^/|) {
            my $sr=$self->Directives('ServerRoot');
            my $server_root=$sr->server_root(map=>$map)
                or return;
            $document_root=$server_root . $document_root;
        }
        return $self->pathname(\$document_root);
    } else {
        return $self->root_document_root;
    }
}

sub root_document_root {
    my $self=shift;

    my $parser=$self->Parser('Apache');

    my $valid=$parser->find_valid_directives(directive=>'DocumentRoot')
        or return;

    if (@{$valid}) {
        my @root_document_roots=();
        for my $meta (@{$valid}) {
            my ($map, $value)=@{$meta}{qw(map value)};
            next if grep $_ eq 'VirtualHost', @{$map};
            push @root_document_roots, $value;
        }

        if (@root_document_roots) {
            my $root_document_root=$root_document_roots[-1];
            if ($root_document_root !~ m|^/|) {
                my $sr=$self->Directives('ServerRoot');
                my $server_root=$sr->server_root()
                    or return;
                $root_document_root=$server_root . $root_document_root;
            }
            return $self->pathname(\$root_document_root);
        }
    }
}

1;
