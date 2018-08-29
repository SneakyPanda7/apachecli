#!/usr/bin/env perl

package ApacheConf::Common::Shell;
use warnings;
use strict;
use parent qw(ApacheConf::Common);
use ApacheConf::Common;
use UNIVERSAL;

my @methods=keys %{namespace::clean->get_functions(__PACKAGE__)};
our @EXPORT=('%RE', @methods);

sub new {
    my $class=shift;
    my $self={@_};

    bless $self, $class;

    $self->_init();

    return $self;
}

sub _init {
    my $self=shift;
    $self->_core();

    my $override=$self->can('__init');
    $override->($self)
        if defined $override;

    return $self;
}

sub _core {
    my $self=shift;

    return $self->{'core'}
        if defined $self->{'core'};

    my $uid=(sort { $a <=> $b } keys %{$ApacheConf::Instances})[-1];
    if (defined $uid) {
        $self->{'core'}=$ApacheConf::Instances->{$uid};
    } else {
        $self->{'core'}=ApacheConf->new();
    }

    return $self->{'core'};
}

sub Directives {
    my $self=shift;

    return $self->_core->Directives(@_);
}

sub Parser {
    my $self=shift;

    return $self->_core->Parser(@_);
}

sub uid {
    my $self=shift;

    return $self->_core->uid(@_);
}

sub url {
    my $self=shift;

    return $self->_core->url(@_);
}

1;
