#!/usr/bin/env perl

package ApacheConf::Directives::IfDefine;
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
                                $RE{'CUSTOM'}{'HTTPD'}{'SERVER_PARAM'}{'-keep'}
                            )
                        /xi;

    my ($negate, $server_param);
    if (@params == 2) {
        ($negate, $server_param)=@params;
    } elsif (@params == 1) {
        ($server_param)=@params;
    }
    return unless defined $server_param;

    if ($negate) {
        return $self->is_server_param_defined($server_param) ? 0 : 1;
    } else {
        return $self->is_server_param_defined($server_param) ? 1 : 0;
    }
}

sub is_server_param_defined {
    my $self=shift;
    my $param=shift;

    my $parser=$self->Parser('Apache');
    my $params=$parser->params()
        or return;

    return $params->{$param} ? 1 : 0;
}

1;
