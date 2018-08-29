package ApacheConf;

use warnings;
use strict;
use FindBin qw( $Bin );
use lib "$Bin/lib/perl5";
use lib "$Bin/lib";
use ApacheConf::Common;
use ApacheConf::htaccess;
use ApacheConf::Directives;
use ApacheConf::Parser;
use ApacheConf::Handlers;
use ApacheConf::CLI;
use Devel::Refcount qw(refcount);
use Data::Dumper;

our $Uid=0;
our $Instances={};

sub main {
    my $class=shift;
    my $self=$class->new();
}

sub _init {
    my $self=shift;
    my $url=shift;
    if (defined $url) {
        $url = 'http://localhost'
            unless $url =~ /^$RE{'CUSTOM'}{'NETWORK'}{'FQDN'}{'-i'}$/;
    } else {
        $url = 'http://localhost';
    }
    $self->url($url);
    for my $uid (keys %{$ApacheConf::Instances}) {
        delete $ApacheConf::Instances->{$uid}
            if refcount($ApacheConf::Instances->{$uid}) == 1;
    }
    $self->{'uid'}=$ApacheConf::Uid;
    $ApacheConf::Instances->{$ApacheConf::Uid}=$self;
    $Uid++;

    $self->request();
    return $self;
}

sub new {
    my $class=shift;
    my $url=shift;
    my $self={@_};

    bless $self, $class;

    $self->_init($url);

    return $self;
}

sub Directives {
    my $self=shift;
    my $directive=shift;

    return $self->{'Directives'}->{$directive}
        if defined $self->{'Directives'}->{$directive};

    my $class="ApacheConf::Directives::$directive";

    $self->{'Directives'}->{$directive}=$class->new();

    return $self->{'Directives'}->{$directive};
}

sub Parser {
    my $self=shift;
    my $parser=shift;

    return $self->{'Parser'}->{$parser}
        if defined $self->{'Parser'}->{$parser};

    my $class="ApacheConf::Parser::$parser";

    $self->{'Parser'}->{$parser}=$class->new();

    return $self->{'Parser'}->{$parser};
}

sub request {
    my $self=shift;

    return unless defined $self->{'requests'};
    return $self->{'requests'}->[-1];
}

sub uid {
    my $self=shift;

    return $self->{'uid'};
}

sub url {
    my $self=shift;
    my $url=shift;

    if (defined $url) {
        $self->{'url'}=$url;

        my $parsed=$self->url_parse(url=>$url)
            or return;

        push @{$self->{'requests'}}, $parsed;

        return $self->{'url'};
    } else {
        return $self->{'url'};
    }
}

1;
