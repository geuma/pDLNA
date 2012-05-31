package PDLNA::Media;
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

use Movie::Info;

my %AUDIO_CODECS = (
	'a52' => 'ac3',
	'faad' => 'aac',
	'ffflac' => 'flac',
	'mp3' => 'mp3',
	'ffvorbis' => 'vorbis',
	'pcm' => 'wav',
	'ffwmav2' => 'wmav2',
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
		'AudioCodecs' => ['mp3', 'ffflac', 'pcm', ],
		'VideoCodecs' => [],
		'mp3' => {
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
		'AudioCodecs' => ['faad', ],
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

sub info
{
	my $data = shift;

	my $movie_info = Movie::Info->new();
	unless (defined($movie_info))
	{
		PDLNA::Log::fatal('Unable to find MPlayer.');
	}

	my %info = $movie_info->info($$data{PATH});
	if (defined($info{'length'}))
	{
		$$data{DURATION_SECONDS} = $1 if $info{'length'} =~ /^(\d+)/; # ignore milliseconds
	}
	$$data{BITRATE} = $info{'audio_bitrate'} || 0;
	$$data{HZ} = $info{'audio_rate'} || 0;
	$$data{WIDTH} = $info{'width'} || 0;
	$$data{HEIGHT} = $info{'height'} || 0;

	$$data{AUDIO_CODEC} = $info{'audio_codec'} || '';
	$$data{VIDEO_CODEC} = $info{'codec'} || '';
	$$data{CONTAINER} = $info{'demuxer'} || '';

	$$data{MIME_TYPE} = details($$data{CONTAINER}, $$data{VIDEO_CODEC}, $$data{AUDIO_CODEC}, 'MimeType');
	$$data{TYPE} = details($$data{CONTAINER}, $$data{VIDEO_CODEC}, $$data{AUDIO_CODEC}, 'MediaType');
	$$data{FILE_EXTENSION} = details($$data{CONTAINER}, $$data{VIDEO_CODEC}, $$data{AUDIO_CODEC}, 'FileExtension');
	return 1;
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

1;
