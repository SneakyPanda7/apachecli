#!/usr/bin/env perl

package ApacheConf::Parser::Apache;
use warnings;
use strict;
use FindBin qw( $Bin );
use lib "$Bin/lib";
use lib "$Bin/lib/perl5";
use ApacheConf::Common::Shell;
use ApacheConf::Config::General;
use Data::Dumper;
use File::Slurp;
use Tie::DxHash;

sub main {
    my $class=shift;
    my $self=$class->new();
}

sub available_sections {
    my $self=shift;

    return $self->{'available_sections'}
        if defined $self->{'available_sections'};

    my $run=$self->shell('httpd -L')
        or return;

    return
        if $run->{'exit_code'}
        or not $run->{'stdout'};

    $self->{'available_sections'}=[];
    push @{$self->{'available_sections'}}, $run->{'stdout'} =~ /^<(\S++)/gmc;

    return $self->{'available_sections'};
}

sub available_directives {
    my $self=shift;

    return $self->{'available_directives'}
        if defined $self->{'available_directives'};

    my $run=$self->shell('httpd -L')
        or return;

    return
        if $run->{'exit_code'}
        or not $run->{'stdout'};

    $self->{'available_directives'}=[];
    push @{$self->{'available_directives'}}, $run->{'stdout'} =~ /^<?(\S++)/gmc;

    return $self->{'available_directives'};
}

sub cmd_line_opts {
    my $self=shift;
    my $return=[];

    my $proc=$self->root_httpd_proc()
        or return;

    my $x   =   join "\x00",
                grep    { defined and length }
                map     { /^(-[a-z])?(.*)/gi }
                splice(@{[split(/\x00/, $proc->{'cmd'})]}, 1);

    $x =~ s/(?:\A|\x00)\K(-.)(?!\x00[^-])/$1\x001/;

    my @opts=split /\x00/, $x;
    return if @opts % 2;

    push @{$return}, {splice (@opts, 0, 2)} while @opts;

    return $return;
}

sub config_file {
    my $self=shift;

    my $params=$self->params()
        or return;

    my $httpd_root=$self->pathname(\$params->{'HTTPD_ROOT'});
    my $server_config_file=$self->pathname(\$params->{'SERVER_CONFIG_FILE'});

    return $httpd_root . '/' . $server_config_file;
}

sub find_valid_sections {
    my $self=shift;
    my $args={@_};
    my $section=$args->{'section'};
    my $contains=$args->{'contains'};

    my $httpdconf=$self->load_conf_cached()
        or return;
    my $results=$self->key2values(data=>$httpdconf, key=>$section)
        or return;

    my $found=[];
    if (defined $contains and ref $contains eq 'HASH' and keys %{$contains}) {
        for my $result (@{$results}) {
            my ($section, $section_map)=@{$result}{qw(value map)};
            next unless $self->is_directive_valid(map=>$section_map);
            next unless ref $section eq 'HASH';
            my $hits={};
            while (my ($key, $value)=each %{$contains}) {
                my $results=$self->key2values(data=>$section, key=>$key);
                for my $result (@{$results}) {
                    my ($directive_values, $directives_partial_map)=@{$result}{qw(value map)};
                    my $directives_map=[@{$section_map}, @{$directives_partial_map}];
                    next unless $self->is_directive_valid(map=>$directives_map);
                    next if ref $directive_values->[-1];
                    $hits->{join("\x00", @{$section_map}, @{$directives_partial_map}[0..1])}->{$key}++
                        if $directive_values->[-1] eq $value;
                }
            }
            for my $map (keys %{$hits}) {
                my @found_keys=sort { $a cmp $b } keys %{$hits->{$map}};
                my @required_keys=sort { $a cmp $b } keys %{$contains};
                next if "@found_keys" ne "@required_keys";
                my $ref=$httpdconf;
                my $map=[split /\x00/, $map];
                my $section=$self->map2conf($map);
                push @{$found}, {
                    map     => $map,
                    value   => $section,
                };
            }
        }
    } else {
        push @{$found}, @{$results};
    }

    return $found;
}

sub find_valid_directives {
    my $self=shift;
    my $args={@_};
    my $directive=$args->{'directive'};
    my $map=$args->{'map'};

    my $section;
    if (defined $map) {
        $section=$self->map2conf($map);
    } else {
        $section=$self->load_conf_cached()
            or return;
    }

    my $results=$self->key2values(data=>$section, key=>$directive)
        or return;

    my $found=[];
    for my $result (@{$results}) {
        my ($values, $map)=@{$result}{qw(value map)};
        unshift @{$map}, @{$args->{'map'}}
            if defined $args->{'map'};
        for my $value (@{$values}) {
            push @{$found}, {
                map     => $map,
                value   => $value,
            } if $self->is_directive_valid(map=>$map);
        }
    }

    return $found;
}

sub httpd_binary {
    my $self=shift;

    return $self->{'httpd_binary'}
        if defined $self->{'httpd_binary'};

    my $run=$self->shell('which httpd');

    return
        if $run->{'exit_code'}
        or not $run->{'stdout'};

    $self->{'httpd_binary'}=$run->{'stdout'};

    return $self->{'httpd_binary'};
}

sub is_directive_valid {
    my $self=shift;
    my $args={@_};
    my $map=$args->{'map'};

    my $x;
    my @y = grep {++$x % 3} splice(@{[@{$map}]}, 0, -1);
    my $sections={};
    tie %{$sections}, "Tie::DxHash";
    %{$sections}=@y;

    my $valid=1;
    while (my ($directive, $params)=each %{$sections}) {
        my $success=eval 'ApacheConf::Directives::' . $directive . '->main(params=>$params, map=>$map);';
        unless ($@) {
            $valid=0 unless $success;
        }
    }

    return $valid;
}

sub load_conf {
    my $self=shift;
    my $return={};
    tie %{$return}, "Tie::DxHash";

    my $file=$self->config_file
        or return;
    -r $file
        or return;

    my $conf=eval {ApacheConf::Config::General->new(
        -ConfigFile         =>$file,
        -ApacheCompatible   => 1,
        -Tie                => "Tie::DxHash",
        -ForceValueArray    => 1,
        -ForceBlockArray    => 1,
        -ForceBlockName     => 1,
    )} or return;

    %{$return}=$conf->getall;

    return $return;
}

sub load_conf_cached {
    my $self=shift;

    return $self->{'load_conf_cached'}
        if defined $self->{'load_conf_cached'};

    $self->{'load_conf_cached'}=$self->load_conf();

    return $self->{'load_conf_cached'};
}

sub loaded_modules {
    my $self=shift;

    return $self->{'loaded_modules'}
        if defined $self->{'loaded_modules'};

    $self->{'loaded_modules'}={};
    my $run;

    $run=$self->shell('httpd -M');
    return
        if $run->{'exit_code'}
        or not $run->{'stdout'};
    my $httpd_m=$run->{'stdout'};

    $run=$self->shell('httpd -l');
    return
        if $run->{'exit_code'}
        or not $run->{'stdout'};
    my $httpd_l=$run->{'stdout'};

    my @idents=();
    push @idents, $1 while $httpd_m =~ s/^loaded\smodules:\n\K\s++(\S++).*+\n?//im;

    my @static_files=();
    push @static_files, $1 while $httpd_l =~ s/^compiled\sin\smodules:\n\K\s++(\S++).*+\n?//im;

    push @{$self->{'loaded_modules'}->{'files'}}, @static_files;
    push @{$self->{'loaded_modules'}->{'idents'}}, @idents;

    my $shared_files={};
    my $httpdconf=$self->load_conf_cached();
    my $results=$self->key2values(data=>$httpdconf, key=>'LoadModule');
    for my $ident (@idents) {
        for my $result (@{$results}) {
            for my $value (@{$result->{'value'}}) {
                next unless $value =~ m|^(\S++).*?([^/\s]++)$|;
                $shared_files->{$2}=1
                    if $ident eq $1;
            }
        }
    }

    push @{$self->{'loaded_modules'}->{'files'}}, keys %{$shared_files};

    return $self->{'loaded_modules'};
}

sub map2conf {
    my $self=shift;
    my $map=shift;
    my $httpdconf=$self->load_conf_cached();
    my $ref=$httpdconf
        or return;
    for my $index (@{$map}) {
        if (ref $ref eq 'HASH') {
            $ref=$ref->{$index};
        } elsif (ref $ref eq 'ARRAY') {
            $ref=$ref->[$index];
        }
    }

    return $ref;
}

sub params {
    my $self=shift;

    return $self->{'params'}
        if defined $self->{'params'};

    $self->{'params'}={};

    my $run=$self->shell('httpd -V');

    return
        if $run->{'exit_code'}
        or not $run->{'stdout'};

    my $httpd_v=$run->{'stdout'};

    $self->{'params'}->{$1}=defined $2 ? $2 : 1
        while $httpd_v =~ s/^(?i:server\scompiled\swith).*+\n\K\s++-D\s++$RE{'CUSTOM'}{'HTTPD'}{'SERVER_PARAM'}{'-keep'}(?>=$RE{'CUSTOM'}{'GENERAL'}{'DELIMITED'}{'-delim'=>'"'}{'-i'}{'-keep'})?.*+\n?//m;

    my $opts=$self->cmd_line_opts()
        or return;

    for my $opt (@{$opts}) {
        while (my ($option, $option_value)=each %{$opt}) {
            next unless $option eq '-D';
            my ($param, $param_value)=grep(defined, $option_value =~ /^$RE{'CUSTOM'}{'HTTPD'}{'SERVER_PARAM'}{'-keep'}(?>=(?>$RE{'CUSTOM'}{'GENERAL'}{'DELIMITED'}{'-delim'=>'"'}{'-i'}{'-keep'}|$RE{'CUSTOM'}{'GENERAL'}{'DELIMITED'}{'-delim'=>"'"}{'-i'}{'-keep'}|(\S++)))?$/);
            $self->{'params'}->{$param}=defined $param_value ? $param_value : 1;
        }
    }

    return $self->{'params'};
}

sub root_httpd_proc {
    my $self=shift;

    return $self->{'root_httpd_proc'}
        if defined $self->{'root_httpd_proc'};

    my $run;
    $self->{'root_httpd_proc'}={};

    my $httpd=$self->httpd_binary();

    $run=$self->shell("pgrep -f -U 0 -o '^$httpd'");

    return
        if $run->{'exit_code'}
        or not $run->{'stdout'};

    my $pid=$run->{'stdout'};
    my $cmd=read_file("/proc/$pid/cmdline");

    $self->{'root_httpd_proc'}->{'pid'}=$pid;
    $self->{'root_httpd_proc'}->{'cmd'}=$cmd;

    return $self->{'root_httpd_proc'};
}

sub url2path {
    my $self=shift;
    my $url=shift;
    my $parsed=$self->url_parse(url=>$url)
        or return;

    my $vh=$self->Directives('VirtualHost');
    my $vhost=$vh->url2vhost($url);

    my $path;
    my $webroot;
    if (defined $vhost) {
        my $results=$self->find_valid_directives(directive=>'DocumentRoot', map=>$vhost->{'map'})
            or return;
        return unless @{$results};
        $webroot=$results->[-1]->{'value'};
    } else {
        my $sn=$self->Directives('ServerName');
        my $root_server_name=$sn->root_server_name
            or return;
        if ($parsed->{'host'} eq $root_server_name) {
            my $dr=$self->Directives('DocumentRoot');
            my $root_document_root=$dr->root_document_root;
            $webroot=$root_document_root;
        }
    }

    return unless defined $webroot;

    $path=$webroot . '/' . $parsed->{'path'};
    $self->pathname(\$path);

    return $path;
}

#sub webroot {
#    my $self=shift;
#    my $args={@_};

#    while (my ($key, $value)=each %{$args}) {
#        my $results=$self->find_valid_directives($key);
#        for my $result (@$results) {
            
#    }

1;
