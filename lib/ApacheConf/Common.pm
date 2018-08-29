#!/usr/bin/env perl

package ApacheConf::Common;
use warnings;
use strict;
use FindBin qw($Bin);
use lib "$Bin/lib";
use lib "$Bin/lib/perl5";
use parent qw(Exporter);
use ApacheConf;
use Data::Dumper;
use Data::Walk;
use IPC::Open3;
use Parallel::ForkManager;
use POSIX qw(ceil);
use Regexp::Common qw(pattern);
use Socket;
use URI;

use namespace::clean;

my @methods=keys %{namespace::clean->get_functions(__PACKAGE__)};
our @EXPORT=('%RE', @methods);

pattern(
    name    => [qw(CUSTOM GENERAL ESCAPE_CHAR)],
    create  => '(?k:\x5C(?>x[\da-f]{2,}+|.))',
);

pattern(
    name    => [qw(CUSTOM GENERAL DELIMITED)],
    create  => sub {
        my ($self, $flags) = @_;
        my $delim=$flags->{'-delim'};

        my @balanced=qw'( { [ ] } )';

        my $open={
            '(' => ')',
            '{' => '}',
            '[' => ']',
        };

        my $close={
            ')' => '(',
            '}' => '{',
            ']' => '[',
        };

        if (grep $delim eq $_, @balanced) {
            my $hex={};

            if (my $c=$open->{$delim}) {
                my $o=$delim;
                $hex->{'open'}=sprintf('\x%X', ord($o));
                $hex->{'close'}=sprintf('\x%X', ord($c));
            } elsif (my $o=$close->{$delim}) {
                my $c=$delim;
                $hex->{'open'}=sprintf('\x%X', ord($o));
                $hex->{'close'}=sprintf('\x%X', ord($c));
            }

            return $hex->{'open'} . '(?k:(?>' . $RE{'CUSTOM'}{'GENERAL'}{'ESCAPE_CHAR'} . '++|[^' . $hex->{'close'} . '\x5C]++)*?)' . $hex->{'close'};
        } else {
            my $hex=sprintf('\x%X', ord($delim));
            return $hex . '(?k:(?>' . $RE{'CUSTOM'}{'GENERAL'}{'ESCAPE_CHAR'} . '++|[^' . $hex . '\x5C]++)*?)' . $hex;
        }
    },
);

pattern(
    name    => [qw(CUSTOM NETWORK DOMAIN_NAME)],
    create  => '(?k:(?>[a-z\d]++(?>-++[a-z\d]++)*+\.)++[a-z]{2,})',
);

pattern(
    name    => [qw(CUSTOM NETWORK FQDN)],
    create  => '(?k:(?>[a-z\d]++(?>-++[a-z\d]++)*+\.)+[a-z]{2,}\.?)',
);

pattern(
    name    => [qw(CUSTOM NETWORK TLD)],
    create  => '(?k:[a-z]{2,}\.?)',
);

pattern(
    name    => [qw(CUSTOM NETWORK IP)],
    create  => '(?k:(?>(?>25[0-5]|2[0-4]\d|[01]?\d{1,2}+)\.){3}(?>25[0-5]|2[0-4]\d|[01]?\d{1,2}+))',
);

pattern(
    name    => [qw(CUSTOM BASH ESCAPE_CHAR)],
    create  => '(?k:\x5C(?>0[\da-f]{2,}+|.))',
);

pattern(
    name    => [qw(CUSTOM BASH PATH)],
    create  => '(?k:(?>' . $RE{'CUSTOM'}{'BASH'}{'ESCAPE_CHAR'} . '++|[^\s\x5C]++)++)',
);

pattern(
    name    => [qw(CUSTOM HTTPD EXPR VAR)],
    create  => '(?k:\x24' . $RE{'CUSTOM'}{'GENERAL'}{'DELIMITED'}{'-delim'=>'{'}{'-i'} . ')',
);

pattern(
    name    => [qw(CUSTOM HTTPD EXPR OPERATOR BINARY)],
    create  => '(?k:[!=][=~]|[=<>]=?|-(?>eq|ne|[lg][te]|(?>ip|str|strc|fn)match))',
);

pattern(
    name    => [qw(CUSTOM HTTPD EXPR OPERATOR UNARY)],
    create  => '(?k:-[defsLhFUAnzTR])',
);

pattern(
    name    => [qw(CUSTOM HTTPD EXPR FUNCTION)],
    create  => '(?k:req_novary|reqenv|req|http|resp|osenv|note|env|tolower|toupper|unescape|escape|unbase64|base64|md5|sha1|filemod|filesize|file)',
);

pattern(
    name    => [qw(CUSTOM HTTPD EXPR DATA)],
    create  =>  '(?k:' .
                $RE{'CUSTOM'}{'GENERAL'}{'DELIMITED'}{'-delim'=>'"'}{'-i'} . '|' .
                $RE{'CUSTOM'}{'GENERAL'}{'DELIMITED'}{'-delim'=>"'"}{'-i'} . '|' .
                $RE{'CUSTOM'}{'HTTPD'}{'EXPR'}{'OPERATOR'}{'BINARY'} . '|' .
                $RE{'CUSTOM'}{'HTTPD'}{'EXPR'}{'OPERATOR'}{'UNARY'} . '|' .
                $RE{'CUSTOM'}{'HTTPD'}{'EXPR'}{'FUNCTION'} . '|' .
                $RE{'CUSTOM'}{'HTTPD'}{'EXPR'}{'VAR'} . '|' .
                '\S++' .
                ')',
);

pattern(
    name    => [qw(CUSTOM HTTPD SERVER_PARAM)],
    create  => '(?k:[A-Z_\d]++)',
);

sub value2keys {
    my $self=shift;
    my $args={@_};
    my $data=$args->{'data'};
    my $value=$args->{'value'};
    my $results=[];
    my $map=[];
    my $wanted=sub {
        my $node=$_;
        return if $Data::Walk::depth < 2; #Ignore absolute root of data structure
        return unless $Data::Walk::type =~ /^(?>HASH|ARRAY)$/; #Only examine hash or array structures

        if ($Data::Walk::type eq 'HASH') {
            unless ($Data::Walk::index % 2) {
                my $depth=$Data::Walk::depth - 2;
                splice(@{$map}, $depth+1) if defined $map->[$depth+1];
                $map->[$depth]=$node;
            }

            return unless $Data::Walk::index % 2; #Only examine hash values
            return unless $node eq $value;

            my $key=(%{$Data::Walk::container})[$Data::Walk::index - 1];

            push @{$results}, {
                key => $key,
                map => [@{$map}],
            };
        } elsif ($Data::Walk::type eq 'ARRAY') {
            my $depth=$Data::Walk::depth - 2;
            splice(@{$map}, $depth+1) if defined $map->[$depth+1];
            $map->[$depth]=$Data::Walk::index;
        }
    };

    walk $wanted, $data;

    return $results;
}

sub key2values {
    my $self=shift;
    my $args={@_};
    my $data=$args->{'data'};
    my $key=$args->{'key'};

    my $results=[];
    my $map=[];
    my $wanted=sub {
        my $node=$_;
        return if $Data::Walk::depth < 2; #Ignore absolute root of data structure
        return unless $Data::Walk::type =~ /^(?>HASH|ARRAY)$/; #Only examine hash or array structures

        if ($Data::Walk::type eq 'HASH') {
            unless ($Data::Walk::index % 2) {
                my $depth=$Data::Walk::depth - 2;
                splice(@{$map}, $depth+1) if defined $map->[$depth+1];
                $map->[$depth]=$node;
            }

            return if $Data::Walk::index % 2; #Only examine hash keys
            return unless $node eq $key;

            my $value=(%{$Data::Walk::container})[$Data::Walk::index + 1];

            push @{$results}, {
                value   => $value,
                map     => [@{$map}],
            };
        } elsif ($Data::Walk::type eq 'ARRAY') {
            my $depth=$Data::Walk::depth - 2;
            splice(@{$map}, $depth+1) if defined $map->[$depth+1];
            $map->[$depth]=$Data::Walk::index;
        }
    };

    walk $wanted, $data;

    return $results;
}

sub pathname {
    my $self=shift;
    my $path=shift;

    ${$path} =~ s|/{2,}|/|g;
    while(${$path} =~ s|/[^/]++/\.{2}||g) {};
    ${$path} =~ s|(?<!^)/$||;

    return ${$path};
}

sub resolve {
    my $self=shift;
    my $host=shift;

    return [$host]
        if $host =~ /^$RE{'CUSTOM'}{'NETWORK'}{'IP'}$/;

    my $cache=$self->dns_cache(host=>$host);

    return $cache
        if defined $cache;

    my $ips=[];
    my ($err, @addrs) = Socket::getaddrinfo( $host, 0, { 'protocol' => Socket::IPPROTO_TCP, 'family' => Socket::AF_INET } );
    unless ($err) {
        for my $addr (@addrs) {
            my ($err, $ip) = Socket::getnameinfo( $addr->{addr}, Socket::NI_NUMERICHOST );
            unless ($err) {
                push @{$ips}, $ip;
            }
        }
    }

    $self->dns_cache(host=>$host, ips=>$ips);

    return $ips;
}

sub dns_cache {
    my $self=shift;
    my $args={@_};
    my $host=$args->{'host'};
    my $ips=$args->{'ips'};
    my $batch=$args->{'batch'};

    $self->{'dns_cache'} ||= {};

    if (defined $host) {
        if (defined $ips) {
            $self->{'dns_cache'}->{$host}=$ips;
            return $self->{'dns_cache'}->{$host};
        } else {
            return $self->{'dns_cache'}->{$host};
        }
    } elsif (defined $batch) {
        %{$self->{'dns_cache'}}=(%{$self->{'dns_cache'}}, %{$batch});
        return $self->{'dns_cache'};
    } else {
        return $self->{'dns_cache'};
    }
}

sub shell {
    my $self=shift;
    my $cmd=shift;
    my ($stdout, $stderr, $exit_code);
    my $bash="cat | /bin/bash";

    my $pid=open3(\*IN, \*OUT, \*ERR, $bash);
    print IN $cmd;
    close IN;
    $stdout = eval {join '', <OUT>} || '';
    close OUT;
    $stderr = eval {join '', <ERR>} || '';
    close ERR;
    waitpid($pid, 0);

    $self->strip(\$stdout) if defined $stdout and length $stdout;
    $self->strip(\$stderr) if defined $stderr and length $stderr;

    $exit_code=$? >> 8;

    return {
        'cmd'       => $cmd,
        'stdout'    => $stdout,
        'stderr'    => $stderr,
        'exit_code' => $exit_code,
    };
}

sub strip {
    my $self=shift;
    my $data=shift;
    my $type=shift;
    if (not defined $type) {
        ${$data} =~ s/^\s++|\s++$//g;
    } else {
        ${$data} =~ s/^\s++// if $type eq 'left';
        ${data} =~ s/\s++$// if $type eq 'right';
    }
    return ${$data};
}

sub url_parse {
    my $self=shift;
    my $args={@_};
    my $url=$args->{'url'};
    my $resolve=defined $args->{'resolve'} ? $args->{'resolve'} : 1;

    if ($url =~ /^$RE{'CUSTOM'}{'NETWORK'}{'FQDN'}{'-i'}$/) {
        $url =~ s|^|http://|;
    }

    return unless $RE{'URI'}{'HTTP'}->matches($url);
    my $uri=URI->new($url);

    my $ssl=$uri->scheme =~ m|^https$| ? 1 : 0;
    my $host=$uri->authority;
    my $path=$self->pathname(\$uri->path);
    my $port=$uri->port;
    my $ips=$resolve ? $self->resolve($host) : [];

    return {
        url     => $url,
        ssl     => $ssl,
        host    => $host,
        path    => $path,
        port    => $port,
        ip      => $ips->[0],
    };
}

sub run_in_batches {
    my $self=shift;
    my $args={@_};
    my $run=$args->{'run'};
    my $list=$args->{'list'};
    my $forks=$args->{'forks'};
    my $ros=$args->{'run_on_start'};
    my $row=$args->{'run_on_wait'};
    my $rof=$args->{'run_on_finish'};
    my $batch_size=ceil(scalar(@{$list}) / $forks);
    my $batches=$self->batches(list=>$list, batch_size=>$batch_size)
        or return;

    my $return={};

    my $pm = new Parallel::ForkManager($forks);
    $pm->run_on_start   (sub { eval $ros; })
        if defined $ros;
    $pm->run_on_wait    (sub { eval $row; })
        if defined $row;
    $pm->run_on_finish  (sub { eval $rof; })
        if defined $rof;

    for my $batch (@{$batches}) {
        $pm->start()
            and next;

        my $return={};
        for my $item (@{$batch}) {
            eval $run;
        }

        $pm->finish(0, $return);
    }

    $pm->wait_all_children;

    return $return;
}

sub batches {
    my $self=shift;
    my $args={@_};
    my $list=$args->{'list'};
    my $batch_size=$args->{'batch_size'};

    my @batches;
    while (@{$list}) {
        my @batch;
        for (my $x=0; $x < $batch_size; $x++) {
            my $host=shift @{$list};
            last unless defined $host;
            push @batch, $host;
        }
        push @batches, [@batch];
    }

    return [@batches];
}

1;
