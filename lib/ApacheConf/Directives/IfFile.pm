#!/usr/bin/env perl

package ApacheConf::Directives::IfFile;
use warnings;
use strict;
use FindBin qw( $Bin );
use lib "$Bin/lib/perl5";
use lib "$Bin/lib";
use ApacheConf::Directives::Common;

sub main {
    my $class=shift;
    my $self=$class->new(@_);

    my $params=$self->params()
        or return;

    my @params=grep { defined and length }
                    $params =~
                        /^(\x21)?\s*+
                            (?>
                                $RE{'CUSTOM'}{'GENERAL'}{'DELIMITED'}{'-delim'=>"'"}{'-keep'}|
                                $RE{'CUSTOM'}{'GENERAL'}{'DELIMITED'}{'-delim'=>'"'}{'-keep'}|
                                $RE{'CUSTOM'}{'BASH'}{'PATH'}{'-keep'}
                            )
                        /xi;

    my ($negate, $file);
    if (@params == 2) {
        ($negate, $file)=@params;
    } elsif (@params == 1) {
        ($file)=@params;
    }
    return unless defined $file;

    if ($negate) {
        return $self->does_file_exist($file) ? 0 : 1;
    } else {
        return $self->does_file_exist($file) ? 1 : 0;
    }
}

sub does_file_exist {
    my $self=shift;
    my $file=shift;

    $self->pathname(\$file);

    if ($file =~ m|^/|) {
        return -e $file ? 1 : 0;
    } else {
        my $map=$self->map();
        my $sr=$self->Directives('ServerRoot');
        my $server_root=$sr->server_root(map=>$map)
            or return;
        return -e $server_root . "/$file" ? 1 : 0;
    }
}

1;
