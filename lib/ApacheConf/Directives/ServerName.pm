#!/usr/bin/env perl

package ApacheConf::Directives::ServerName;
use warnings;
use strict;
use FindBin qw( $Bin );
use lib "$Bin/lib/perl5";
use lib "$Bin/lib";
use ApacheConf::Directives::Common;
use Data::Dumper;
use Sys::Hostname;

sub main {
    my $class=shift;
    my $self=$class->new(@_);
}

sub __init {
    my $self=shift;
    $self->resolve_server_names(forks=>200);
}

sub resolve_server_names {
    my $self=shift;
    my $args={@_};
    my $forks=$args->{'forks'};

    my $parser=$self->Parser('Apache');
    my $httpdconf=$parser->load_conf_cached
        or return;
    my $results=$self->key2values(data=>$httpdconf, key=>'ServerName')
        or return;

    my $hosts={};
    for my $result (@{$results}) {
        my ($map, $value)=@{$result}{qw(map value)};
        for my $params (@{$value}) {
            my $parsed=$self->parse(params=>$params, resolve=>0)
                or next;
            $hosts->{$parsed->{'host'}}=1;
        }
    }

    my $run=<<'EOF';
        my $ips=$self->resolve($item);
        $return->{$item}=$ips;
EOF

    my $rof=<<'EOF';
        my ($pid, $exit_code, $ident, $exit_signal, $core_dump, $batch_return) = @_;
        %{$return}=(%{$return}, %{$batch_return});
EOF

    my $dns=$self->run_in_batches(
        list            => [keys %{$hosts}],
        forks           => $forks,
        run             => $run,
        run_on_finish   => $rof,
    )   or return;

    $self->dns_cache(batch=>$dns);
}

sub parse {
    my $self=shift;
    my $args={@_};
    my $params=$args->{'params'};
    my $resolve=$args->{'resolve'};

    my $parsed=$self->url_parse(url=>$params, resolve=>$resolve);

    return $parsed;
}

sub server_name {
    my $self=shift;
    my $args={@_};
    my $map=$args->{'map'};

    my $parser=$self->Parser('Apache');
    my $return;

    SERVER_NAME: {
        if (defined $map and grep $_ eq 'VirtualHost', @{$map}) {
            my $valid=$parser->find_valid_directives(directive=>'ServerName', map=>$map)
                or return;
            @{$valid}
                or $return=hostname and last SERVER_NAME;

            $return=$valid->[-1]->{'value'} and last SERVER_NAME;
        }

        $return=$self->root_server_name and last SERVER_NAME;
    }

    my $ips=$self->resolve($return);

    return @{$ips} ? $return : hostname;
}

sub root_server_name {
    my $self=shift;

    my $parser=$self->Parser('Apache');

    my $valid=$parser->find_valid_directives(directive=>'ServerName')
        or return;

    if (@{$valid}) {
        my @root_server_names=();
        for my $meta (@{$valid}) {
            my ($map, $value)=@{$meta}{qw(map value)};
            next if grep $_ eq 'VirtualHost', @{$map};
            push @root_server_names, $value;
        }

        if (@root_server_names) {
            return $root_server_names[-1];
        }
    }

    return hostname;
}

1;
