package App::Wallflower;

use strict;
use warnings;

use Getopt::Long qw( GetOptionsFromArray );
use Pod::Usage;
use Plack::Util ();
use Wallflower;
use Wallflower::Util qw( links_from );

sub new_with_options {
    my ( $class, $args ) = @_;
    my $input = (caller)[1];

    # save previous configuration
    my $save = Getopt::Long::Configure();

    # ensure we use Getopt::Long's default configuration
    Getopt::Long::ConfigDefaults();

    # get the command-line options (modifies $args)
    my %option = ( follow => 1, environment => 'deployment' );
    GetOptionsFromArray(
        $args,           \%option,
        'application=s', 'destination|directory=s',
        'index=s',       'environment=s',
        'follow!',       'filter|files|F',
        'quiet',         'include|INC=s@',
        'help',          'manual',
    ) or pod2usage(
        -input   => $input,
        -verbose => 1,
        -exitval => 2,
    );

    # restore Getopt::Long configuration
    Getopt::Long::Configure($save);

    # simple on-line help
    pod2usage( -verbose => 1 ) if $option{help};
    pod2usage( -verbose => 2 ) if $option{manual};

    # application is required
    pod2usage(
        -input   => $input,
        -verbose => 1,
        -exitval => 2,
        -message => 'Missing required option: application'
    ) if !exists $option{application};

    # include option
    my $path_sep = $Config::Config{path_sep} || ';';
    $option{inc} = [ split /\Q$path_sep\E/, join $path_sep,
        @{ $option{include} || [] } ];

    local $ENV{PLACK_ENV} = $option{environment};
    local @INC = ( @INC, @{ $option{inc} } );
    return bless {
        option     => \%option,
        args       => $args,
        seen       => {},
        wallflower => Wallflower->new(
            application => Plack::Util::load_psgi( $option{application} ),
            ( destination => $option{destination} )x!! $option{destination},
            ( index       => $option{index}       )x!! $option{index},
        ),
    }, $class;

}

sub run {
    my ($self) = @_;
    ( my $args, $self->{args} ) = ( $self->{args}, [] );
    my $method = $self->{option}{filter} ? '_process_args' : '_process_queue';
    $self->$method(@$args);
}

sub _process_args {
    my $self = shift;
    local @ARGV = @_;
    while (<>) {

        # ignore blank lines and comments
        next if /^\s*(#|$)/;
        chomp;

        $self->_process_queue("$_");
    }
}

sub _process_queue {
    my ( $self, @queue ) = @_;
    my ( $quiet, $follow, $seen )
        = @{ $self->{option} }{qw( quiet follow seen )};
    my $wallflower = $self->{wallflower};

    # I'm just hanging on to my friend's purse
    local $ENV{PLACK_ENV} = $self->{option}{environment};
    local @INC = ( @INC, @{ $self->{option}{inc} } );
    @queue = ('/') if !@queue;
    while (@queue) {

        my $url = URI->new( shift @queue );
        next if $seen->{ $url->path }++;

        # get the response
        my $response = $wallflower->get($url);
        my ( $status, $headers, $file ) = @$response;

        # tell the world
        printf "$status %s%s\n", $url->path, $file && " => $file [${\-s $file}]"
            if !$quiet;

        # obtain links to resources
        if ( $status eq '200' && $follow ) {
            push @queue, links_from( $response => $url );
        }

        # follow 301 Moved Permanently
        elsif ( $status eq '301' ) {
            require HTTP::Headers;
            my $l = HTTP::Headers->new(@$headers)->header('Location');
            unshift @queue, $l if $l;
        }
    }
}

1;

__END__

=head1 NAME

App::Wallflower - Class performing the moves for the wallflower program

=head1 SYNOPSIS

    # this is the actual code for wallflower
    use App::Wallflower;
    App::Wallflower->new_with_options( \@ARGV )->run;

=head1 DESCRIPTION

L<App::Wallflower> is a container for functions for the L<wallflower>
program.

=head1 METHODS

=head2 new_with_options( \@argv )

Process options in the provided array reference (modifying it),
and return a object ready to be C<run()>.

=head2 run( )

Filter the URL in the files remaining from processing the options
in C<@argv>, or from standard input if it's empty.

=head1 AUTHOR

Philippe Bruhat (BooK)

=head1 COPYRIGHT

Copyright 2010-2012 Philippe Bruhat (BooK), all rights reserved.

=head1 LICENSE

This program is free software and is published under the same
terms as Perl itself.

=cut
