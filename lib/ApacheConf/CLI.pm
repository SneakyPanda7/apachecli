#!/usr/bin/env perl

package ApacheConf::CLI;
use warnings;
use strict;
use FindBin qw( $Bin );
use lib "$Bin/lib/perl5";
use lib "$Bin/lib";
use ApacheConf::CLI::Methods;
use Class::Inspector;
use Config::Simple;
use Data::Dumper;
use DBI;
use File::Path qw(make_path);
use JSON::PP;
use Term::ANSIColor qw(:constants);
use Text::Table::Any;
use UNIVERSAL;

#__PACKAGE__->main();

sub main {
    my $class=shift;
    my $self=$class->new();

    my $command=$self->read_command;
    my $return=$self->run($command);
    $self->display($return);
}

sub new {
    my $class=shift;
    my $self={@_};

    bless $self, $class;

    return $self;
}

sub config {
    my $self=shift;

    return $self->{'config'}
        if defined $self->{'config'};

    my $cfg=new Config::Simple($Bin . '/../config/apachecli.cfg');

    $self->{'config'}->{'directories'}=$cfg->get_block('directories');

    for my $directory (values %{$self->{'config'}->{'directories'}}) {
        eval {make_path($directory, {owner => 'root', group => 'root'})};
    }

    return $self->{'config'};
}

sub data_types {
    my $self=shift;

    return $self->{'data_types'}
        if defined $self->{'data_types'};

    $self->{'data_types'}={
        bool                => '[01]',
        int                 => '\d++',
        int_comparison      => '(?>g[te]|l[te]|eq|ne):\d++',
        float               => '\d++\.\d++',

        brand               => 'bluehost|justhost|hostmonster|fastdomain',
        cpuser              => '[a-z\d]{1,10}',
        format              => 'table|csv|json|data_dump|string',
        home                => 'home[\d]++',
        hostname            => '(?>[a-z\d]++(?>-++[a-z\d]++)*+\.)++[a-z]{2,}',
        ip                  => '(?>(?>25[0-5]|2[0-4]\d|[01]?\d{1,2}+)\.){3}(?>25[0-5]|2[0-4]\d|[01]?\d{1,2}+)',
        identifier          => '[A-Za-z_][A-Za-z\d_]*+',
        region              => 'provo|houston',
        method              => join('|', map("\Q$_\E", $self->method_list)),

        list                => '(?>(?>\x22((?:(?>\\.)++|[^\x22\\]++)*?)\x22|\x27((?:(?>\\.)++|[^\x27\\]++)*?)\x27|[^,]++),)*+(?>\x22((?:(?>\\.)++|[^\x22\\]++)*?)\x22|\x27((?:(?>\\.)++|[^\x27\\]++)*?)\x27|[^,]++)',
    };

    my $a={%{$self->{'data_types'}}};
    while (my ($type, $regex)=each %{$a}) {
        next if $type eq 'list';
        $self->{'data_types'}->{$type . '_list'} = "(?>(?:$regex),)*+(?:$regex)";
    }

    $self->{'data_types'}->{'data_type'}=join('|', map("\Q$_\E", keys %{$self->{'data_types'}}, 'data_type'));

    return $self->{'data_types'};
}

sub display {
    my $self=shift;
    my $display=shift;
    my $data=$display->{'data'};
    my $format=$display->{'format'};
    my $method=$display->{'method'};

    if (defined $format) {
        if ($format =~ /^(?>table|csv)$/) {
            die "$method cannot return as $format.\n"
                unless $self->validate_table($data);

            my $backend;
            $backend='Text::Table::Tiny' if $format eq 'table';
            $backend='Text::Table::CSV' if $format eq 'csv';

            print Text::Table::Any::table(
                rows        => $data,
                header_row  => 1,
                backend     => $backend,
            );
        } elsif ($format eq 'json') {
            die "$method cannot return as $format.\n"
                unless ref($data) =~ /^(?>ARRAY|HASH)$/;

            my $json=encode_json($data);
            print "$json\n";
        } elsif ($format eq 'data_dump') {
            die "$method cannot return as $format.\n"
                unless ref($data) =~ /^(?>ARRAY|HASH)$/;

            print Dumper $data;
        } elsif ($format eq 'string') {
            $data =~ s/(?<!\n)\z/\n/;
            die "$method cannot return as $format.\n"
                unless ref($data) eq '';
            print "$data";
        }
    }
}

sub help {
    my $self=shift;
    my $method=shift;

    if (defined $method) {
        return $self->{'help'}->{'methods'}->{$method}
            if defined $self->{'help'}->{'methods'}->{$method};
    } else {
        return $self->{'help'}
            if defined $self->{'help'};
    }

    my $frontpage=<<'EOF';

NAME
    apachecli v1.0

SYNOPSIS
    apachecli [METHOD [ARGUMENT VALUE]...]

DESCRIPTION
    This tool provides a user-friendly interface for analyzing Apache configurations. See a method you like? Use 'apachecli help method METHOD' to learn more about it.

METHODS
EOF

    my $meta=$self->meta();
    for my $method (sort { lc($a) cmp lc($b) } keys %{$meta}) {
        $frontpage.=<<"EOF";
    $method
        $meta->{$method}->{'description'}
EOF
    }

    $frontpage.="\n";
    $self->{'help'}->{'frontpage'}=$frontpage;

    for my $method (sort { lc($a) cmp lc($b) } keys %{$meta}) {
        my $page=<<"EOF";

NAME
    $method

SYNOPSIS
    $meta->{$method}->{'synopsis'}

DESCRIPTION
    $meta->{$method}->{'description'}

ARGUMENTS
EOF

        my $lengths;
        for my $arg (keys %{$meta->{$method}->{'args'}}) {
            $lengths->{$arg}->{'parameter'}=0;
            $lengths->{$arg}->{'value'}=0;

            while (my ($parameter, $value)=each %{$meta->{$method}->{'args'}->{$arg}}) {
                $lengths->{$arg}->{'parameter'}=length $parameter
                    if length $parameter > $lengths->{$arg}->{'parameter'};
                $lengths->{$arg}->{'value'}=length $value
                    if length $value > $lengths->{$arg}->{'value'};
            }
        }

        for my $arg (sort { lc($a) cmp lc($b) } keys %{$meta->{$method}->{'args'}}) {
            $page.=<<"EOF";
    $arg
EOF
            for my $parameter (sort { lc($a) cmp lc($b) } keys %{$meta->{$method}->{'args'}->{$arg}}) {
                my $format="%-$lengths->{$arg}->{'parameter'}s%4s%-$lengths->{$arg}->{'value'}s";
                my $line=sprintf $format, $parameter, ' => ', $meta->{$method}->{'args'}->{$arg}->{$parameter};
                $page.=<<"EOF";
        $line
EOF
            }
        }

    $page.="\n";

    $self->{'help'}->{'methods'}->{$method}=$page;
    }

    if (defined $method) {
        return $self->{'help'}->{'methods'}->{$method};
    } else {
        return $self->{'help'};
    }
}

sub meta {
    my $self=shift;
    my $method=shift;

    if (defined $method) {
        return $self->{'meta'}->{$method}
            if defined $self->{'meta'}->{$method};
    } else {
        return $self->{'meta'}
            if defined $self->{'meta'}
    }

    my @methods=$self->method_list;
    for my $method (@methods) {
        my $get_meta=ApacheConf::CLI::Methods->can('_' . $method);
        my $meta=$get_meta->();

        my $args=$meta->{'args'};

        my @args_sorted=map     { $_->[0] }
                        sort    { $b->[1] <=> $a->[1] || $a->[2] <=> $b->[2] || $a->[0] cmp $b->[0] }
                        map     { [$_, $args->{$_}->{'required'}, $args->{$_}->{'type'} =~ /_list$/ ? 1 : 0] }
                        keys    %{$args};

        my @tuples;
        for my $arg (@args_sorted) {
            my $required=$args->{$arg}->{'required'};
            my $list=$args->{$arg}->{'type'} =~ /_list$/ ? 1 : 0;
            my $type=$args->{$arg}->{'type'};
            $type=~s/_list$//;
            $type=uc($type);

            my $value;
            if ($list) {
                $value=$type . '[,' . $type . ']...';
            } else {
                $value=$type;
            }

            my $tuple;
            if ($required) {
                $tuple="$arg $value";
            } else {
                $tuple="[$arg $value]";
            }

            push @tuples, $tuple;
        }

        my $synopsis="apachecli $method ";
        $synopsis.=join ' ', @tuples;

        $meta->{'synopsis'}=$synopsis;

        $self->{'meta'}->{$method}=$meta;
    }

    if (defined $method) {
        return $self->{'meta'}->{$method};
    } else {
        return $self->{'meta'};
    }
}

sub method_list {
    my $self=shift;

    return @{$self->{'methods'}}
        if defined $self->{'methods'};

    $self->{'methods'}=Class::Inspector->methods('ApacheConf::CLI::Methods', 'public');

    return @{$self->{'methods'}};
}

sub read_command {
    my $self=shift;

    return $self->{'command'}
        if defined $self->{'command'};

    print $self->help->{'frontpage'} and exit
        unless my $method=shift @ARGV;
    die "Odd number of arguments passed on the command line.\n"
        if (scalar(@ARGV) % 2 );
    die "Invalid method: '$method'.\n"
        if $method =~ /^_/;
    die "Invalid method: '$method'.\n"
        unless ApacheConf::CLI::Methods->can($method);

    my $args={ @ARGV };
    my $meta=$self->meta($method);

    for my $arg (keys %{$meta->{'args'}}) {
        my $default=$meta->{'args'}->{$arg}->{'default'};
        $args->{$arg}=$default if defined $default and not defined $args->{$arg};
    }

    my $command={
        method  => $method,
        args    => $args,
    };

    $self->{'command'}=$command;

    return $self->{'command'};
}

sub report {
    my $self=shift;
    my $args={@_};
    my @columns=@{$args->{'columns'}};
    my @rows=@{$args->{'rows'}};

    my $length;
    $length->{$_}=length $_ for @columns;
    for my $row (@rows) {
        for my $column (@columns) {
            my $old_length=$length->{$column};
            my $new_length=length $row->{$column};
            $length->{$column}=$new_length if $new_length > $old_length;
        }
    }
    $length->{$_} += 3 for @columns;

    my $print_format;
    my @print_values;
    push (@print_values, $length->{$_}) for @columns;
    $print_format.="%-10s%-";
    $print_format.=join 's%-', @print_values;
    $print_format.="s%s";

    my $return=sprintf $print_format, '', @columns, "\n";
    for my $row (@rows) {
        my @column_data=map $row->{$_}, @columns;
        $return.=sprintf $print_format, '', @column_data, "\n";
    }

    return $return;
}

sub run {
    my $self=shift;
    my $command=shift;
    $self->validate_args($command);
    my $method=$command->{'method'};
    my $args=$command->{'args'};
    my $format=$args->{'format'};

    return $self->{'run'}->{$method}
        if defined $self->{'run'}->{$method};

    my $run=ApacheConf::CLI::Methods->can($method);

    $self->{'run'}->{$method}=$run->($self, $args);

    return $self->{'run'}->{$method};
}

sub validate_args {
    my $self=shift;
    my $command=shift;
    my $method=$command->{'method'};
    my $args=$command->{'args'};
    my $data_types=$self->data_types;
    my $meta=$self->meta($method);

    for my $arg (keys %{$meta->{'args'}}) {
        my $required=$meta->{'args'}->{$arg}->{'required'};
        my $type=$meta->{'args'}->{$arg}->{'type'};

        if ($required) {
            die "Missing required argument to method '$method'. '$arg' is required.\n"
                unless $args->{$arg};
        }

        if ($args->{$arg}) {
            my $value=$args->{$arg};
            if ($type) {
                my $regex=$data_types->{$type};
                die "Invalid value supplied to argument '$arg'. We expected '$type' type value.\n"
                    unless $value =~ /^(?:$regex)$/;
            }
        }
    }
}

sub validate_table {
    my $self=shift;
    my $data=shift;

    my $table=1;

    my $num_columns;
    if (ref $data eq 'ARRAY') {
        for my $row (@{$data}) {
            ref $row eq 'ARRAY' ? $num_columns->{scalar @{$row}}=1 : $table=0;
        }
    } else {
        $table=0;
    }

    $table=0
        unless scalar keys %{$num_columns} == 1;

    return $table;
}

1;
