#!/usr/bin/env perl

package ApacheConf::Directives::IfVersion;
use warnings;
use strict;
use FindBin qw( $Bin );
use lib "$Bin/lib/perl5";
use lib "$Bin/lib";
use ApacheConf::Directives::Common;
use version;

sub main {
    my $class=shift;
    my $self=$class->new(@_);

    my $params=$self->params();

    my $regexp;
    my @params=grep { defined and length }
                    $params =~
                        /^(\x21)?\s*+([=><]=?|~)\s*+
                            (?>
                                $RE{'CUSTOM'}{'GENERAL'}{'DELIMITED'}{'-delim'=>"'"}{'-keep'}|
                                $RE{'CUSTOM'}{'GENERAL'}{'DELIMITED'}{'-delim'=>'"'}{'-keep'}|
                                $RE{'CUSTOM'}{'GENERAL'}{'DELIMITED'}{'-delim'=>"\x2F"}{'-i'}{'-keep'}|
                                (\S++)
                            )
                        /xi;

    my ($negate, $operator, $version);
    if (@params == 3) {
        ($negate, $operator, $version)=@params;
    } elsif (@params == 2) {
        ($operator, $version)=@params;
    }
    return unless defined $operator and defined $version;

    if ($operator eq '~') {
        $regexp=$version;
    } elsif (defined $5 and $operator =~ /^==?$/) {
        $regexp=$version;
    }

    my $server_version=$self->version()
        or return;

    if ($regexp) {
        if ($negate) {
            return $self->compare_regexp($server_version, $regexp) ? 0 : 1;
        } else {
            return $self->compare_regexp($server_version, $regexp) ? 1 : 0;
        }
    } else {
        if ($negate) {
            return $self->compare($server_version, $operator, $version) ? 0 : 1;
        } else {
            return $self->compare($server_version, $operator, $version) ? 1 : 0;
        }
    }
}

sub compare {
    my $self=shift;
    my $a=shift;
    my $b=shift;
    my $op=shift;

    $a =~ s/^(?!v)/v/;
    $b =~ s/^(?!v)/v/;
    $op =~ s/^=$/==/;

    $a =~ /^\d++(?>\.\d++)*+$/
        or return;
    $b =~ /^\d++(?>\.\d++)*+$/
        or return;
    $op =~ /^[=><]=?$/
        or return;

    my $cmp=q{version->parse($a) $op version->parse($b)};

    return eval $cmp ? 1 : 0;
}

sub compare_regexp {
    my $self=shift;
    my $a=shift;
    my $b=shift;

    return $a =~ /$b/ ? 1 : 0;
}

sub version {
    my $self=shift;

    return $self->{'version'}
        if defined $self->{'version'};

    my $run=$self->shell('httpd -v');

    return
        if $run->{'exit_code'}
        or not $run->{'stdout'};

    ($self->{'version'})=$run->{'stdout'} =~ m|server\sversion:\sapache/(\d++(?>\.\d++)*+)(?![\.\d])|mi;

    return $self->{'version'};
}

1;
