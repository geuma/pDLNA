package PDLNA::ContentItem;
#
# pDLNA - a perl DLNA media server
# Copyright (C) 2010-2012 Stefan Heumader <stefan@heumader.at>
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

use Audio::FLAC::Header;
use Audio::Wav;
use Audio::WMA;
use Date::Format;
use File::Basename;
use File::MimeInfo;
use Image::Info qw(image_info dim image_type);
use Movie::Info;
use MP3::Info;
use MP4::Info;
use Ogg::Vorbis::Header;

use PDLNA::Config;
use PDLNA::Utils;

sub new
{
	my $class = shift;
	my $params = shift;

	my $self = ();
	$self->{ID} = $$params{'parent_id'}.$$params{'id'};
	$self->{PATH} = $$params{'filename'};
	$self->{NAME} = $$params{'name'} || basename($$params{'filename'});
	$self->{FILE_EXTENSION} = uc($1) if ($$params{'filename'} =~ /\.(\w{3,4})$/);
	$self->{PARENT_ID} = $$params{'parent_id'};
	$self->{DATE} = $$params{'date'};
	$self->{SIZE} = 0 || $$params{'size'};
	$self->{TYPE} = $$params{'type'};
	$self->{MIME_TYPE} = $$params{'mimetype'} || 'unknown';
	$self->{STREAM} = 0 || $$params{'stream'};
	$self->{SUBTITLE} = {};

	$self->{WIDTH} = 0;
	$self->{HEIGHT} = 0;
	$self->{COLOR} = '';
	$self->{DURATION_SECONDS} = 0; # duration in seconds
	$self->{BITRATE} = 0,
	$self->{VBR} = 0,

	$self->{ARTIST} = 'n/A';
	$self->{ALBUM} = 'n/A';
	$self->{TRACKNUM} = 'n/A';
	$self->{TITLE} = 'n/A';
	$self->{GENRE} = 'n/A';
	$self->{YEAR} = 'n/A';

	$self->{AUDIO_CODEC} = '';
	$self->{VIDEO_CODEC} = '';

	if ($self->{TYPE} eq 'image')
	{
		my $info = image_info($self->{PATH});
		($self->{WIDTH}, $self->{HEIGHT}) = dim($info);
	}
	elsif ($self->{TYPE} eq 'audio')
	{
		if ($self->{MIME_TYPE} eq 'audio/mpeg')
		{
			my $info = get_mp3info($self->{PATH});
			$self->{DURATION_SECONDS} = convert_to_seconds($info->{'TIME'});
			$self->{BITRATE} = int($info->{'BITRATE'});
			$self->{VBR} = $info->{'VBR'};

			my $tag = get_mp3tag($self->{PATH});
			if (keys %{$tag})
			{
				$self->{ARTIST} = $tag->{'ARTIST'} if length($tag->{'ARTIST'}) > 0;
				$self->{ALBUM} = $tag->{'ALBUM'} if length($tag->{'ALBUM'}) > 0;
				$self->{TRACKNUM} = $tag->{'TRACKNUM'} if length($tag->{'TRACKNUM'}) > 0;
				$self->{TITLE} = $tag->{'TITLE'} if length($tag->{'TITLE'}) > 0;
				$self->{GENRE} = $tag->{'GENRE'} if length($tag->{'GENRE'}) > 0;
				$self->{YEAR} = $tag->{'YEAR'} if length($tag->{'YEAR'}) > 0;
			}
		}
		if ($self->{MIME_TYPE} eq 'audio/mp4')
		{
			my $info = get_mp4info($self->{PATH});
			$self->{DURATION_SECONDS} = convert_to_seconds($info->{'TIME'});
			$self->{BITRATE} = int($info->{'BITRATE'});
			$self->{VBR} = 0;

			my $tag = get_mp4tag($self->{PATH});
			if (keys %{$tag})
			{
				$self->{ARTIST} = $tag->{'ARTIST'} if length($tag->{'ARTIST'}) > 0;
				$self->{ALBUM} = $tag->{'ALBUM'} if length($tag->{'ALBUM'}) > 0;
				$self->{TRACKNUM} = $tag->{'TRACKNUM'} if length($tag->{'TRACKNUM'}) > 0;
				$self->{TITLE} = $tag->{'TITLE'} if length($tag->{'TITLE'}) > 0;
				$self->{GENRE} = $tag->{'GENRE'} if length($tag->{'GENRE'}) > 0;
				$self->{YEAR} = $tag->{'YEAR'} if length($tag->{'YEAR'}) > 0;
			}
		}
		elsif ($self->{MIME_TYPE} eq 'audio/x-ms-wma')
		{
			my $wma = Audio::WMA->new($self->{PATH});

			my $info = $wma->info();
			$self->{DURATION_SECONDS} = $1 if $info->{'playtime_seconds'} =~ /^(\d+)/;
			$self->{BITRATE} = int($info->{'bitrate'});

			my $tag = $wma->tags();
			if (keys %{$tag})
			{
				$self->{ARTIST} = $tag->{'AUTHOR'} if length($tag->{'AUTHOR'}) > 0;
				$self->{ALBUM} = $tag->{'ALBUMTITLE'} if length($tag->{'ALBUMTITLE'}) > 0;
				$self->{TRACKNUM} = $tag->{'TRACKNUMBER'} if length($tag->{'TRACKNUMBER'}) > 0;
				$self->{TITLE} = $tag->{'TITLE'} if length($tag->{'TITLE'}) > 0;
				$self->{GENRE} = $tag->{'GENRE'} if length($tag->{'GENRE'}) > 0;
				$self->{YEAR} = $tag->{'YEAR'} if length($tag->{'YEAR'}) > 0;

				$self->{VBR} = $tag->{'VBR'};
			}
		}
		elsif ($self->{MIME_TYPE} eq 'audio/x-flac')
		{
			my $flac = Audio::FLAC::Header->new($self->{PATH});

			$self->{DURATION_SECONDS} = $1 if $flac->{'trackTotalLengthSeconds'} =~ /^(\d+)/;
			$self->{BITRATE} = int($flac->{'bitRate'});
			$self->{VBR} = 0;

			my $tag = $flac->tags();
			if (keys %{$tag})
			{
				$self->{ARTIST} = $tag->{'ARTIST'} if defined($tag->{'ARTIST'});
				$self->{ALBUM} = $tag->{'ALBUM'} if defined($tag->{'ALBUM'});
				$self->{TRACKNUM} = $tag->{'TRACKNUMBER'} if defined($tag->{'TRACKNUMBER'});
				$self->{TITLE} = $tag->{'TITLE'} if defined($tag->{'TITLE'});
				$self->{GENRE} = $tag->{'GENRE'} if defined($tag->{'GENRE'});
				$self->{YEAR} = $tag->{'DATE'} if defined($tag->{'DATE'});
			}
		}
		elsif ($self->{MIME_TYPE} eq 'video/x-theora+ogg')
		{
			my $ogg = Ogg::Vorbis::Header->new($self->{PATH});

			my $info = $ogg->info();
			$self->{DURATION_SECONDS} = $1 if $info->{'length'} =~ /^(\d+)/;
			$self->{BITRATE} = int($info->{'bitrate_nominal'});
			$self->{VBR} = 0;

			$self->{ARTIST} = $ogg->comment('ARTIST') if $ogg->comment('ARTIST');
			$self->{ALBUM} = $ogg->comment('ALBUM') if $ogg->comment('ALBUM');
			$self->{TRACKNUM} = $ogg->comment('TRACKNUMBER') if $ogg->comment('TRACKNUMBER');
			$self->{TITLE} = $ogg->comment('TITLE') if $ogg->comment('TITLE');
			$self->{GENRE} = $ogg->comment('GENRE') if $ogg->comment('GENRE');
			$self->{YEAR} = $ogg->comment('YEAR') if $ogg->comment('YEAR');
		}
		elsif ($self->{MIME_TYPE} eq 'audio/x-wav')
		{
			my $wav = new Audio::Wav;
			my $read = $wav->read($self->{PATH});

			$self->{DURATION_SECONDS} = $1 if $read->length_seconds() =~ /^(\d+)/;
			$self->{BITRATE} = 0;
			$self->{VBR} = 0;
		}

		my $movie_info = Movie::Info->new();
		unless (defined($movie_info))
		{
			PDLNA::Log::fatal('Unable to find MPlayer.');
		}

		my %info = $movie_info->info($self->{PATH});
		$self->{AUDIO_CODEC} = $info{'audio_codec'};
	}
	elsif ($self->{TYPE} eq 'video')
	{
		my $movie_info = Movie::Info->new();
		unless (defined($movie_info))
		{
			PDLNA::Log::fatal('Unable to find MPlayer.');
		}

		my %info = $movie_info->info($self->{PATH});

		$self->{DURATION_SECONDS} = $1 if $info{'length'} =~ /^(\d+)/; # ignore milliseconds
		$self->{BITRATE} = $info{'bitrate'} || 0;
		$self->{WIDTH} = $info{'width'} || 0;
		$self->{HEIGHT} = $info{'height'} || 0;

		$self->{AUDIO_CODEC} = $info{'audio_codec'};
		$self->{VIDEO_CODEC} = $info{'codec'};

		my $tmp = $1 if $self->{PATH} =~ /^(.+)\.\w{3,4}$/;
		foreach my $extensions ('srt')
		{
			if (-f $tmp.'.'.$extensions)
			{
				my $mimetype = mimetype($tmp.'.'.$extensions);
				my @fileinfo = stat($tmp.'.'.$extensions);
				if ($mimetype eq 'application/x-subrip') # TODO text/x-subviewer (.sub)
				{
					$self->{SUBTITLE}->{$extensions} = {
						'path' => $tmp.'.'.$extensions,
						'mimetype' => $mimetype,
						'size' => $fileinfo[7],
						'date' => $fileinfo[9]
					};
				}
				else
				{
					PDLNA::Log::log('Unknown MimeType '.$mimetype.' for subtitle file '.$tmp.'.'.$extensions.'.', 3, 'library');
				}
			}
		}
	}

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
	return $self->{PARENT_ID};
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
	my $device = shift || '';

	# Samsung does not accept normal MIME TYPE 'video/x-matroska',
	# instead it wants 'video/x-mkv' as MIME TYPE
	if ($device eq 'Samsung DTV DMR')
	{
		return 'video/x-mkv' if $self->{MIME_TYPE} eq 'video/x-matroska';
		return 'video/x-avi' if $self->{MIME_TYPE} eq 'video/x-msvideo';
	}
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

	my $seconds = $self->{DURATION_SECONDS};
	my $minutes = 0;
	$minutes = int($seconds / 60) if $seconds > 59;
	$seconds -= $minutes * 60 if $seconds;
	my $hours = 0;
	$hours = int($minutes / 60) if $minutes > 59;
	$minutes -= $hours * 60 if $hours;

	my $string = '';
	$string .= PDLNA::Utils::add_leading_char($hours,2,'0').':';
	$string .= PDLNA::Utils::add_leading_char($minutes,2,'0').':';
	$string .= PDLNA::Utils::add_leading_char($seconds,2,'0');

	return $string;
}

sub duration_seconds
{
	my $self = shift;
	return $self->{DURATION_SECONDS} if $self->{DURATION_SECONDS};
}

# TODO make it more beautiful
sub convert_to_seconds
{
	my $duration = shift;

	my $seconds = 0;
    my @foo;
	@foo = split(':', $duration) if $duration;

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

sub subtitle
{
	my $self = shift;
	my $type = shift || undef;

	if (defined($type))
	{
		return %{$self->{SUBTITLE}->{$type}} if exists($self->{SUBTITLE}->{$type});
	}
	return %{$self->{SUBTITLE}};
}

sub print_object
{
	my $self = shift;
	my $input = shift;

    my $string = '';
	$string .= $input."Object PDLNA::ContentItem\n";
	$string .= $input."\tID:            ".$self->{ID}."\n";
	$string .= $input."\tParentID:      ".$self->{PARENT_ID}."\n";
	$string .= $input."\tFilename:      ".$self->{NAME}."\n";
	$string .= $input."\tPath:          ".$self->{PATH}."\n";
	$string .= $input."\tFileExtension: ".$self->{FILE_EXTENSION}."\n";
	$string .= $input."\tType:          ".$self->{TYPE}."\n";
	$string .= $input."\tDate:          ".$self->{DATE}." (".time2str($CONFIG{'DATE_FORMAT'}, $self->{DATE}).")\n";
	$string .= $input."\tSize:          ".$self->{SIZE}." Bytes (".PDLNA::Utils::convert_bytes($self->{SIZE}).")\n";
	$string .= $input."\tMimeType:      ".$self->{MIME_TYPE}."\n";

	if ($self->{TYPE} eq 'image')
	{
		$string .= $input."\tResolution:    ".$self->{WIDTH}."x".$self->{HEIGHT}." px\n";
	}
	if ($self->{TYPE} eq 'audio')
	{
		$string .= $input."\tDuration:      ".$self->duration()." (".$self->duration_seconds()." seconds)\n";
		$string .= $input."\tBitrate:       ".$self->{BITRATE}." (k)bit/s (VBR ".$self->{VBR}.")\n";
		$string .= $input."\tArtist:        ".$self->{ARTIST}."\n";
		$string .= $input."\tAlbum:         ".$self->{ALBUM}."\n";
		$string .= $input."\tTrackNumber:   ".$self->{TRACKNUM}."\n";
		$string .= $input."\tTitle:         ".$self->{TITLE}."\n";
		$string .= $input."\tGenre:         ".$self->{GENRE}."\n";
		$string .= $input."\tYear:          ".$self->{YEAR}."\n";
	}
	elsif ($self->{TYPE} eq 'video')
	{
		$string .= $input."\tDuration:      ".$self->duration()." (".$self->duration_seconds()." seconds)\n";
		$string .= $input."\tBitrate:       ".$self->{BITRATE}." bit/s\n";
		$string .= $input."\tResolution:    ".$self->{WIDTH}."x".$self->{HEIGHT}." px\n";
		foreach my $type (keys %{$self->{SUBTITLE}})
		{
			$string .= $input."\tSubTitleFile   ".$self->{SUBTITLE}->{$type}->{'path'}." (".$type.")\n";
		}
	}

	if ($self->{TYPE} eq 'audio' || $self->{TYPE} eq 'video')
	{
		$string .= $input."\tAudioCodec:    ".$self->{AUDIO_CODEC}."\n" if defined($self->{AUDIO_CODEC});
	}
	if ($self->{TYPE} eq 'video')
	{
		$string .= $input."\tVideoCodec:    ".$self->{VIDEO_CODEC}."\n" if defined($self->{VIDEO_CODEC});
	}
	$string .= $input."Object PDLNA::ContentItem END\n";

	return $string;
}

1;
