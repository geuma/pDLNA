package PDLNA::Transcode;
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

use PDLNA::Config;
use PDLNA::Media;
use PDLNA::Log;

# this represents the beatuiful codec names and their internal (in the db) possible values
my %AUDIO_CODECS = (
	'aac' => [ 'faad', 'ffaac', ],
	'ac3' => [ 'a52', 'ffac3', ],
	'flac' => [ 'ffflac', ],
	'mp3' => [ 'mp3', 'ffmp3float', ],
	'vorbis' => [ 'ffvorbis', ],
	'wav' => [ 'pcm', ],
	'wmav2' => [ 'ffwmav2', ],
);

# this represents the beatuiful codec names and their container names
my %AUDIO_CONTAINERS = (
	'aac' => 'lavfpref',
	'ac3' => 'lavf',
	'flac' => 'audio',
	'mp3' => 'audio',
	'vorbis' => 'ogg',
	'wav' => 'audio',
	'wmav2' => 'asf',
);

# this represents the beatuiful codec names and their ffmpeg decoder formats
my %FFMPEG_DECODE_FORMATS = (
	'aac' => 'aac',
	'ac3' => 'ac3',
	'flac' => 'flac',
	'mp3' => 'mp3',
	'vorbis' => 'ogg',
	'wav' => 'wav',
	'wmav2' => 'asf',
);

# this represents the beatuiful codec names and their ffmpeg encoder formats
my %FFMPEG_ENCODE_FORMATS = (
	'aac' => 'm4v',
	'ac3' => 'ac3',
	'flac' => 'flac',
	'mp3' => 'mp3',
	'vorbis' => 'ogg',
	'wav' => 'wav',
	'wmav2' => 'asf',
);

# this represents the beautiful codec names and their ffmpeg decode codecs
my %FFMPEG_AUDIO_DECODE_CODECS = (
	'aac' => 'aac',
	'ac3' => 'ac3',
	'flac' => 'flac',
	'mp3' => 'mp3',
	'vorbis' => 'vorbis',
	'wav' => 'pcm_s16le',
	'wmav2' => 'wmav2',
);

# this represents the beautiful codec names and their ffmpeg encode codecs
my %FFMPEG_AUDIO_ENCODE_CODECS = (
	'aac' => 'libfaac',
	'ac3' => 'ac3',
	'flac' => 'flac',
	'mp3' => 'libmp3lame',
	'vorbis' => 'libvorbis',
	'wav' => 'pcm_s16le',
	'wmav2' => 'wmav2',
);

my %FFMPEG_AUDIO_ENCODE_PARAMS = (
	'aac' => [],
	'ac3' => [],
	'flac' => [],
	'mp3' => [],
	'vorbis' => [],
	'wav' => [],
	'wmav2' => [ '-ab 32k', ],
);

sub is_supported_audio_decode_codec
{
	my $codec = shift;

	return $FFMPEG_AUDIO_DECODE_CODECS{$codec} if defined($FFMPEG_AUDIO_DECODE_CODECS{$codec});
	return undef;
}

sub is_supported_audio_encode_codec
{
	my $codec = shift;

	return $FFMPEG_AUDIO_ENCODE_CODECS{$codec} if defined($FFMPEG_AUDIO_ENCODE_CODECS{$codec});
	return undef;
}

sub get_decode_format_by_audio_codec
{
	my $codec = shift;

	return $FFMPEG_DECODE_FORMATS{$codec} if defined($FFMPEG_DECODE_FORMATS{$codec});
	return undef;
}

sub get_encode_format_by_audio_codec
{
	my $codec = shift;

	return $FFMPEG_ENCODE_FORMATS{$codec} if defined($FFMPEG_ENCODE_FORMATS{$codec});
	return undef;
}

sub shall_we_transcode
{
	my $media_data = shift;
	my $client_data = shift;

	if ($CONFIG{'LOW_RESOURCE_MODE'} == 1 || $$media_data{'external'} != 0 || !defined($$media_data{'container'}))
	{
		return 0;
	}

	PDLNA::Log::log('Looking for a matching Transcoding Profile for Container: '.$$media_data{'container'}.', AudioCodec: '.$$media_data{'audio_codec'}.'.', 2, 'transcoding');

	foreach my $profile (@{$CONFIG{'TRANSCODING_PROFILES'}})
	{
		next if $$media_data{'media_type'} ne $profile->{'MediaType'};

		my $matched_profile = 0;
		if ($$media_data{'media_type'} eq 'audio')
		{
			if (grep(/^$$media_data{'audio_codec'}$/, @{$AUDIO_CODECS{$profile->{'AudioCodecIn'}}}))
			{
				$matched_profile = 1;
			}
		}
		elsif ($$media_data{'media_type'} eq 'video')
		{
			next;
		}
		else
		{
			next;
		}
		next if $matched_profile == 0;

		my $matched_ip = 0;
		foreach my $ip (@{$$profile{'ClientIPs'}})
		{
			$matched_ip++ if $ip->match($$client_data{'ip'});
		}
		next if $matched_ip == 0;

		if ($$media_data{'media_type'} eq 'audio')
		{
			PDLNA::Log::log('Found a matching Transcoding Profile with Name: '.$profile->{'Name'}.'.', 2, 'transcoding');

			$$media_data{'audio_codec'} = $AUDIO_CODECS{$profile->{'AudioCodecOut'}}->[0];
			$$media_data{'container'} = $AUDIO_CONTAINERS{$profile->{'AudioCodecOut'}};
			$$media_data{'file_extension'} = PDLNA::Media::details($$media_data{'container'}, undef, $$media_data{'audio_codec'}, 'FileExtension');
			$$media_data{'mime_type'} = PDLNA::Media::details($$media_data{'container'}, undef, $$media_data{'audio_codec'}, 'MimeType');
			PDLNA::Log::log("$$media_data{'container'}, $$media_data{'audio_codec'}, $$media_data{'file_extension'}, $$media_data{'mime_type'}", 3, 'transcoding');

			$$media_data{'command'} = get_transcode_command($media_data, $profile->{'AudioCodecOut'});

			return 1;
		}
	}
	return 0;
}

sub get_transcode_command
{
	my $media_data = shift;
	my $audio_codec = shift;

	my $command = $CONFIG{'FFMPEG_BIN'}.' -i "'.$$media_data{'fullname'}.'"';
	$command .= ' -acodec '.$FFMPEG_AUDIO_ENCODE_CODECS{$audio_codec}.' ';
	if (scalar @{$FFMPEG_AUDIO_ENCODE_PARAMS{$audio_codec}} > 0)
	{
		$command .= join(' ', @{$FFMPEG_AUDIO_ENCODE_PARAMS{$audio_codec}});
	}
	$command .= ' -f '.$FFMPEG_ENCODE_FORMATS{$audio_codec};
	$command .= ' pipe: 2>/dev/null';

	PDLNA::Log::log('Command for Transcoding Profile: '.$command.'.', 3, 'transcoding');

	return $command;
}

sub get_ffmpeg_formats
{
	my $ffmpeg_bin = shift;
	my $decode = shift;
	my $encode = shift;

	open(CMD, $CONFIG{'FFMPEG_BIN'}.' -formats 2>&1 |');
	my @output = <CMD>;
	close(CMD);

	unless ($output[0] =~ /^ffmpeg\s+version\s+(.+),\scopyright/i)
	{
		return 0;
	}

	foreach my $line (@output)
	{
		if ($line =~ /\s+([DE\s]{2})\s([a-z0-9\_]+)\s+/)
		{
			my $support = $1;
			my $codec = $2;

			next if !defined($support);
			next if !defined($codec);

			if (substr($support, 0, 1) eq 'D')
			{
				push(@{$decode}, $codec);
			}
			if (substr($support, 1, 1) eq 'E')
			{
				push(@{$encode}, $codec);
			}
		}
	}

	return 1;
}

sub get_ffmpeg_codecs
{
	my $ffmpeg_bin = shift;
	my $audio_decode = shift;
	my $audio_encode = shift;
	my $video_decode = shift;
	my $video_encode = shift;

	my $exitcode = system($CONFIG{'FFMPEG_BIN'}.' -codecs > /dev/null 2>&1'); # FIX ME for WINDOWS
	if (defined($exitcode) && $exitcode == 0)
	{
		open(CMD, $CONFIG{'FFMPEG_BIN'}.' -codecs 2>&1 |');
	}
	else
	{
		open(CMD, $CONFIG{'FFMPEG_BIN'}.' -formats 2>&1 |');
	}
	my @output = <CMD>;
	close(CMD);

	unless ($output[0] =~ /^ffmpeg\s+version\s+(.+),\scopyright/i)
	{
		return 0;
	}

	foreach my $line (@output)
	{
		if ($line =~ /\s+([A-Z\s]{6})\s([a-z0-9\_]+)\s+/)
		{
			my $support = $1;
			my $codec = $2;

			next if !defined($support);
			next if !defined($codec);

			if (substr($support, 2, 1) eq 'A') # audio codecs
			{
				# $codec = PDLNA::Media::audio_codec_by_beautiful_name($codec);
				# next unless defined($codec);

				if (substr($support, 0, 1) eq 'D')
				{
					push(@{$audio_decode}, $codec);
				}
				if (substr($support, 1, 1) eq 'E')
				{
					push(@{$audio_encode}, $codec);
				}
			}
			elsif (substr($support, 2, 1) eq 'V') # video codecs
			{
				# TODO transcoding profiles for videos
			}
		}
	}

	return 1;
}

1;
