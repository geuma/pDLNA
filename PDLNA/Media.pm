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


use Fcntl;
use XML::Simple;

use PDLNA::Config;

my %MIME_TYPES = (
	'image/jpeg' => 'jpeg',
	'image/gif' => 'gif',
    'image/png' => 'png',
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
	'ffac3' => 'ac3',
	'a52' => 'ac3',
	'faad' => 'aac',
	'ffflac' => 'flac',
	'mp3' => 'mp3',
	'ffvorbis' => 'vorbis',
	'pcm' => 'wav',
    'pcm_s16le' => 'wav',
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

my %CONTAINER = (
	'audio' => {
		'AudioCodecs' => ['mp3', 'flac', 'pcm', 'mp3float'],
		'VideoCodecs' => [],
		'mp3' => {
			'MimeType' => 'audio/mpeg',
			'FileExtension' => 'mp3',
			'MediaType' => 'audio',
		},
		'mp3float' => {
			'MimeType' => 'audio/mpeg',
			'FileExtension' => 'mp3',
			'MediaType' => 'audio',
		},
		'flac' => {
			'MimeType' => 'audio/x-flac',
			'FileExtension' => 'flac',
			'MediaType' => 'audio',
		},
		'pcm' => {
			'MimeType' => 'audio/x-wav',
			'FileExtension' => 'wav',
			'MediaType' => 'audio',
		},
	},
    'wav' => {
		'AudioCodecs' => ['mp3', 'pcm_s16le'],
		'VideoCodecs' => [],
		'mp3' => {
			'MimeType' => 'audio/mpeg',
			'FileExtension' => 'mp3',
			'MediaType' => 'audio',
		},
		'pcm_s16le' => {
			'MimeType' => 'audio/x-wav',
			'FileExtension' => 'wav',
			'MediaType' => 'audio',
		},
	},
    'mp3' => {
		'AudioCodecs' => ['mp3'],
		'VideoCodecs' => [],
		'mp3' => {
			'MimeType' => 'audio/mpeg',
			'FileExtension' => 'mp3',
			'MediaType' => 'audio',
		},
	},
	'asf' => {
		'AudioCodecs' => ['wmav2', 'wmav1', ],
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
		'wmv3' => {
			'MimeType' => 'audio/x-ms-wmv',
			'FileExtension' => 'wmv',
			'MediaType' => 'video',
		},
	},
	'avi' => {
		'AudioCodecs' => ['mp3', 'a52', 'pcm_s16le'],
		'VideoCodecs' => ['xdiv', 'divx', 'mpeg4','msmpeg4v3', 'h264','msmpeg4v1'],
		'xvid' => {
			'MimeType' => 'video/x-divx', # video/avi, video/msvideo
			'FileExtension' => 'avi',
			'MediaType' => 'video',
		},
		'divx' => {
			'MimeType' => 'video/x-divx', # video/avi, video/msvideo
			'FileExtension' => 'avi',
			'MediaType' => 'video',
		},
        'mpeg4' => {
			'MimeType' => 'video/mp4', # video/avi, video/msvideo
			'FileExtension' => 'avi',
			'MediaType' => 'video',
		},
        'msmpeg4v3' => {
			'MimeType' => 'video/mp4', # video/avi, video/msvideo
			'FileExtension' => 'avi',
			'MediaType' => 'video',
		},
        'msmpeg4v1' => {
			'MimeType' => 'video/mp4', # video/avi, video/msvideo
			'FileExtension' => 'avi',
			'MediaType' => 'video',
		},
        'h264' => {
			'MimeType' => 'video/mp4', # video/avi, video/msvideo
			'FileExtension' => 'avi',
			'MediaType' => 'video',
		},
	},

	'matroska' => {
		'AudioCodecs' => ['a52', ],
		'VideoCodecs' => ['h264', 'divx', ],
		'h264' => {
			'MimeType' => 'video/x-matroska',
			'FileExtension' => 'mkv',
			'MediaType' => 'video',
		},
		'divx' => {
			'MimeType' => 'video/x-matroska',
			'FileExtension' => 'mkv',
			'MediaType' => 'video',
		},
	},
	'mov' => {
		'AudioCodecs' => ['faad','aac' ],
		'VideoCodecs' => ['divx', 'h264','mpeg4' ],
		'faad' => {
			'MimeType' => 'audio/mp4',
			'FileExtension' => 'mp4', # m4a
			'MediaType' => 'audio',
		},
        'aac' => {
			'MimeType' => 'audio/mp4',
			'FileExtension' => 'mp4', # m4a
			'MediaType' => 'audio',
		},
		'divx' => {
			'MimeType' => 'video/mp4',
			'FileExtension' => 'mp4',
			'MediaType' => 'video',
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
	'mpegps' => {
		'AudioCodecs' => ['a52', 'mp3', ],
		'VideoCodecs' => ['mpegpes', ],
		'mpegpes' => {
			'MimeType' => 'video/mpeg',
			'FileExtension' => 'mpg',
			'MediaType' => 'video',
		},
	},
    'mpeg' => {
		'AudioCodecs' => ['mp2', 'pcm_s16be'],
		'VideoCodecs' => ['mpeg2video', 'mpeg1video' ],
		'mpeg2video' => {
			'MimeType' => 'video/mpeg',
			'FileExtension' => 'mpg',
			'MediaType' => 'video',
		},
        'mpeg1video' => {
			'MimeType' => 'video/mpeg',
			'FileExtension' => 'mpg',
			'MediaType' => 'video',
		},
	},
	'ogg' => {
		'AudioCodecs' => ['vorbis', ],
		'VideoCodecs' => ['mpeg4', 'xvid'],
		'vorbis' => {
			'MimeType' => 'video/x-theora+ogg',
			'FileExtension' => 'ogg',
			'MediaType' => 'audio',
		},
        'mpeg4' => {
			'MimeType' => 'video/mp4',
			'FileExtension' => 'mp4',
			'MediaType' => 'video',
		},
        'xvid' => {
			'MimeType' => 'video/mp4',
			'FileExtension' => 'mp4',
			'MediaType' => 'video',
		},
    },
    'flv' => {
		'AudioCodecs' => ['aac', 'mp3'],
		'VideoCodecs' => ['h264',  ],
		'h264' => {
			'MimeType' => 'video/x-flv',
			'FileExtension' => 'flv',
			'MediaType' => 'video',
		},

	},
   'image2' => {
		'AudioCodecs' => [ ],
		'VideoCodecs' => ['mjpeg','png'  ],
		'mjpeg' => {
			'MimeType' => 'image/jpeg',
			'FileExtension' => 'jpg',
			'MediaType' => 'image',
		},
        'png' => {
			'MimeType' => 'image/png',
			'FileExtension' => 'png',
			'MediaType' => 'image',
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
		PDLNA::Log::log('FFMPEG was unable to determine MediaInformation.', 1, 'library');
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

	return 1 if $url =~ /^(http|mms|rtmp):\/\//;
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


sub get_media_info
{
	my $file = shift;
	my $info = shift;

 
    $$info{DURATION} = 0;
    my $ffmpegbin = PDLNA::Config::get_ffmpeg();
    my $rtmpdumpbin = PDLNA::Config::get_rtmpdump();
    
    my $cmd;
    if ($file =~ /^rtmp:\/\//) { $cmd = "$rtmpdumpbin -m 200 -r $file -q | $ffmpegbin -i pipe:0 2>&1 "; }
    else                       { $cmd = "$ffmpegbin -i \"$file\" 2>&1"; }
    

    
    open(CMD,"$cmd |") or PDLNA::Log::fatal('Unable to find the FFMPEG binary:'.$ffmpegbin);
    while(<CMD>) 
    {
        if (/Duration: (\d\d):(\d\d):(\d\d).(\d+), /)
        {
          $$info{DURATION} = 3600*$1+60*$2+$3; # ignore miliseconds
        }
        if (/Stream .+: Audio: ([\w|\d|_]+) .+, (\d+) Hz, .+, (\d+) kb\/s/)
        {

         $$info{AUDIO_CODEC} = $1;
         $$info{BITRATE}     = $3*1000;
        }
        elsif (/Stream .+: Audio: ([\w|\d|_]+), (\d+) Hz, .+, (\d+) kb\/s/)
        {
  
         $$info{AUDIO_CODEC} = $1;
         $$info{BITRATE}     = $3*1000;
        }
        elsif (/Stream .+ Video: ([\w|\d]+) .+, (\d+)x(\d+)/)
        {         
         $$info{VIDEO_CODEC} = $1;
         $$info{WIDTH}       = $2;
         $$info{HEIGHT}      = $3;
         if (/XVID/ ) { $$info{VIDEO_CODEC} = "xvid"; }
        }
        elsif (/Stream .+ Video: ([\w|\d]+), .+, (\d+)x(\d+)/)
        {         
         $$info{VIDEO_CODEC} = $1;
         $$info{WIDTH}       = $2;
         $$info{HEIGHT}      = $3;
         if (/XVID/ ) { $$info{VIDEO_CODEC} = "xvid"; }
        }
        elsif (/TITLE\S:\S(.+)$/i)
        {
         $$info{TITLE} = $1;
        }
        elsif (/ARTIST\S:\S(.+)$/i)
        {
         $$info{ARTIST} = $1;
        }
        elsif (/ALBUM\S:\S(.+)$/i)
        {
         $$info{ALBUM} = $1;
        }
        elsif (/TRACK\S:\S(\d+)$/i)
        {
         $$info{TRACKNUM} = $1;
        }
        elsif (/GENRE\S:\S(.+)$/i)
        {
         $$info{GENRE} = $1;
        }
        elsif (/DATE\S:\S(\d\d\d\d)$/i)
        {
         $$info{DATE} = $1;
        }
        elsif (/Input .+, ([\w|\d|,]+), from /)
        {
         my $ctn = $1;
         if ($ctn =~ /,/) { $$info{CONTAINER} = ((split(/,/,$ctn))[0]); } 
         else             { $$info{CONTAINER} = $ctn; }   
        }
    }
    close(CMD);
    
    if ($file =~ /.mp3$/) {  $$info{VIDEO_CODEC} = undef; }
    if ($file =~ /.wav$/) {  $$info{VIDEO_CODEC} = undef; }
    
 
    
	$$info{MIME_TYPE} = details($$info{CONTAINER}, $$info{VIDEO_CODEC}, $$info{AUDIO_CODEC}, 'MimeType');
	$$info{TYPE} = details($$info{CONTAINER}, $$info{VIDEO_CODEC}, $$info{AUDIO_CODEC}, 'MediaType');
	$$info{FILE_EXTENSION} = details($$info{CONTAINER}, $$info{VIDEO_CODEC}, $$info{AUDIO_CODEC}, 'FileExtension');

	if (defined($$info{MIME_TYPE}) && defined($$info{TYPE}) && defined($$info{FILE_EXTENSION}))
	{
		PDLNA::Log::log('PDLNA::Media::details() returned for '.$file.": $$info{MIME_TYPE}, $$info{TYPE}, $$info{FILE_EXTENSION}", 3, 'library');
	}
	else
	{
		PDLNA::Log::log('PDLNA::Media::details() was unable to determine details for '.$file.'.', 3, 'library');
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
