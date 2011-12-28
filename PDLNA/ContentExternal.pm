package PDLNA::ContentExternal;
#
# pDLNA - a perl DLNA media server
# Copyright (C) 2010-2011 Stefan Heumader <stefan@heumader.at>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

# Only video streams supported!

use strict;
use warnings;

use File::Basename;
use Date::Format;
use Data::Dumper;

use PDLNA::Utils;

sub new
{
	my $class = shift;
	my $params = shift;

	my $self = ();
	$self->{ID} = $$params{'parent_id'}.$$params{'id'};
	$self->{PATH} = $$params{'path'};
	$self->{NAME} = basename($$params{'path'});
	$self->{FILE_EXTENSION} = 'AVI';
	$self->{PARENT_ID} = $$params{'parent_id'};
	$self->{DATE} = time();
	$self->{SIZE} = 0;
	$self->{TYPE} = $$params{'type'};

	$self->{MIME_TYPE} = 'video/x-msvideo';

	$self->{WIDTH} = '';
	$self->{HEIGHT} = '';
	$self->{COLOR} = '';
	$self->{DURATION} = ''; # beautiful duration, like i.e. 02:31
	$self->{DURATION_SECONDS} = 0; # duration in seconds
	$self->{BITRATE} = 0,
	$self->{VBR} = 0,

	bless($self, $class);
	return $self;
}

sub is_directory
{
	return 0;
}

sub is_item
{
	return 1;
}

sub id
{
	my $self = shift;
	my $id = shift;

	$self->{ID} = $id if defined($id);
	return $self->{ID};
}

sub beautiful_id
{
	my $self = shift;
	return PDLNA::Utils::add_leading_char($self->{ID},3,'0');
}

sub name
{
	my $self = shift;
	return $self->{NAME};
}

sub date
{
	my $self = shift;
	return $self->{DATE};
}

sub parent_id
{
	my $self = shift;
	return $self->{DATE};
}

sub size
{
	my $self = shift;
	return $self->{SIZE};
}

sub path
{
	my $self = shift;
	return $self->{PATH};
}

sub file_extension
{
	my $self = shift;
	return $self->{FILE_EXTENSION};
}

sub type
{
	my $self = shift;
	return $self->{TYPE};
}

sub mime_type
{
	my $self = shift;
	return $self->{MIME_TYPE};
}

sub resolution
{
	my $self = shift;
	return $self->{WIDTH}.'x'.$self->{HEIGHT};
}

# TODO make it more beautiful
sub duration
{
	my $self = shift;
	return $self->{DURATION} if $self->{DURATION};

	my $seconds = $self->{DURATION_SECONDS};
	my $minutes = int($seconds / 60) if $seconds > 59;
	$seconds -= $minutes * 60;
	my $hours = int($minutes / 60) if $minutes > 59;
	$minutes -= $hours * 60;

	my $string = '';
	$string .= PDLNA::Utils::add_leading_char($hours,2,'0').':' if $hours;
	$string .= PDLNA::Utils::add_leading_char($minutes,2,'0').':';
	$string .= PDLNA::Utils::add_leading_char($seconds,2,'0');

	return $string;
}

# TODO make it more beautiful
sub duration_seconds
{
	my $self = shift;

	my $seconds = 0;
    my @foo;
	@foo = split(':', $self->{DURATION}) if $self->{'DURATION'};

	my $i = 0;
	foreach my $bar (reverse @foo)
	{
		$seconds += $bar if $i == 0;
		$seconds += $bar*60 if $i == 1;
		$seconds += $bar*3600 if $i == 2;
		$i++;
	}

	return $seconds;
}

sub artist
{
	my $self = shift;
	return $self->{ARTIST};
}

sub album
{
	my $self = shift;
	return $self->{ALBUM};
}

sub genre
{
	my $self = shift;
	return $self->{GENRE};
}

sub year
{
	my $self = shift;
	return $self->{YEAR};
}

sub bitrate
{
	my $self = shift;
	return $self->{BITRATE};
}

sub tracknum
{
	my $self = shift;
	return $self->{TRACKNUM};
}

sub print_object
{
	my $self = shift;
	my $input = shift;

    my $string = '';
	$string .= $input."Object PDLNA::ContentExternal\n";
	$string .= $input."\tID:            ".$self->{ID}."\n";
	$string .= $input."\tParentID:      ".$self->{PARENT_ID}."\n";
	$string .= $input."\tFilename:      ".$self->{NAME}."\n";
	$string .= $input."\tPath:          ".$self->{PATH}."\n";
	$string .= $input."\tFileExtension: ".$self->{FILE_EXTENSION}."\n";
	$string .= $input."\tType:          ".$self->{TYPE}."\n";
	$string .= $input."\tMimeType:      ".$self->{MIME_TYPE}."\n";

	$string .= $input."Object PDLNA::ContentItem END\n";

	return $string;
}

1;
