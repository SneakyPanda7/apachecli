#!/usr/bin/env perl

package ApacheConf::Directives::IfDirective;
use warnings;
use strict;
use FindBin qw( $Bin );
use lib "$Bin/lib/perl5";
use lib "$Bin/lib";
use ApacheConf::Directives::Common;

sub main {
    my $class=shift;
    my $self=$class->new(@_);

    my $params=$self->params();

    my @params=grep { defined and length }
                    $params =~
                        /^(\x21)?\s*+
                            (?>
                                $RE{'CUSTOM'}{'GENERAL'}{'DELIMITED'}{'-delim'=>"'"}{'-keep'}|
                                $RE{'CUSTOM'}{'GENERAL'}{'DELIMITED'}{'-delim'=>'"'}{'-keep'}|
                                (\S++)
                            )
                        /xi;

    my ($negate, $directive);
    if (@params == 2) {
        ($negate, $directive)=@params;
    } elsif (@params == 1) {
        ($directive)=@params;
    }
    return unless defined $directive;

    if ($negate) {
        return $self->is_directive_available($directive) ? 0 : 1;
    } else {
        return $self->is_directive_available($directive) ? 1 : 0;
    }
}

sub is_directive_available {
    my $self=shift;
    my $directive=shift;
    my $parser=$self->Parser('Apache')
        or return;

    return grep $directive, @{$parser->available_directives} ? 1 : 0;
}

1;
