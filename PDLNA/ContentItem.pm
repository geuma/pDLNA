package PDLNA::ContentItem;
#
# pDLNA - a perl DLNA media server
# Copyright (C) 2010 Stefan Heumader <stefan@heumader.at>
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

use strict;
use warnings;

use File::Basename;
use Date::Format;
use Image::Info qw(image_info dim image_type);
use MP3::Info;
use Data::Dumper;

use PDLNA::Utils;

sub new
{
	my $class = shift;
	my $params = shift;

	my $self = ();
	$self->{ID} = $$params{'id'};
	$self->{PATH} = $$params{'filename'};
	$self->{NAME} = basename($$params{'filename'});
	$self->{DATE} = $$params{'date'};
	$self->{SIZE} = $$params{'size'};
	$self->{TYPE} = $$params{'type'};

	$self->{WIDTH} = '';
	$self->{HEIGHT} = '';
	$self->{MEDIA_TYPE} = '';
	$self->{COLOR} = '';
	$self->{DURATION} = '';
	$self->{BITRATE} = '',
	$self->{VBR} = 0,

	$self->{ARTIST} = '';
	$self->{ALBUM} = '';
	$self->{TRACKNUM} = '';
	$self->{TITLE} = '';
	$self->{GENRE} = '';
	$self->{YEAR} = '';

	if ($self->{TYPE} eq 'image')
	{
		my $info = image_info($self->{PATH});
		($self->{WIDTH}, $self->{HEIGHT}) = dim($info);
		$self->{MEDIA_TYPE} = $info->{'file_media_type'};
	}
	elsif ($self->{TYPE} eq 'audio')
	{
		my $info = get_mp3info($self->{PATH});
		$self->{DURATION} = $info->{'TIME'};
		$self->{BITRATE} = $info->{'BITRATE'};
		$self->{VBR} = $info->{'VBR'};

		my $tag = get_mp3tag($self->{PATH});
		$self->{ARTIST} = $tag->{'ARTIST'};
		$self->{ALBUM} = $tag->{'ALBUM'};
		$self->{TRACKNUM} = $tag->{'TRACKNUM'};
		$self->{TITLE} = $tag->{'TITLE'};
		$self->{GENRE} = $tag->{'GENRE'};
		$self->{YEAR} = $tag->{'YEAR'};
	}
	elsif ($self->{TYPE} eq 'video')
	{
	}

	bless($self, $class);
	return $self;
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

sub print_object
{
	my $self = shift;

	print "\t\t\tObject PDLNA::ContentItem\n";
	print "\t\t\t\tID:            ".PDLNA::Utils::add_leading_char($self->{ID},3,'0')."\n";
	print "\t\t\t\tFilename:      ".$self->{NAME}."\n";
	print "\t\t\t\tPath:          ".$self->{PATH}."\n";
	print "\t\t\t\tType:          ".$self->{TYPE}."\n";
	print "\t\t\t\tDate:          ".$self->{DATE}." (".time2str("%Y-%m-%d %H:%M", $self->{DATE}).")\n";
	print "\t\t\t\tSize:          ".$self->{SIZE}." Bytes\n";
	print "\t\t\t\tResolution:    ".$self->{WIDTH}."x".$self->{HEIGHT}." px\n" if $self->{TYPE} eq 'image';
	print "\t\t\t\tMediaType:     ".$self->{MEDIA_TYPE}."\n" if $self->{TYPE} eq 'image';
	print "\t\t\t\tDuration:      ".$self->{DURATION}."\n" if $self->{TYPE} eq 'audio';
	print "\t\t\t\tBitrate:       ".$self->{BITRATE}." bit/s (VBR ".$self->{VBR}.")\n" if $self->{TYPE} eq 'audio';
	if ($self->{TYPE} eq 'audio')
	{
		print "\t\t\t\tArtist:        ".$self->{ARTIST}."\n";
		print "\t\t\t\tAlbum:         ".$self->{ALBUM}."\n";
		print "\t\t\t\tTrackNumber:   ".$self->{TRACKNUM}."\n";
		print "\t\t\t\tTitle:         ".$self->{TITLE}."\n";
		print "\t\t\t\tGenre:         ".$self->{GENRE}."\n";
		print "\t\t\t\tYear:          ".$self->{YEAR}."\n";
	}
}

1;
