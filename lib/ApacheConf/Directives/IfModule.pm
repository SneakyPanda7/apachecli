#!/usr/bin/env perl

package ApacheConf::Directives::IfModule;
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
                                (\S++)
                            )
                        /xi;

    my ($negate, $module);
    if (@params == 2) {
        ($negate, $module)=@params;
    } elsif (@params == 1) {
        ($module)=@params;
    }
    return unless defined $module;

    if ($negate) {
        return $self->is_module_loaded($module) ? 0 : 1;
    } else {
        return $self->is_module_loaded($module) ? 1 : 0;
    }
}

sub is_module_loaded {
    my $self=shift;
    my $module=shift;
    my $parser=$self->Parser('Apache')
        or return;

    my $loaded_modules=$parser->loaded_modules();

    return grep($module eq $_, map(@{$_}, @{$loaded_modules->{'files','idents'}})) ? 1 : 0;
}

1;
