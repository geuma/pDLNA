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
use Ogg::Vorbis::Header::PurePerl;
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



















#
# TODO DO WE NEED THIS
#

my %AUDIO_CODECS = (
	'ffac3' => 'ac3',
	'a52' => 'ac3',
	'faad' => 'aac',
	'ffflac' => 'flac',
	'mp3' => 'mp3',
	'ffvorbis' => 'vorbis',
	'pcm' => 'wav',
	'ffwmav1' => 'wmav1',
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

#
# TODO END
#

















my %CONTAINER = (
	'avi' => {
		'AudioCodecs' => [ 'mp3', 'mp2', ],
		'VideoCodecs' => [ 'mpeg4', 'msmpeg4', 'msmpeg4v2' ],
		'mpeg4' => {
			'MimeType' => 'video/x-msvideo', # video/avi, video/msvideo
			'FileExtension' => 'avi',
			'MediaType' => 'video',
		},
		'msmpeg4' => {
			'MimeType' => 'video/x-msvideo', # video/avi, video/msvideo
			'FileExtension' => 'avi',
			'MediaType' => 'video',
		},
		'msmpeg4v2' => {
			'MimeType' => 'video/x-msvideo', # video/avi, video/msvideo
			'FileExtension' => 'avi',
			'MediaType' => 'video',
		},
	},
	'mp3' => {
		'AudioCodecs' => [ 'mp3', ],
		'VideoCodecs' => [],
		'mp3' => {
			'MimeType' => 'audio/mpeg',
			'FileExtension' => 'mp3',
			'MediaType' => 'audio',
		},
	},
	'mov' => {
		'AudioCodecs' => [ 'mpeg4aac', 'aac', ],
		'VideoCodecs' => [ 'h264', 'mpeg4', ],
		'mpeg4aac' => {
			'MimeType' => 'audio/mp4',
			'FileExtension' => 'mp4', # m4a
			'MediaType' => 'audio',
		},
		'aac' => {
			'MimeType' => 'audio/mp4',
			'FileExtension' => 'mp4', # m4a
			'MediaType' => 'audio',
		},
		'h264' => {
			'MimeType' => 'video/mp4',
			'FileExtension' => 'mp4',
			'MediaType' => 'video',
		},
		'mpeg4' => {
			'MimeType' => 'video/mp4',
			'FileExtension' => 'mp4',
			'MediaType' => 'video',
		},
	},
	'ac3' => {
		'AudioCodecs' => [ 'ac3', ],
		'VideoCodecs' => [],
		'ac3' => {
			'MimeType' => 'audio/ac3',
			'FileExtension' => 'ac3',
			'MediaType' => 'audio',
		},
	},
	'flac' => {
		'AudioCodecs' => [ 'flac', ],
		'VideoCodecs' => [],
		'flac' => {
			'MimeType' => 'audio/flac',
			'FileExtension' => 'flac',
			'MediaType' => 'audio',
		},
	},
	'ogg' => {
		'AudioCodecs' => [ 'vorbis', ],
		'VideoCodecs' => [],
		'vorbis' => {
			'MimeType' => 'video/x-theora+ogg',
			'FileExtension' => 'ogg',
			'MediaType' => 'audio',
		},
	},
	'wav' => {
		'AudioCodecs' => [ 'pcm_s16le', ],
		'VideoCodecs' => [],
		'pcm_s16le' => {
			'MimeType' => 'audio/wav',
			'FileExtension' => 'wav',
			'MediaType' => 'audio',
		},
	},
	'asf' => {
		'AudioCodecs' => [ 'wmav1', 'wmav2', ],
		'VideoCodecs' => [],
		'wmav1' => {
			'MimeType' => 'audio/x-ms-wma',
			'FileExtension' => 'wma',
			'MediaType' => 'audio',
		},
		'wmav2' => {
			'MimeType' => 'audio/x-ms-wma',
			'FileExtension' => 'wma',
			'MediaType' => 'audio',
		},
	},
	'matroska' => {
		'AudioCodecs' => [ 'ac3', ],
		'VideoCodecs' => [ 'h264', 'mpeg4', ],
		'h264' => {
			'MimeType' => 'video/x-matroska',
			'FileExtension' => 'mkv',
			'MediaType' => 'video',
		},
		'mpeg4' => {
			'MimeType' => 'video/x-matroska',
			'FileExtension' => 'mkv',
			'MediaType' => 'video',
		},
	},
	'mpeg' => {
		'AudioCodecs' => [ 'mp2', 'ac3', ],
		'VideoCodecs' => [ 'mpeg1video', 'mpeg2video', ],
		'mpeg1video' => {
			'MimeType' => 'video/mpeg',
			'FileExtension' => 'mpg',
			'MediaType' => 'video',
		},
		'mpeg2video' => {
			'MimeType' => 'video/mpeg',
			'FileExtension' => 'mpg',
			'MediaType' => 'video',
		},
	},
	'flv' => {
		'AudioCodecs' => [ 'mp3', ],
		'VideoCodecs' => [ 'vp6f', ],
		'vp6f' => {
			'MimeType' => 'video/x-flv',
			'FileExtension' => 'flv',
			'MediaType' => 'video',
		},
	},
);















my %FOO = (
	'asf' => {
		'AudioCodecs' => ['ffwmav2', 'ffwmav1', ],
		'VideoCodecs' => [],
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
		'AudioCodecs' => ['a52', 'pcm', 'ffac3', ],
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
		'ffac3' => {
			'MimeType' => 'audio/ac3',
			'FileExtension' => 'ac3',
			'MediaType' => 'audio',
		},
	},
	'lavfpref' => {
		'AudioCodecs' => ['faad', 'ffaac'],
		'VideoCodecs' => ['ffodivx', 'ffh264', 'ffvp6f', 'ffvorbis', ],
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
		'ffvorbis' => {
			'MimeType' => 'video/x-theora+ogg',
			'FileExtension' => 'ogg',
			'MediaType' => 'audio',
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

	return 0 unless defined($container);
	return scalar(@{$CONTAINER{$container}->{AudioCodecs}});
}

sub container_supports_video
{
	my $container = shift;

	return 0 unless defined($container);
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
		PDLNA::Log::log('ERROR: MPlayer was unable to determine MediaInformation.', 0, 'library');
	}
	return undef;
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

sub is_supported_stream
{
	my $url = shift || '';

	return 1 if $url =~ /^(http|mms):\/\//;
	return 0;
}

sub return_type_by_mimetype
{
	my $mimetype = shift;
	my ($media_type) = split('/', $mimetype, 0);
	$media_type = 'audio' if $mimetype eq 'video/x-theora+ogg';
	return $media_type;
}

sub get_dlnacontentfeatures
{
	my $item = shift;
	my $transcode = shift;
	my $type = shift;

	my $contentfeatures = '';

	# DLNA.ORG_PN - media profile
	if (defined($item))
	{
#		$contentfeatures .= 'DLNA.ORG_PN=LPCM;' if $self->{MIME_TYPE} eq 'audio/L16';
#		$contentfeatures .= 'DLNA.ORG_PN=LPCM;' if $self->{MIME_TYPE} eq 'audio/x-aiff';
#		$contentfeatures .= 'DLNA.ORG_PN=LPCM;' if $self->{MIME_TYPE} eq 'audio/x-wav';
		$contentfeatures .= 'DLNA.ORG_PN=WMABASE;' if $item->{MIME_TYPE} eq 'audio/x-ms-wma';
		$contentfeatures .= 'DLNA.ORG_PN=MP3;' if $item->{MIME_TYPE} eq 'audio/mpeg';
		$contentfeatures .= 'DLNA.ORG_PN=JPEG_LRG;' if $item->{MIME_TYPE} eq 'image/jpeg';
	}
	else
	{
		$contentfeatures .= 'DLNA.ORG_PN=JPEG_TN;' if $type eq 'JPEG_TN';
		$contentfeatures .= 'DLNA.ORG_PN=JPEG_SM;' if $type eq 'JPEG_SM';
	}

	# DLNA.ORG_OP=ab
	#   a - server supports TimeSeekRange
	#   b - server supports RANGE
	if (defined($item))
	{
		if ($item->{TYPE} eq 'image')
		{
			$contentfeatures .= 'DLNA.ORG_OP=00;'; # deactivate seeking for images
		}
		elsif ($transcode)
		{
			$contentfeatures .= 'DLNA.ORG_OP=00;'; # deactivate seeking for transcoded media items
		}
		elsif ($item->{EXTERNAL})
		{
			$contentfeatures .= 'DLNA.ORG_OP=00;'; # deactivate seeking for external media items
		}
		else
		{
			$contentfeatures .= 'DLNA.ORG_OP=01;'; # activate seeking by RANGE command
		}
	}
	else
	{
		$contentfeatures .= 'DLNA.ORG_OP=00;'; # deactivate seeking for thumbnails
	}

	# DLNA.ORG_PS - supported play speeds
	# TODO

	# DLNA.ORG_CI - for transcoded media items it is set to 1
	$contentfeatures .= 'DLNA.ORG_CI='.$transcode.';';

	# DLNA.ORG_FLAGS - binary flags with device parameters
	if (defined($item))
	{
		if ($item->{TYPE} eq 'image')
		{
			$contentfeatures .= 'DLNA.ORG_FLAGS=00D00000000000000000000000000000';
		}
#		elsif ($self->{MIME_TYPE} eq 'audio/x-aiff' || $self->{MIME_TYPE} eq 'audio/x-wav')
#		{
#			$contentfeatures .= 'DLNA.ORG_FLAGS=61F00000000000000000000000000000';
#		}
		else
		{
			$contentfeatures .= 'DLNA.ORG_FLAGS=01500000000000000000000000000000';
		}
	}
	else
	{
		$contentfeatures .= 'DLNA.ORG_FLAGS=00D00000000000000000000000000000';
	}

	return $contentfeatures;
}

sub get_image_fileinfo
{
	my $path = shift;

	my $info = image_info($path);
	return dim($info);
}

sub get_audio_fileinfo
{
	my $file = shift;
	my $audio_codec = shift;
	my $info = shift;

	if ($audio_codec eq 'mp3')
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
	elsif ($audio_codec eq 'mpeg4aac')
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
	elsif ($audio_codec eq 'wmav2') # TODO wmav1
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
	elsif ($audio_codec eq 'flac')
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
	elsif ($audio_codec eq 'vorbis')
	{
		my $ogg = Ogg::Vorbis::Header::PurePerl->new($file);
		($$info{ARTIST}) = $ogg->comment('artist') if $ogg->comment('artist');
		($$info{ALBUM}) = $ogg->comment('album') if $ogg->comment('album');
		($$info{TRACKNUM}) = $ogg->comment('tracknumber') if $ogg->comment('tracknumber');
		($$info{TITLE}) = $ogg->comment('title') if $ogg->comment('title');
		($$info{GENRE}) = $ogg->comment('genre') if $ogg->comment('genre');
		($$info{YEAR}) = $ogg->comment('year') if $ogg->comment('year');
	}
	# TODO ac3
	# TODO wav
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
