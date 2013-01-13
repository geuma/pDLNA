package PDLNA::Media;
#
# pDLNA - a perl DLNA media server
# Copyright (C) 2010-2013 Stefan Heumader <stefan@heumader.at>
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
use Fcntl;
use Image::Info qw(image_info dim image_type);
use Movie::Info;
use MP3::Info;
use MP4::Info;
use Ogg::Vorbis::Header;
use XML::Simple;

my %MIME_TYPES = (
	'image/jpeg' => 'jpeg',
	'image/gif' => 'gif',

	'audio/mpeg' => 'mp3',
	'audio/mp4' => 'mp4',
	'audio/x-ms-wma' => 'wma',
	'audio/x-flac' => 'flac',
	'audio/x-wav' => 'wav',
	'video/x-theora+ogg' => 'ogg',
	'audio/ac3' => 'ac3',
	'audio/x-aiff' => 'lpcm',

	'video/x-msvideo' => 'avi',
	'video/x-matroska' => 'mkv',
	'video/mp4' => 'mp4',
	'video/mpeg' => 'mpg',
	'video/x-flv' => 'flv',
);

my %PLAYLISTS = (
	'audio/x-scpls' => 'pls',
	'application/vnd.apple.mpegurl' => 'm3u',
	'audio/x-mpegurl' => 'm3u',
	'audio/x-ms-asx' => 'asx',
	'video/x-ms-asf' => 'asf',
	'application/xspf+xml' => 'xspf',
);

my %SUBTITLES = (
	'application/x-subrip' => 'srt',
);

my %AUDIO_CODECS = (
	'a52' => 'ac3',
	'faad' => 'aac',
	'ffflac' => 'flac',
	'mp3' => 'mp3',
	'ffvorbis' => 'vorbis',
	'pcm' => 'wav',
	'ffwmav2' => 'wmav2',
	'ffmp3float' => 'mp3',
	'ffaac' => 'aac',
);

my %VIDEO_CODECS = (
	'ffh264' => 'h264',
	'ffwmv3' => 'wmvv3',  # or shall we name it wmvv9 ??
	'ffdivx' => 'divx', # mpeg4 video v3
	'ffodivx' => 'xvid', # mpeg4 video
	'mpegpes' => 'mpg', # mpeg 1/2 video
);

my %CONTAINER = (
	'audio' => {
		'AudioCodecs' => ['mp3', 'ffflac', 'pcm', 'ffmp3float'],
		'VideoCodecs' => [],
		'mp3' => {
			'MimeType' => 'audio/mpeg',
			'FileExtension' => 'mp3',
			'MediaType' => 'audio',
		},
		'ffmp3float' => {
			'MimeType' => 'audio/mpeg',
			'FileExtension' => 'mp3',
			'MediaType' => 'audio',
		},
		'ffflac' => {
			'MimeType' => 'audio/x-flac',
			'FileExtension' => 'flac',
			'MediaType' => 'audio',
			'FFmpegParam' => '-f flac',
		},
		'pcm' => {
			'MimeType' => 'audio/x-wav',
			'FileExtension' => 'wav',
			'MediaType' => 'audio',
		},
	},
	'asf' => {
		'AudioCodecs' => ['ffwmav2', ],
		'VideoCodecs' => [],
		'ffwmav2' => {
			'MimeType' => 'audio/x-ms-wma',
			'FileExtension' => 'wma',
			'MediaType' => 'audio',
		},
		'ffwmv3' => {
			'MimeType' => 'audio/x-ms-wmv',
			'FileExtension' => 'wmv',
			'MediaType' => 'video',
		},
	},
	'avi' => {
		'AudioCodecs' => ['mp3', 'a52', ],
		'VideoCodecs' => ['ffodivx', 'ffdivx', ],
		'ffodivx' => {
			'MimeType' => 'video/x-msvideo', # video/avi, video/msvideo
			'FileExtension' => 'avi',
			'MediaType' => 'video',
		},
		'ffdivx' => {
			'MimeType' => 'video/x-msvideo', # video/avi, video/msvideo
			'FileExtension' => 'avi',
			'MediaType' => 'video',
		},
	},
	'avini' => {
		'AudioCodecs' => ['mp3', 'a52', ],
		'VideoCodecs' => ['ffodivx', 'ffdivx', ],
		'ffodivx' => {
			'MimeType' => 'video/x-msvideo', # video/avi, video/msvideo
			'FileExtension' => 'avi',
			'MediaType' => 'video',
		},
		'ffdivx' => {
			'MimeType' => 'video/x-msvideo', # video/avi, video/msvideo
			'FileExtension' => 'avi',
			'MediaType' => 'video',
		},
	},
	'lavf' => {
		'AudioCodecs' => ['a52', 'pcm'],
		'VideoCodecs' => [],
		'a52' => {
			'MimeType' => 'audio/ac3',
			'FileExtension' => 'ac3',
			'MediaType' => 'audio',
		},
		'pcm' => {
			'MimeType' => 'audio/x-aiff',
			'FileExtension' => 'aif',
			'MediaType' => 'audio',
		},
	},
	'lavfpref' => {
		'AudioCodecs' => ['faad', 'ffaac'],
		'VideoCodecs' => ['ffodivx', 'ffh264', 'ffvp6f'],
		'ffh264' => {
			'MimeType' => 'video/x-flv',
			'FileExtension' => 'flv',
			'MediaType' => 'video',
		},
		'faad' => {
			'MimeType' => 'audio/mp4',
			'FileExtension' => 'mp4', # m4a
			'MediaType' => 'audio',
		},
		'ffaac' => {
			'MimeType' => 'audio/mp4',
			'FileExtension' => 'mp4', # m4a
			'MediaType' => 'audio',
		},
		'ffodivx' => {
			'MimeType' => 'video/mp4',
			'FileExtension' => 'mp4',
			'MediaType' => 'video',
		},
		'ffvp6f' => {
			'MimeType' => 'video/x-flv',
			'FileExtension' => 'flv',
			'MediaType' => 'video',
		},
	},
	'mkv' => {
		'AudioCodecs' => ['a52', ],
		'VideoCodecs' => ['ffh264', 'ffodivx', ],
		'ffh264' => {
			'MimeType' => 'video/x-matroska',
			'FileExtension' => 'mkv',
			'MediaType' => 'video',
		},
		'ffodivx' => {
			'MimeType' => 'video/x-matroska',
			'FileExtension' => 'mkv',
			'MediaType' => 'video',
		},
	},
	'mov' => {
		'AudioCodecs' => ['faad', ],
		'VideoCodecs' => ['ffodivx', 'ffh264', ],
		'faad' => {
			'MimeType' => 'audio/mp4',
			'FileExtension' => 'mp4', # m4a
			'MediaType' => 'audio',
		},
		'ffodivx' => {
			'MimeType' => 'video/mp4',
			'FileExtension' => 'mp4',
			'MediaType' => 'video',
		},
		'ffh264' => {
			'MimeType' => 'video/mp4',
			'FileExtension' => 'mp4',
			'MediaType' => 'video',
		},
	},
	'mpegps' => {
		'AudioCodecs' => ['a52', 'mp3', ],
		'VideoCodecs' => ['mpegpes', ],
		'mpegpes' => {
			'MimeType' => 'video/mpeg',
			'FileExtension' => 'mpg',
			'MediaType' => 'video',
		},
	},
	'ogg' => {
		'AudioCodecs' => ['ffvorbis', ],
		'VideoCodecs' => [],
		'ffvorbis' => {
			'MimeType' => 'video/x-theora+ogg',
			'FileExtension' => 'ogg',
			'MediaType' => 'audio',
		},
	},
);

sub audio_codec_by_beautiful_name
{
	my $beautiful_name = shift;
	foreach my $audio_codec (keys %AUDIO_CODECS)
	{
		return $audio_codec if $AUDIO_CODECS{$audio_codec} eq $beautiful_name;
	}
	return undef;
}

sub audio_codec_by_name
{
	my $name = shift;
	return $AUDIO_CODECS{$name} if defined($AUDIO_CODECS{$name});
	return undef;
}

sub video_codec_by_beautiful_name
{
	my $beautiful_name = shift;
	foreach my $video_codec (keys %VIDEO_CODECS)
	{
		return $video_codec if $VIDEO_CODECS{$video_codec} eq $beautiful_name;
	}
	return undef;
}

sub container_by_beautiful_name
{
	my $beautiful_name = shift;
	return $beautiful_name if defined($CONTAINER{$beautiful_name});
	return undef;
}

sub container_supports_audio_codec
{
	my $container = shift;
	my $codec = shift;
	return 1 if grep(/^$codec$/, @{$CONTAINER{$container}->{AudioCodecs}});
	return 0;
}

sub container_supports_audio
{
	my $container = shift;
	return scalar(@{$CONTAINER{$container}->{AudioCodecs}});
}

sub container_supports_video
{
	my $container = shift;
	return scalar(@{$CONTAINER{$container}->{VideoCodecs}});
}

sub details
{
	my $container = shift;
	my $video_codec = shift;
	my $audio_codec = shift;
	my $param = shift;

	if ($container && $video_codec)
	{
		if (defined($CONTAINER{$container}->{$video_codec}))
		{
			return $CONTAINER{$container}->{$video_codec}->{$param};
		}
		else
		{
			PDLNA::Log::log('Unknown MediaInformation: Container: '.$container.', AudioCodec:'.$audio_codec.', VideoCodec:'.$video_codec.'.', 1, 'library');
		}
	}
	elsif ($container && $audio_codec)
	{
		if (defined($CONTAINER{$container}->{$audio_codec}))
		{
			return $CONTAINER{$container}->{$audio_codec}->{$param};
		}
		else
		{
			PDLNA::Log::log('Unknown MediaInformation: Container: '.$container.', AudioCodec:'.$audio_codec.'.', 1, 'library');
		}
	}
	else
	{
		PDLNA::Log::log('MPlayer was unable to determine MediaInformation.', 1, 'library');
	}
	return 0;
}

sub is_supported_mimetype
{
	my $mimetype = shift;

	return 1 if defined($MIME_TYPES{$mimetype});
	return 0;
}

sub is_supported_playlist
{
	my $mimetype = shift;

	return 1 if defined($PLAYLISTS{$mimetype});
	return 0;
}

sub is_supported_subtitle
{
	my $mimetype = shift;

	return 1 if defined($SUBTITLES{$mimetype});
	return 0;
}

sub return_type_by_mimetype
{
	my $mimetype = shift;
	my ($media_type) = split('/', $mimetype, 0);
	$media_type = 'audio' if $mimetype eq 'video/x-theora+ogg';
	return $media_type;
}

sub dlna_contentfeatures
{
	my $type = shift;
	my $mimetype = shift;

	my $contentfeature = '';

# DLNA.ORG_PN - media profile
#   $contentfeature = 'DLNA.ORG_PN=WMABASE;' if $self->{MIME_TYPE} eq 'audio/x-ms-wma';
#   $contentfeature = 'DLNA.ORG_PN=LPCM;' if $self->{MIME_TYPE} eq 'audio/L16';
#   $contentfeature = 'DLNA.ORG_PN=LPCM;' if $self->{MIME_TYPE} eq 'audio/x-aiff';
#   $contentfeature = 'DLNA.ORG_PN=LPCM;' if $self->{MIME_TYPE} eq 'audio/x-wav';
	$contentfeature = 'DLNA.ORG_PN=WMABASE;' if $mimetype eq 'audio/x-ms-wma';
	$contentfeature = 'DLNA.ORG_PN=MP3;' if $mimetype eq 'audio/mpeg';
	$contentfeature = 'DLNA.ORG_PN=JPEG_LRG;' if $mimetype eq 'image/jpeg';
	$contentfeature = 'DLNA.ORG_PN=JPEG_TN;' if $type eq 'JPEG_TN';
	$contentfeature = 'DLNA.ORG_PN=JPEG_SM;' if $type eq 'JPEG_SM';

# DLNA.ORG_OP=ab
#   a - server supports TimeSeekRange
#   b - server supports RANGE
	#unless ($type eq 'JPEG_TN' || $type eq 'JPEG_SM' || $type eq 'image' || !$self->{FILE})
	unless ($type eq 'JPEG_TN' || $type eq 'JPEG_SM' || $type eq 'image')
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
	if ($type eq 'JPEG_TN' || $type eq 'JPEG_SM' || $type eq 'image')
	{
		$contentfeature .= 'DLNA.ORG_FLAGS=00D00000000000000000000000000000';
	}
#   elsif ($self->{MIME_TYPE} eq 'audio/x-aiff' || $self->{MIME_TYPE} eq 'audio/x-wav')
#   {
#       $contentfeature .= 'DLNA.ORG_FLAGS=61F00000000000000000000000000000';
#   }
	else
	{
		$contentfeature .= 'DLNA.ORG_FLAGS=01500000000000000000000000000000';
	}

	return $contentfeature;
}

sub get_image_fileinfo
{
	my $path = shift;

	my $info = image_info($path);
	return dim($info);
}

sub get_mplayer_info
{
	my $file = shift;
	my $info = shift;

	my $movie_info = Movie::Info->new();
	unless (defined($movie_info))
	{
		PDLNA::Log::fatal('Unable to find MPlayer.');
	}

	my %mplayer = $movie_info->info($file);
	if (defined($mplayer{'length'}))
	{
		$$info{DURATION} = $1 if $mplayer{'length'} =~ /^(\d+)/; # ignore milliseconds
	}
	$$info{BITRATE} = $mplayer{'audio_bitrate'} || 0;
	$$info{HZ} = $mplayer{'audio_rate'} || 0;
	$$info{WIDTH} = $mplayer{'width'} || 0;
	$$info{HEIGHT} = $mplayer{'height'} || 0;

	$$info{AUDIO_CODEC} = $mplayer{'audio_codec'} || '';
	$$info{VIDEO_CODEC} = $mplayer{'codec'} || '';
	$$info{CONTAINER} = $mplayer{'demuxer'} || '';

#	$$data{MIME_TYPE} = details($$data{CONTAINER}, $$data{VIDEO_CODEC}, $$data{AUDIO_CODEC}, 'MimeType');
#	$$data{TYPE} = details($$data{CONTAINER}, $$data{VIDEO_CODEC}, $$data{AUDIO_CODEC}, 'MediaType');
#	$$data{FILE_EXTENSION} = details($$data{CONTAINER}, $$data{VIDEO_CODEC}, $$data{AUDIO_CODEC}, 'FileExtension');

	return 1;
}

sub get_audio_fileinfo
{
	my $file = shift;
	my $audio_codec = shift;
	my $info = shift;

	if ($audio_codec eq 'mp3' || $audio_codec eq 'ffmp3float')
	{
		my $tag = get_mp3tag($file);
		if (keys %{$tag})
		{
			$$info{ARTIST} = $tag->{'ARTIST'} if length($tag->{'ARTIST'}) > 0;
			$$info{ALBUM} = $tag->{'ALBUM'} if length($tag->{'ALBUM'}) > 0;
			$$info{TRACKNUM} = $tag->{'TRACKNUM'} if length($tag->{'TRACKNUM'}) > 0;
			$$info{TITLE} = $tag->{'TITLE'} if length($tag->{'TITLE'}) > 0;
			$$info{GENRE} = $tag->{'GENRE'} if length($tag->{'GENRE'}) > 0;
			$$info{YEAR} = $tag->{'YEAR'} if length($tag->{'YEAR'}) > 0;
		}
	}
	elsif ($audio_codec eq 'faad' || $audio_codec eq 'ffaac')
	{
		my $tag = get_mp4tag($file);
		if (keys %{$tag})
		{
			$$info{ARTIST} = $tag->{'ARTIST'} if length($tag->{'ARTIST'}) > 0;
			$$info{ALBUM} = $tag->{'ALBUM'} if length($tag->{'ALBUM'}) > 0;
			$$info{TRACKNUM} = $tag->{'TRACKNUM'} if length($tag->{'TRACKNUM'}) > 0;
			$$info{TITLE} = $tag->{'TITLE'} if length($tag->{'TITLE'}) > 0;
			$$info{GENRE} = $tag->{'GENRE'} if length($tag->{'GENRE'}) > 0;
			$$info{YEAR} = $tag->{'YEAR'} if length($tag->{'YEAR'}) > 0;
		}
	}
	elsif ($audio_codec eq 'ffwmav2')
	{
		my $wma = Audio::WMA->new($file);
		my $tag = $wma->tags();
		if (keys %{$tag})
		{
			$$info{ARTIST} = $tag->{'AUTHOR'} if length($tag->{'AUTHOR'}) > 0;
			$$info{ALBUM} = $tag->{'ALBUMTITLE'} if length($tag->{'ALBUMTITLE'}) > 0;
			$$info{TRACKNUM} = $tag->{'TRACKNUMBER'} if length($tag->{'TRACKNUMBER'}) > 0;
			$$info{TITLE} = $tag->{'TITLE'} if length($tag->{'TITLE'}) > 0;
			$$info{GENRE} = $tag->{'GENRE'} if length($tag->{'GENRE'}) > 0;
			$$info{YEAR} = $tag->{'YEAR'} if length($tag->{'YEAR'}) > 0;
		}
	}
	elsif ($audio_codec eq 'ffflac')
	{
		my $flac = Audio::FLAC::Header->new($file);
		my $tag = $flac->tags();
		if (keys %{$tag})
		{
			$$info{ARTIST} = $tag->{'ARTIST'} if defined($tag->{'ARTIST'});
			$$info{ALBUM} = $tag->{'ALBUM'} if defined($tag->{'ALBUM'});
			$$info{TRACKNUM} = $tag->{'TRACKNUMBER'} if defined($tag->{'TRACKNUMBER'});
			$$info{TITLE} = $tag->{'TITLE'} if defined($tag->{'TITLE'});
			$$info{GENRE} = $tag->{'GENRE'} if defined($tag->{'GENRE'});
			$$info{YEAR} = $tag->{'DATE'} if defined($tag->{'DATE'});
		}
	}
	return 1;
}

sub get_mimetype_by_modelname
{
	my $mimetype = shift;
	my $modelname = shift || '';

	if ($modelname eq 'Samsung DTV DMR')
	{
		return 'video/x-mkv' if $mimetype eq 'video/x-matroska';
		return 'video/x-avi' if $mimetype eq 'video/x-msvideo';
	}
	return $mimetype;
}

sub parse_playlist
{
	my $file = shift;
	my $mime_type = shift;

	my @items = ();
	if ($mime_type eq 'audio/x-scpls')
	{
		# reading the playlist file
		sysopen(PLAYLIST, $file, O_RDONLY);
		my @content = <PLAYLIST>;
		close(PLAYLIST);

		foreach my $line (@content)
		{
			$line =~ s/\r\n//g;
			$line =~ s/\n//g;
			push(@items, $1) if ($line =~ /^File\d+\=(.+)$/);
		}
	}
	elsif ($mime_type eq 'application/vnd.apple.mpegurl' || $mime_type eq 'audio/x-mpegurl')
	{
		# reading the playlist file
		sysopen(PLAYLIST, $file, O_RDONLY);
		my @content = <PLAYLIST>;
		close(PLAYLIST);

		foreach my $line (@content)
		{
			$line =~ s/\r\n//g;
			$line =~ s/\n//g;
			push(@items, $line) if ($line !~ /^#/);
		}
	}
	elsif ($mime_type eq 'audio/x-ms-asx' || $mime_type eq 'video/x-ms-asf')
	{
		# TODO more beautiful way to do this
		# reading the playlist file
		sysopen(PLAYLIST, $file, O_RDONLY);
		my @content = <PLAYLIST>;
		close(PLAYLIST);

		foreach my $line (@content)
		{
			$line =~ s/\r\n//g;
			$line =~ s/\n//g;
			$line =~ s/^\s+//g;
		}

		foreach my $entry (split(/(<.+?>)/, join('', @content)))
		{
			push(@items, $1) if $entry =~ /^<ref\s+href=\"(.+)\"\s*\/>$/;
		}
	}
	elsif ($mime_type eq 'application/xspf+xml')
	{
		my $xs = XML::Simple->new();
		my $xml = $xs->XMLin($file);
		foreach my $element (@{$xml->{trackList}->{track}})
		{
			if ($element->{location} =~ /^file:\/\/(.+)$/)
			{
				push(@items, $1);
			}
			elsif ($element->{location} =~ /^http:\/\//)
			{
				push(@items, $element->{location});
			}
		}
	}
	return @items;
}

1;
