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
	$self->{PARENT_ID} = $$params{'parent_id'};

	$self->{FILE} = 0; # is it a file stored on a mounted filesystem
	$self->{DATE} = 0;
	$self->{SIZE} = 0;
	$self->{TYPE} = '';
	$self->{FILE_EXTENSION} = '';
	if (defined($$params{'filename'}))
	{
		$self->{FILE} = 1;
		$self->{PATH} = $$params{'filename'};
		$self->{NAME} = $$params{'name'} || basename($$params{'filename'});
		$self->{MIME_TYPE} = $$params{'mimetype'};
		$self->{TYPE} = $$params{'type'} || '';

		$self->{FILE_EXTENSION} = $1 if $self->{NAME} =~ /(\w{3,4})$/;
		#
		# FILESYSTEM META DATA
		#
		my @fileinfo = stat($self->{PATH});
		$self->{DATE} = $fileinfo[9];
		$self->{SIZE} = $fileinfo[7];
	}
	elsif (defined($$params{'command'}))
	{
		$self->{NAME} = $$params{'name'} || '';
		$self->{COMMAND} = $$params{'command'};
		$self->{PATH} = $$params{'command'};
	}
	elsif (defined($$params{'streamurl'}))
	{
		$self->{NAME} = $$params{'name'} || '';
		$self->{COMMAND} = $CONFIG{'MPLAYER_BIN'}.' '.$$params{'streamurl'}.' -dumpstream -dumpfile /dev/stdout 2>/dev/null';
		$self->{PATH} = $$params{'streamurl'};
	}

	#
	# resolution, encoding, ...
	#
	$self->{WIDTH} = 0;
	$self->{HEIGHT} = 0;

	$self->{DURATION_SECONDS} = 0; # duration in seconds
	$self->{BITRATE} = 0,
	$self->{VBR} = 0,

	$self->{CONTAINER} = '';
	$self->{AUDIO_CODEC} = '';
	$self->{VIDEO_CODEC} = '';

	if ($self->{TYPE} eq 'image')
	{
		my $info = image_info($self->{PATH});
		($self->{WIDTH}, $self->{HEIGHT}) = dim($info);
	}
	else
	{
		PDLNA::Media::info($self);
	}

	#
	# ADD AUDIO INFORMATION (artist, ...)
	#
	$self->{ARTIST} = 'n/A';
	$self->{ALBUM} = 'n/A';
	$self->{TRACKNUM} = 0;
	$self->{TITLE} = 'n/A';
	$self->{GENRE} = 'n/A';
	$self->{YEAR} = '0000';

	if ($self->{TYPE} eq 'audio' && defined($self->{AUDIO_CODEC}))
	{
		if ($self->{AUDIO_CODEC} eq 'mp3')
		{
			#my $info = get_mp3info($self->{PATH});
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
		elsif ($self->{AUDIO_CODEC} eq 'faad')
		{
			#my $info = get_mp4info($self->{PATH});
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
		elsif ($self->{AUDIO_CODEC} eq 'ffwmav2')
		{
			my $wma = Audio::WMA->new($self->{PATH});
			#my $info = $wma->info();
			my $tag = $wma->tags();
			if (keys %{$tag})
			{
				$self->{ARTIST} = $tag->{'AUTHOR'} if length($tag->{'AUTHOR'}) > 0;
				$self->{ALBUM} = $tag->{'ALBUMTITLE'} if length($tag->{'ALBUMTITLE'}) > 0;
				$self->{TRACKNUM} = $tag->{'TRACKNUMBER'} if length($tag->{'TRACKNUMBER'}) > 0;
				$self->{TITLE} = $tag->{'TITLE'} if length($tag->{'TITLE'}) > 0;
				$self->{GENRE} = $tag->{'GENRE'} if length($tag->{'GENRE'}) > 0;
				$self->{YEAR} = $tag->{'YEAR'} if length($tag->{'YEAR'}) > 0;
			}
		}
		elsif ($self->{AUDIO_CODEC} eq 'ffflac')
		{
			my $flac = Audio::FLAC::Header->new($self->{PATH});
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
		elsif ($self->{AUDIO_CODEC} eq 'ffvorbis')
		{
#			my $ogg = Ogg::Vorbis::Header->new($self->{PATH});
#			$self->{ARTIST} = $ogg->comment('ARTIST') if $ogg->comment('ARTIST');
#			$self->{ALBUM} = $ogg->comment('ALBUM') if $ogg->comment('ALBUM');
#			$self->{TRACKNUM} = $ogg->comment('TRACKNUMBER') if $ogg->comment('TRACKNUMBER');
#			$self->{TITLE} = $ogg->comment('TITLE') if $ogg->comment('TITLE');
#			$self->{GENRE} = $ogg->comment('GENRE') if $ogg->comment('GENRE');
#			$self->{YEAR} = $ogg->comment('YEAR') if $ogg->comment('YEAR');
		}
		elsif ($self->{AUDIO_CODEC} eq 'pcm')
		{
#			my $wav = Audio::Wav->new();
#			my $read = $wav->read($self->{PATH});
		}
		else
		{
		}
	}

	#
	# SUBTITLES
	# TODO support more subtitles (text/x-subviewer (.sub))
	#
	$self->{SUBTITLE} = {};

	if ($self->{TYPE} eq 'video')
	{
		my $tmp = $1 if $self->{PATH} =~ /^(.+)\.\w{3,4}$/;
		foreach my $extensions ('srt')
		{
			if (-f $tmp.'.'.$extensions)
			{
				my $mimetype = mimetype($tmp.'.'.$extensions);
				my @fileinfo = stat($tmp.'.'.$extensions);
				if ($mimetype eq 'application/x-subrip')
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

	#
	# TRANSCODING
	#
	$self->{CONTAINER_TRANSCODE} = undef;
	$self->{AUDIO_CODEC_TRANSCODE} = undef;
	$self->{VIDEO_CODEC_TRANSCODE} = undef;

	if ($self->{TYPE} =~ /^(audio|video)$/ && $self->{FILE})
	{
		foreach my $transcode_profile (@{$CONFIG{'TRANSCODING_PROFILES'}})
		{
			next if $self->{CONTAINER} ne $$transcode_profile{'ContainerIn'};

			if (defined($$transcode_profile{'AudioIn'}) && $self->{AUDIO_CODEC} ne $$transcode_profile{'AudioIn'})
			{
				next;
			}

			if (defined($$transcode_profile{'VideoIn'}) && $self->{VIDEO_CODEC} ne $$transcode_profile{'VideoIn'})
			{
				next;
			}

			$self->{FILE} = 0;
			$self->{CONTAINER_TRANSCODE} = $$transcode_profile{'ContainerOut'};
			$self->{AUDIO_CODEC_TRANSCODE} = $$transcode_profile{'AudioOut'} if defined($$transcode_profile{'AudioOut'});
			$self->{VIDEO_CODEC_TRANSCODE} = $$transcode_profile{'VideoOut'} if defined($$transcode_profile{'VideoOut'});
			$self->{MIME_TYPE} = PDLNA::Media::details($self->{CONTAINER_TRANSCODE}, $self->{VIDEO_CODEC_TRANSCODE}, $self->{AUDIO_CODEC_TRANSCODE}, 'MimeType');
			$self->{TYPE} = PDLNA::Media::details($self->{CONTAINER_TRANSCODE}, $self->{VIDEO_CODEC_TRANSCODE}, $self->{AUDIO_CODEC_TRANSCODE}, 'MediaType');
			$self->{FILE_EXTENSION} = PDLNA::Media::details($self->{CONTAINER_TRANSCODE}, $self->{VIDEO_CODEC_TRANSCODE}, $self->{AUDIO_CODEC_TRANSCODE}, 'FileExtension');

			$self->{COMMAND} = $CONFIG{'FFMPEG_BIN'}.' -i "'.$self->{PATH}.'" '.PDLNA::Media::details($self->{CONTAINER_TRANSCODE}, $self->{VIDEO_CODEC_TRANSCODE}, $self->{AUDIO_CODEC_TRANSCODE}, 'FFmpegParam').' pipe: 2>/dev/null';
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

sub file
{
	my $self = shift;
	return $self->{FILE};
}

sub command
{
	my $self = shift;
	return $self->{COMMAND};
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

	# Samsung does not accept some normal MIME_TYPEs
	if ($device eq 'Samsung DTV DMR')
	{
		return 'video/x-mkv' if $self->{MIME_TYPE} eq 'video/x-matroska';
		return 'video/x-avi' if $self->{MIME_TYPE} eq 'video/x-msvideo';
#		return 'audio/L16' if $self->{MIME_TYPE} eq 'audio/x-aiff';
#		return 'audio/L16' if $self->{MIME_TYPE} eq 'audio/x-wav';
	}
	return $self->{MIME_TYPE};
}

sub dlna_contentfeatures
{
	my $self = shift;
	my $type = shift || '';

	my $contentfeature = '';

	# DLNA.ORG_PN - media profile
#	$contentfeature = 'DLNA.ORG_PN=WMABASE;' if $self->{MIME_TYPE} eq 'audio/x-ms-wma';
#	$contentfeature = 'DLNA.ORG_PN=LPCM;' if $self->{MIME_TYPE} eq 'audio/L16';
#	$contentfeature = 'DLNA.ORG_PN=LPCM;' if $self->{MIME_TYPE} eq 'audio/x-aiff';
#	$contentfeature = 'DLNA.ORG_PN=LPCM;' if $self->{MIME_TYPE} eq 'audio/x-wav';
	$contentfeature = 'DLNA.ORG_PN=WMABASE;' if $self->{MIME_TYPE} eq 'audio/x-ms-wma';
	$contentfeature = 'DLNA.ORG_PN=MP3;' if $self->{MIME_TYPE} eq 'audio/mpeg';
	$contentfeature = 'DLNA.ORG_PN=JPEG_LRG;' if $self->{MIME_TYPE} eq 'image/jpeg';
	$contentfeature = 'DLNA.ORG_PN=JPEG_TN;' if $type eq 'JPEG_TN';
	$contentfeature = 'DLNA.ORG_PN=JPEG_SM;' if $type eq 'JPEG_SM';

	# DLNA.ORG_OP=ab
	# 	a - server supports TimeSeekRange
	# 	b - server supports RANGE
	unless ($type eq 'JPEG_TN' || $type eq 'JPEG_SM' || $self->{TYPE} eq 'image' || !$self->{FILE})
	{
		$contentfeature .= 'DLNA.ORG_OP=01;'; # deactivate seeking for transcoded or streamed media files (and images :P)
	}

	# DLNA.ORG_PS - supported play speeds

	# DLNA.ORG_CI - if media is transcoded
	if ($type eq 'JPEG_TN' || $type eq 'JPEG_SM')
	{
		$contentfeature .= 'DLNA.ORG_CI=1;';
	}
	else
	{
		$contentfeature .= 'DLNA.ORG_CI=0;';
	}

	# DLNA.ORG_FLAGS - binary flags with device parameters
	if ($type eq 'JPEG_TN' || $type eq 'JPEG_SM' || $self->{TYPE} eq 'image')
	{
		$contentfeature .= 'DLNA.ORG_FLAGS=00D00000000000000000000000000000';
	}
#	elsif ($self->{MIME_TYPE} eq 'audio/x-aiff' || $self->{MIME_TYPE} eq 'audio/x-wav')
#	{
#		$contentfeature .= 'DLNA.ORG_FLAGS=61F00000000000000000000000000000';
#	}
	else
	{
		$contentfeature .= 'DLNA.ORG_FLAGS=01500000000000000000000000000000';
	}

	return $contentfeature;
}

sub width
{
	my $self = shift;
	return $self->{WIDTH};
}

sub height
{
	my $self = shift;
	return $self->{HEIGHT};
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
	$string .= $input."\tFileName:      ".$self->{NAME}."\n";
	if ($self->{FILE} || $self->{CONTAINER_TRANSCODE})
	{
		$string .= $input."\tPath:          ".$self->{PATH}."\n";
	}
	if (!$self->{FILE})
	{
		$string .= $input."\tCommand:       ".$self->{COMMAND}."\n" if $self->{COMMAND};
	}
	$string .= $input."\tFileExtension: ".$self->{FILE_EXTENSION}."\n";
	$string .= $input."\tType:          ".$self->{TYPE}."\n";
	$string .= $input."\tDate:          ".$self->{DATE}." (".time2str($CONFIG{'DATE_FORMAT'}, $self->{DATE}).")\n" if $self->{DATE};
	$string .= $input."\tSize:          ".$self->{SIZE}." Bytes (".PDLNA::Utils::convert_bytes($self->{SIZE}).")\n" if $self->{SIZE};
	$string .= $input."\tMimeType:      ".$self->{MIME_TYPE}."\n" if $self->{MIME_TYPE};

	if ($self->{TYPE} eq 'image')
	{
		$string .= $input."\tResolution:    ".$self->{WIDTH}."x".$self->{HEIGHT}." px\n";
	}
	if ($self->{TYPE} eq 'audio' && ($self->{FILE} || $self->{AUDIO_CODEC_TRANSCODE}))
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
	elsif ($self->{TYPE} eq 'video' && ($self->{FILE} || $self->{AUDIO_CODEC_TRANSCODE} || $self->{VIDEO_CODEC_TRANSCODE}))
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
		$string .= $input."\tContainer:     ";
		$string .= $self->{CONTAINER} if $self->{CONTAINER};
		$string .= " (transcode to ".$self->{CONTAINER_TRANSCODE}.")" if $self->{CONTAINER_TRANSCODE};
		$string .= "\n";

		$string .= $input."\tAudioCodec:    ";
		$string .= $self->{AUDIO_CODEC} if $self->{AUDIO_CODEC};
		$string .= " (transcode to ".$self->{AUDIO_CODEC_TRANSCODE}.")" if $self->{AUDIO_CODEC_TRANSCODE};
		$string .= "\n";
	}
	if ($self->{TYPE} eq 'video')
	{
		$string .= $input."\tVideoCodec:    ";
		$string .= $self->{VIDEO_CODEC} if $self->{VIDEO_CODEC};
		$string .= " (transcode to ".$self->{VIDEO_CODEC_TRANSCODE}.")" if $self->{VIDEO_CODEC_TRANSCODE};
		$string .= "\n";
	}
	$string .= $input."Object PDLNA::ContentItem END\n";

	return $string;
}

1;
