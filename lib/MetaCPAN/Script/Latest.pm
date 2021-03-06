package MetaCPAN::Script::Latest;

use feature qw(say);
use Moose;
use MooseX::Aliases;
with 'MooseX::Getopt';
use Log::Contextual qw( :log );
with 'MetaCPAN::Role::Common';

has dry_run => ( is => 'ro', isa => 'Bool', default => 0 );
has distribution => ( is => 'ro', isa => 'Str' );

sub run {
    my $self = shift;
    my $es   = $self->es;
    log_info { "Dry run: updates will not be written to ES" }
    if ( $self->dry_run );
    $es->refresh_index();
    my $query =
      $self->distribution
      ? { term => { distribution => $self->distribution } }
      : { match_all => {} };
    my $scroll = $es->scrolled_search({ index => $self->index->name,
                   type   => 'release',
                   query  => $query,
                   scroll => '1h',
                   size => 1000,
                   sort   => ['distribution',
                             { maturity => { reverse => \1 } },
                             { date     => { reverse => \1 } }
                   ], });

    my $dist = '';
    while ( my $row = $scroll->next(1) ) {
        my $source = $row->{_source};
        if ( $dist ne $source->{distribution} ) {
            $dist = $source->{distribution};
            next if ( $source->{status} eq 'latest' );
            log_info { "Upgrading $source->{name} to latest" };

            log_debug { "Upgrading files" };
            $self->reindex( $source, 'latest' );

            next if ( $self->dry_run );
            $es->index( index => $self->index->name,
                        type  => 'release',
                        id    => $row->{_id},
                        data  => { %$source, status => 'latest' } );
        } elsif ( $source->{status} eq 'latest' ) {
            log_info { "Downgrading $source->{name} to cpan" };

            log_debug { "Downgrading files" };
            $self->reindex( $source, 'cpan' );

            next if ( $self->dry_run );
            $es->index( index => $self->index->name,
                        type  => 'release',
                        id    => $row->{_id},
                        data  => { %$source , status => 'cpan' } );

        }
    }
}

sub reindex {
    my ( $self, $source, $status ) = @_;
    my $es = $self->es;
    my $scroll = $es->scrolled_search(
        {  index       => $self->index->name,
           type        => 'file',
           scroll      => '1h',
           size        => 1000,
           search_type => 'scan',
           query       => { match_all => {} },
           filter      => {
                       and => [
                           { term => { 'file.release' => $source->{name} } },
                           { term => { 'file.author'  => $source->{author} } } ]
           } } );

    while ( my $row = $scroll->next(1) ) {
        my $source = $row->{_source};
        log_debug {
            $status eq 'latest' ? "Upgrading " : "Downgrading ",
              "file ", $source->{name} || '';
        };
        $es->index( index => $self->index->name,
                    type  => 'file',
                    id    => $row->{_id},
                    data  => { %$source, status => $status }
        ) unless ( $self->dry_run );
    }

}

__PACKAGE__->meta->make_immutable;

__END__

=head1 SYNOPSIS

 # bin/metacpan latest

 # bin/metacpan latest --dry_run
 
=head1 DESCRIPTION

After importing releases from cpan, this script will set the status
to latest on the most recent release, its files and dependencies.
It also makes sure that there is only one latest release per distribution.
