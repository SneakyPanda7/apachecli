#!/usr/bin/env perl

package ApacheConf::Directives::VirtualHost;
use warnings;
use strict;
use FindBin qw( $Bin );
use lib "$Bin/lib/perl5";
use lib "$Bin/lib";
use ApacheConf::Directives::Common;
use Data::Dumper;
use Text::Glob qw(match_glob);

sub main {
    my $class=shift;
    my $self=$class->new(@_);
}

sub url2vhost {
    my $self=shift;
    my $url=shift;
    my $parsed=$self->url_parse(url=>$url);
    my $vhosts=$self->vhost_address_set()
        or return;

    for my $wildcard (qw(non_wildcard wildcard)) {
        for my $type (qw(ip_based name_based)) {
            if (defined $vhosts->{$wildcard} and defined $vhosts->{$wildcard}->{$type}) {
                while (my ($ip, $x)=each %{$vhosts->{$wildcard}->{$type}}) {
                    if ($wildcard eq 'non_wildcard') {
                        next unless $ip eq $parsed->{'ip'};
                    } else {
                        next unless match_glob($ip, $parsed->{'ip'});
                    }
                    while (my ($port, $y)=each %{$x}) {
                        if ($wildcard eq 'non_wildcard') {
                            next unless $port eq $parsed->{'port'};
                        } else {
                            next unless match_glob($port, $parsed->{'port'});
                        }
                        for my $section_meta (@{$y}) {
                            my ($map, $section, $names)=@{$section_meta}{qw(map section names)};
                            if ($type eq 'name_based' and grep(match_glob($_, $parsed->{'host'}), @{$names})) {
                                return {
                                    map     => $map,
                                    value   => $section,
                                };
                            } elsif ($type eq 'ip_based') {
                                return {
                                    map     => $map,
                                    value   => $section,
                                };
                            }
                        }
                    }
                }
            }
        }
    }
}

sub map2names {
    my $self=shift;
    my $args={@_};
    my $map=$args->{'map'};

    my $parser=$self->Parser('Apache');
    my $sn=$self->Directives('ServerName');
    my $sa=$self->Directives('ServerAlias');

    my @names=();

    my $vhost_params=$map->[-2];
    my @vhost_set=split /\s++/, $vhost_params;
    my $server_name_params=$sn->server_name(map=>$map);

    my $server_name;
    if (grep /^_default_/, @vhost_set) {
        my $root_server_name_params=$sn->root_server_name
            or return;
        my $root_server_name_params_parsed=$sn->parse(params=>$root_server_name_params, resolve=>0)
            or return;
        $server_name=$root_server_name_params_parsed->{'host'};
    } elsif (defined $server_name_params) {
        my $server_name_params_parsed=$sn->parse(params=>$server_name_params, resolve=>0)
            or return;
        $server_name=$server_name_params_parsed->{'host'};
    } else {
        my $first=$vhost_set[0];
        my ($host)=split /:/, $first;
        $server_name=$host;
    }

    push @names, $server_name;

    my $server_alias_params=$sa->server_aliases(map=>$map)
        or return;
    for my $params (@{$server_alias_params}) {
        my @hosts=split /\s++/, $params;
        push @names, @hosts;
    }

    return [@names];
}

sub vhost_address_set {
    my $self=shift;
    my $args={@_};
    my $parser=$self->Parser('Apache');
    my $results=$parser->find_valid_sections(section=>'VirtualHost')
        or return;

    my $vhosts={};
    for my $meta (@{$results}) {
        while (my ($params, $sections)=each %{$meta->{'value'}}) {
            my @x=();
            for (my $i=0; $i < @{$sections}; $i++) {
                my $section=$sections->[$i];
                my $map=[@{$meta->{'map'}}, $params, $i];
                my $names=$self->map2names(map=>$map);
                push @x, { map=>$map, section=>$section, names=>$names };
            }
            $sections=[@x];

            my @set=split /\s++/, $params;
            for my $address (@set) {
                my $hosts=[];
                my $port;

                my ($x, $y)=split /:/, $address;
                if ($x =~ /^(?>\*|_default_)$/) {
                    push @{$hosts}, '*';
                } else {
                    $hosts=$self->resolve($x);
                }
                $port=defined $y ? $y : '*';

                for my $host (@{$hosts}) {
                    my $wildcard=0;
                    $wildcard=1 if $host eq '*' or $port eq '*';

                    if ($wildcard) {
#                        push @{$vhosts->{'all'}->{$resolved}}, @{$sections};
#                        push @{$vhosts->{'wildcard'}->{'all'}->{$host}->{$port}}, @{$sections};
                        if (1 < @{$sections}) {
                            push @{$vhosts->{'wildcard'}->{'name_based'}->{$host}->{$port}}, @{$sections};
                        } else {
                            push @{$vhosts->{'wildcard'}->{'ip_based'}->{$host}->{$port}}, @{$sections};
                        }
                    } else { 
#                        push @{$vhosts->{'all'}->{$resolved}}, @{$sections};
#                        push @{$vhosts->{'non_wildcard'}->{'all'}->{$host}->{$port}}, @{$sections};
                        if (1 < @{$sections}) {
                            push @{$vhosts->{'non_wildcard'}->{'name_based'}->{$host}->{$port}}, @{$sections};
                        } else {
                            push @{$vhosts->{'non_wildcard'}->{'ip_based'}->{$host}->{$port}}, @{$sections};
                        }
                    }
                }
            }
        }
    }

    return $vhosts;
}

1;
