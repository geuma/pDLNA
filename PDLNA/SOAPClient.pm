package PDLNA::SOAPClient;

=head1 NAME

package PDLNA::SOAPClient - for processing soap messages.

=head1 DESCRIPTION

This module gets and sends a soap message.

=cut


use strict;
use warnings;

=head1 LIBRARY FUNCTIONS

=over 12

=item internal libraries

=begin html

</p>
<a href="./Log.html">PDLNA::Log</a>.
</p>

=end html

=item external libraries

L<SOAP::Lite>,
L<XML::Simple>.

=back

=cut

use SOAP::Lite;
use XML::Simple;

use PDLNA::Log;


=head1 METHODS

=over

=item new() - constructor.

=cut

sub new
{
	my $class = shift;
	my $params = shift;

	my $self = {
		PROXY => $$params{'proxy'},
		URI => $$params{'uri'},
		METHOD => undef,
		ARGUMENTS => [],
	};

	bless($self, $class);
	return $self;
}

=item method()

=cut

sub method
{
	my $self = shift;
	my $method = shift;

	$self->{METHOD} = $method;
}

=item add_argument()

=cut

sub add_argument
{
	my $self = shift;
	my $params = shift;

	push(@{$self->{ARGUMENTS}}, SOAP::Data->type($$params{'type'})->name($$params{'name'})->value($$params{'value'}));
}

=item send()

=cut

sub send
{
	my $self = shift;
	my $params = shift;

	my $request = SOAP::Lite->new(
		proxy => $self->{PROXY},
		uri => $self->{URI},
	);

	PDLNA::Log::log('Doing request to '.$self->{PROXY}.' with method '.$self->{METHOD}.'.', 1, 'soap');

	my $response = undef;
	eval { $response = $request->call($self->{METHOD} => $self->{ARGUMENTS}) };
	if ($@)
	{
		PDLNA::Log::log('ERROR: Unable to perform SOAP request: '.$@, 0, 'soap');
	}
	else
	{
		PDLNA::Log::log('HTTP status code: '.$response->{'_context'}->{'_transport'}->{'_proxy'}->{'_status'}, 2, 'soap');
		if ($response->{'_context'}->{'_transport'}->{'_proxy'}->{'_is_success'})
		{
			PDLNA::Log::log('HTTP response: '.$response->{'_context'}->{'_transport'}->{'_proxy'}->{'_http_response'}->{'_content'}, 3, 'soap');
			if ($$params{'return_value'})
			{
				my $xmlsimple = XML::Simple->new();
				my $xml = undef;
				eval { $xml = $xmlsimple->XMLin($response->{'_context'}->{'_transport'}->{'_proxy'}->{'_http_response'}->{'_content'}) };
				if ($@)
				{
					PDLNA::Log::log('ERROR: Unable to convert response with XML::Simple: '.$@, 0, 'soap');
				}
				else
				{
					PDLNA::Log::log('Finished converting response with XML::Simple.', 3, 'soap');
					PDLNA::Log::log('Return value in response: '.$xml->{'s:Body'}->{'u:'.$self->{METHOD}.'Response'}->{$$params{'return_value'}}, 3, 'soap');
					return $xml->{'s:Body'}->{'u:'.$self->{METHOD}.'Response'}->{$$params{'return_value'}};
				}
			}
			else
			{
				return 1;
			}
		}
		else
		{
			PDLNA::Log::log('ERROR: Unable to understand response (unknwon _is_success value): '.$response->{'_context'}->{'_transport'}->{'_proxy'}->{'_is_success'}, 0, 'soap');
		}
	}
	return 0;
}


=back

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010-2013 Stefan Heumader L<E<lt>stefan@heumader.atE<gt>>.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.
This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
You should have received a copy of the GNU General Public License
along with this program.  If not, see L<http://www.gnu.org/licenses/>.

=cut


1;
