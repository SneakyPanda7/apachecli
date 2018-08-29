#!/usr/bin/env perl

package ApacheConf::Directives::IfSection;
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

    my ($negate, $section);
    if (@params == 2) {
        ($negate, $section)=@params;
    } elsif (@params == 1) {
        ($section)=@params;
    }
    return unless defined $section;

    if ($negate) {
        return $self->is_section_available($section) ? 0 : 1;
    } else {
        return $self->is_section_available($section) ? 1 : 0;
    }
}

sub is_section_available {
    my $self=shift;
    my $section=shift;
    my $parser=$self->Parser('Apache')
        or return;

    return grep $section, @{$parser->available_sections} ? 1 : 0;
}

1;
