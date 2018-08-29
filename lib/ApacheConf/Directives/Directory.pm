#!/usr/bin/env perl

package ApacheConf::Directives::Directory;
use warnings;
use strict;
use FindBin qw( $Bin );
use lib "$Bin/lib/perl5";
use lib "$Bin/lib";
use ApacheConf::Directives::Common;
use Text::Glob qw(match_glob glob_to_regex);

sub main {
    my $class=shift;
    my $self=$class->new(@_);

    my $request=$self->request
        or return;
    my $path=$request->{'path'}
        or return;
    my $params=$self->params()
        or return;

    my @params=grep { defined and length }
                    $params =~
                        /^(\x7E)?\s*+
                            (?>
                                $RE{'CUSTOM'}{'GENERAL'}{'DELIMITED'}{'-delim'=>"'"}{'-keep'}|
                                $RE{'CUSTOM'}{'GENERAL'}{'DELIMITED'}{'-delim'=>'"'}{'-keep'}|
                                $RE{'CUSTOM'}{'BASH'}{'PATH'}{'-keep'}
                            )
                        /xi;

    my ($regexp, $dir);
    if (@params == 2) {
        ($regexp, $dir)=@params;
    } elsif (@params == 1) {
        ($dir)=@params;
    }
    return unless defined $dir;

    return $regexp ? $self->is_path_in_regexp(path=>$path, regexp=>$regexp) : $self->is_path_in_dir(path=>$path, dir=>$dir);
}

sub is_path_in_dir {
    my $self=shift;
    my $args={@_};
    my $dir=$args->{'dir'};
    my $path=$args->{'path'};

    my $dir_depth=$dir =~ tr[/][];
    my $path_depth=$path =~ tr[/][];

    return 0
        if $path_depth < $dir_depth;

    return 1
        if $dir eq '/';

    my $x=join('/', (split(m|/|, $path))[0..$dir_depth]);

    return match_glob($dir, $x) ? 1 : 0;
}

sub is_path_in_regexp {
    my $self=shift;
    my $args={@_};
    my $regexp=$args->{'regexp'};
    my $path=$args->{'path'};

    return $path =~ /$regexp/ ? 1 : 0;
}

sub get_sections_by_url {
    my $self=shift;
    my $url=shift;

    my $parser=$self->Parser('Apache');
    my $path=$parser->url2path($url);
    my $conf=$parser->load_conf_cached();

    my $return=[];

    while (my ($dir, $sections)=each %{$conf->{'Directory'}}) {
        push @{$return}, map({ dir=>$dir, section=>$_ }, @{$sections})
            if $self->is_path_in_dir(path=>$path, dir=>$dir);
    }

    @{$return}=sort { $a->{'dir'} =~ tr[/][] <=> $b->{'dir'} =~ tr[/][] } @{$return};

    return $return;
}

1;
