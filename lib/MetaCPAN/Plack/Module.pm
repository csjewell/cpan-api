package MetaCPAN::Plack::Module;
use base 'MetaCPAN::Plack::Base';
use strict;
use warnings;

sub type { 'file' }

sub query {
    shift;
    return { query  => { match_all => {} },
             filter => {
                         and => [ { term => { documentation => shift } },
                                  { term => { status        => 'latest' } } ]
             },
             size => 1,
             sort => { date => { reverse => \1 } } };
}


sub handle {
    my ($self, $env) = @_;
    $self->get_first_result($env);
}


1;

__END__

=head1 METHODS

=head2 index

Returns C<module>.

=head2 query

Builds a query that looks for the name of the module,
sorts by date descending and fetches only to first 
result.

=head2 handle

Get the first result from the response and return it.

=head1 SEE ALSO

L<MetaCPAN::Plack::Base>